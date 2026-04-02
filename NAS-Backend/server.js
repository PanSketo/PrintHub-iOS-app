const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const https = require('https');
const http = require('http');
const { spawn } = require('child_process');
const { PassThrough } = require('stream');
const mqtt = require('mqtt');
const ftp = require('basic-ftp');
const AdmZip = require('adm-zip');

// Thumbnail cache directory (persists across restarts, cleared on reboot)
const THUMB_CACHE = path.join(os.tmpdir(), 'ph_thumbs');
fs.mkdirSync(THUMB_CACHE, { recursive: true });

const app = express();
const PORT = process.env.PORT || 3456;
const API_KEY = process.env.API_KEY || 'change-this-to-a-strong-random-key';

if (!process.env.API_KEY || process.env.API_KEY === 'change-this-to-a-strong-random-key') {
  console.error('❌ API_KEY environment variable must be set to a strong secret key');
  process.exit(1);
}
const PRINTER_IP           = process.env.PRINTER_IP           || '';
const PRINTER_ACCESS_CODE  = process.env.PRINTER_ACCESS_CODE  || '';
const PRINTER_SERIAL       = process.env.PRINTER_SERIAL       || '';
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'data', 'filaments.db');
// Optional: set to your DDNS / public URL so mirrored image URLs work outside the home network.
// Example: BASE_URL=http://myhome.ddns.net:3456
// If unset, the URL is inferred from the incoming request (local IP only).
const BASE_URL = (process.env.BASE_URL || '').replace(/\/$/, '');

// Ensure data directory exists
const dataDir = path.dirname(DB_PATH);
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

// Images directory for mirrored spool photos
const imagesDir = path.join(dataDir, 'images');
if (!fs.existsSync(imagesDir)) fs.mkdirSync(imagesDir, { recursive: true });

// Init DB
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

// Create / migrate tables — each run individually so partial failures don't block startup
[
  `CREATE TABLE IF NOT EXISTS filaments (
    id TEXT PRIMARY KEY,
    data TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  )`,
  `CREATE TABLE IF NOT EXISTS print_jobs (
    id TEXT PRIMARY KEY,
    filament_id TEXT NOT NULL,
    data TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
  )`,
  `CREATE TABLE IF NOT EXISTS ams_mappings (
    slot_key TEXT PRIMARY KEY,
    filament_id TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
  )`,
  `CREATE TABLE IF NOT EXISTS printer_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
  )`,
  `CREATE TABLE IF NOT EXISTS printer_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    print_name TEXT,
    reason TEXT,
    created_at TEXT DEFAULT (datetime('now'))
  )`
].forEach(sql => {
  try { db.exec(sql); } catch(e) { console.error('Table migration error:', e.message); }
});
console.log('✅ Database tables ready');


// Middleware
app.use(express.json({ limit: '10mb' }));

// Auth middleware — accepts X-API-Key header OR ?key= query param
// (?key= is required for AVPlayer and AsyncImage which cannot set custom headers)
function authenticate(req, res, next) {
  const key = req.headers['x-api-key'] || req.query.key;
  if (!key || key !== API_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// ── Public health (no auth — used by Docker healthcheck and uptime monitors) ──
app.get('/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', timestamp: new Date().toISOString() });
});

// ── Debug: walk FTP root and find timelapse folders ───────────────────────────
// GET /api/printer/ftp-tree  — lists root dirs and checks for timelapse inside each
app.get('/api/printer/ftp-tree', authenticate, async (req, res) => {
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE) {
    return res.json({ error: 'Printer not configured' });
  }
  const client = new ftp.Client();
  client.ftp.verbose = false;
  const result = { root: [], timelapsePaths: [] };
  try {
    await client.access({
      host: PRINTER_IP, port: 990, user: 'bblp',
      password: PRINTER_ACCESS_CODE, secure: 'implicit',
      secureOptions: { rejectUnauthorized: false }
    });
    const rootList = await client.list('/');
    result.root = rootList.map(f => ({ name: f.name, isDir: f.isDirectory }));

    for (const entry of rootList.filter(f => f.isDirectory && f.name !== '.' && f.name !== '..')) {
      const subPath = `/${entry.name}`;
      try {
        const subList = await client.list(subPath);
        const tl = subList.find(f => f.isDirectory && f.name.toLowerCase() === 'timelapse');
        if (tl) result.timelapsePaths.push(`${subPath}/timelapse`);
      } catch (_) {}

      // Also check 2 levels deep
      try {
        const subList = await client.list(subPath);
        for (const sub2 of subList.filter(f => f.isDirectory && f.name !== '.' && f.name !== '..')) {
          try {
            const deep = await client.list(`${subPath}/${sub2.name}`);
            const tl2 = deep.find(f => f.isDirectory && f.name.toLowerCase() === 'timelapse');
            if (tl2) result.timelapsePaths.push(`${subPath}/${sub2.name}/timelapse`);
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Also check root-level timelapse
    const rootTl = rootList.find(f => f.isDirectory && f.name.toLowerCase() === 'timelapse');
    if (rootTl) result.timelapsePaths.unshift('/timelapse');

    res.json(result);
  } catch (err) {
    res.json({ error: err.message, result });
  } finally {
    client.close();
  }
});

// ── Debug: dump printer_state table ──────────────────────────────────────────
app.get('/api/printer/debug', authenticate, (req, res) => {
  try {
    db.exec(`CREATE TABLE IF NOT EXISTS printer_state (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT DEFAULT (datetime('now')))`);
    const rows = db.prepare('SELECT key, value, updated_at FROM printer_state').all();
    res.json({ rows, count: rows.length });
  } catch (err) {
    res.json({ error: err.message, rows: [] });
  }
});

// Serve mirrored images — no auth so UIImage/AsyncImage can load them directly
app.use('/images', express.static(imagesDir));

// CORS for local dev — must be before authenticate so 401 responses include CORS headers
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type, X-API-Key');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

app.use(authenticate);

// ── Authenticated health (iOS uses this to verify both connectivity AND API key) ──
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', timestamp: new Date().toISOString() });
});

// ── Filaments ────────────────────────────────────────────────────────────────
// GET all filaments
app.get('/api/filaments', (req, res) => {
  try {
    const rows = db.prepare('SELECT data FROM filaments ORDER BY created_at DESC').all();
    const filaments = rows.map(r => JSON.parse(r.data));
    res.json(filaments);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET single filament
app.get('/api/filaments/:id', (req, res) => {
  try {
    const row = db.prepare('SELECT data FROM filaments WHERE id = ?').get(req.params.id);
    if (!row) return res.status(404).json({ error: 'Not found' });
    res.json(JSON.parse(row.data));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST add filament
app.post('/api/filaments', (req, res) => {
  try {
    const filament = req.body;
    if (!filament.id) filament.id = crypto.randomUUID();
    db.prepare(`
      INSERT INTO filaments (id, data, created_at, updated_at)
      VALUES (?, ?, datetime('now'), datetime('now'))
    `).run(filament.id, JSON.stringify(filament));
    res.status(201).json(filament);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT update filament
app.put('/api/filaments/:id', (req, res) => {
  try {
    const filament = req.body;
    filament.id = req.params.id;
    const result = db.prepare(`
      INSERT INTO filaments (id, data, created_at, updated_at)
      VALUES (?, ?, datetime('now'), datetime('now'))
      ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = datetime('now')
    `).run(filament.id, JSON.stringify(filament));
    res.json(filament);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE filament
app.delete('/api/filaments/:id', (req, res) => {
  try {
    db.prepare('DELETE FROM filaments WHERE id = ?').run(req.params.id);
    db.prepare('DELETE FROM print_jobs WHERE filament_id = ?').run(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Print Jobs ───────────────────────────────────────────────────────────────
// GET all print jobs
app.get('/api/printjobs', (req, res) => {
  try {
    const rows = db.prepare('SELECT data FROM print_jobs ORDER BY created_at DESC').all();
    res.json(rows.map(r => JSON.parse(r.data)));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET print jobs for a specific filament
app.get('/api/printjobs/filament/:filamentId', (req, res) => {
  try {
    const rows = db.prepare('SELECT data FROM print_jobs WHERE filament_id = ? ORDER BY created_at DESC').all(req.params.filamentId);
    res.json(rows.map(r => JSON.parse(r.data)));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST add print job
app.post('/api/printjobs', (req, res) => {
  try {
    const job = req.body;
    if (!job.id) job.id = crypto.randomUUID();
    db.prepare(`
      INSERT INTO print_jobs (id, filament_id, data, created_at)
      VALUES (?, ?, ?, datetime('now'))
    `).run(job.id, job.filamentId, JSON.stringify(job));
    res.status(201).json(job);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Stats ─────────────────────────────────────────────────────────────────────
app.get('/api/stats', (req, res) => {
  try {
    const filaments = db.prepare('SELECT data FROM filaments').all().map(r => JSON.parse(r.data));
    const jobs = db.prepare('SELECT data FROM print_jobs').all().map(r => JSON.parse(r.data));

    const totalSpend = filaments.reduce((s, f) => s + (f.pricePaid || 0), 0);
    const totalWeightRemaining = filaments.reduce((s, f) => s + (f.remainingWeightG || 0), 0);
    const totalWeightUsed = jobs.reduce((s, j) => s + (j.weightUsedG || 0), 0);
    const lowStock = filaments.filter(f => f.remainingWeightG < 200 && f.remainingWeightG > 0).length;

    res.json({
      totalFilaments: filaments.length,
      totalPrintJobs: jobs.length,
      totalSpend,
      totalWeightRemaining,
      totalWeightUsed,
      lowStockCount: lowStock
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Full App Backup ────────────────────────────────────────────────────────────
const BACKUP_PATH = path.join(dataDir, 'printhub-backup.json');

// GET /api/backup — download the latest full backup JSON
app.get('/api/backup', authenticate, (req, res) => {
  if (!fs.existsSync(BACKUP_PATH)) {
    return res.status(404).json({ error: 'No backup found on NAS' });
  }
  res.setHeader('Content-Type', 'application/json');
  res.sendFile(path.resolve(BACKUP_PATH));
});

// POST /api/backup — save a full backup (sent as JSON body from the app)
app.post('/api/backup', authenticate, (req, res) => {
  try {
    const backup = { ...req.body, savedAt: new Date().toISOString() };
    fs.writeFileSync(BACKUP_PATH, JSON.stringify(backup));
    console.log(`📦 Full backup saved at ${backup.savedAt}`);
    res.json({ ok: true, savedAt: backup.savedAt });
  } catch (e) {
    console.error('Backup error:', e);
    res.status(500).json({ error: e.message });
  }
});

// POST /api/restore — bulk-replace filaments and print jobs from a backup
app.post('/api/restore', authenticate, (req, res) => {
  const { filaments = [], printJobs = [] } = req.body;
  try {
    db.prepare('DELETE FROM filaments').run();
    const insertF = db.prepare(
      'INSERT OR REPLACE INTO filaments (id, data, created_at, updated_at) VALUES (?, ?, ?, ?)'
    );
    const now = new Date().toISOString();
    for (const f of filaments) {
      insertF.run(f.id, JSON.stringify(f), now, now);
    }

    db.prepare('DELETE FROM print_jobs').run();
    const insertJ = db.prepare(
      'INSERT OR REPLACE INTO print_jobs (id, filament_id, data, created_at) VALUES (?, ?, ?, ?)'
    );
    for (const j of printJobs) {
      insertJ.run(j.id, j.filamentId || j.filament_id || '', JSON.stringify(j), now);
    }

    console.log(`🔄 Restore complete: ${filaments.length} filaments, ${printJobs.length} jobs`);
    res.json({ ok: true, filaments: filaments.length, printJobs: printJobs.length });
  } catch (e) {
    console.error('Restore error:', e);
    res.status(500).json({ error: e.message });
  }
});

// ── AMS Mappings ─────────────────────────────────────────────────────────────
// GET all AMS slot → filament mappings
app.get('/api/ams/mappings', (req, res) => {
  try {
    db.exec(`CREATE TABLE IF NOT EXISTS ams_mappings (
      slot_key TEXT PRIMARY KEY,
      filament_id TEXT NOT NULL,
      updated_at TEXT DEFAULT (datetime('now'))
    )`);
    const rows = db.prepare('SELECT slot_key, filament_id FROM ams_mappings').all();
    const mappings = {};
    rows.forEach(r => { mappings[r.slot_key] = r.filament_id; });
    res.json(mappings);
  } catch (err) {
    res.json({});  // Return empty object, never 500
  }
});

// PUT update a single AMS slot mapping
app.put('/api/ams/mappings/:slotKey', (req, res) => {
  try {
    const { slotKey } = req.params;
    const { filamentId } = req.body;
    if (!filamentId) return res.status(400).json({ error: 'filamentId required' });
    db.prepare(`
      INSERT INTO ams_mappings (slot_key, filament_id, updated_at)
      VALUES (?, ?, datetime('now'))
      ON CONFLICT(slot_key) DO UPDATE SET filament_id = excluded.filament_id, updated_at = datetime('now')
    `).run(slotKey, filamentId);
    res.json({ slot_key: slotKey, filament_id: filamentId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE an AMS slot mapping
app.delete('/api/ams/mappings/:slotKey', (req, res) => {
  try {
    db.prepare('DELETE FROM ams_mappings WHERE slot_key = ?').run(req.params.slotKey);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Printer State ─────────────────────────────────────────────────────────────
// GET current printer live state (polled by iOS app)
// Returns graceful empty state if mqtt-bridge has not connected yet
app.get('/api/printer/state', (req, res) => {
  try {
    // Ensure table exists (safe migration for existing databases)
    db.exec(`CREATE TABLE IF NOT EXISTS printer_state (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT DEFAULT (datetime('now'))
    )`);
    db.exec(`CREATE TABLE IF NOT EXISTS ams_mappings (
      slot_key TEXT PRIMARY KEY,
      filament_id TEXT NOT NULL,
      updated_at TEXT DEFAULT (datetime('now'))
    )`);

    const liveRow = db.prepare("SELECT value FROM printer_state WHERE key = 'live'").get();
    const connRow = db.prepare("SELECT value FROM printer_state WHERE key = 'connected'").get();
    res.json({
      connected: connRow ? JSON.parse(connRow.value) : false,
      live: liveRow ? JSON.parse(liveRow.value) : null,
      bridge_active: liveRow !== undefined
    });
  } catch (err) {
    // Always return valid JSON — never a 500 — so iOS shows offline state gracefully
    res.json({ connected: false, live: null, bridge_active: false, error: err.message });
  }
});

// ── Printer Print Control ─────────────────────────────────────────────────────
// POST /api/printer/command — sends a control command to the printer via MQTT
// Body: { "command": "pause"|"resume"|"stop"|"set_speed"|"set_nozzle_temp"|"set_bed_temp", "value": "..." }

app.post('/api/printer/command', (req, res) => {
  const { command, value } = req.body || {};
  if (!command) return res.status(400).json({ error: 'command is required' });
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE || !PRINTER_SERIAL) {
    return res.status(503).json({ error: 'Printer not configured' });
  }

  let mqttPayload;
  switch (command) {
    case 'pause':
      mqttPayload = { print: { sequence_id: '1', command: 'pause' } };
      break;
    case 'resume':
      mqttPayload = { print: { sequence_id: '1', command: 'resume' } };
      break;
    case 'stop':
      mqttPayload = { print: { sequence_id: '1', command: 'stop' } };
      break;
    case 'set_speed':
      if (!value) return res.status(400).json({ error: 'value required for set_speed (1-4)' });
      mqttPayload = { print: { sequence_id: '1', command: 'print_speed', param: String(value) } };
      break;
    case 'set_nozzle_temp':
      if (!value) return res.status(400).json({ error: 'value required for set_nozzle_temp' });
      mqttPayload = { print: { sequence_id: '1', command: 'gcode_line', param: `M104 S${value} \n` } };
      break;
    case 'set_bed_temp':
      if (!value) return res.status(400).json({ error: 'value required for set_bed_temp' });
      mqttPayload = { print: { sequence_id: '1', command: 'gcode_line', param: `M140 S${value} \n` } };
      break;
    default:
      return res.status(400).json({ error: `Unknown command: ${command}` });
  }

  console.log(`[printer] Command: ${command}${value !== undefined ? ' value=' + value : ''}`);

  const client = mqtt.connect(`mqtts://${PRINTER_IP}:8883`, {
    username: 'bblp',
    password: PRINTER_ACCESS_CODE,
    clientId: `filament_cmd_${crypto.randomBytes(4).toString('hex')}`,
    rejectUnauthorized: false,
    connectTimeout: 10000,
    reconnectPeriod: 0
  });

  let settled = false;
  const settle = (err) => {
    if (settled) return;
    settled = true;
    if (err) {
      console.error('[printer] Command error:', err.message);
      try { client.end(true); } catch (_) {}
      if (!res.headersSent) res.status(500).json({ error: err.message });
    } else {
      if (!res.headersSent) res.json({ ok: true });
    }
  };

  const timer = setTimeout(() => settle(new Error('MQTT connection timed out')), 12000);

  client.on('connect', () => {
    clearTimeout(timer);
    client.publish(`device/${PRINTER_SERIAL}/request`, JSON.stringify(mqttPayload), () => {
      setTimeout(() => { try { client.end(); } catch (_) {} settle(null); }, 300);
    });
  });

  client.on('error', (err) => { clearTimeout(timer); settle(err); });
});

// ── Printer Chamber Light ─────────────────────────────────────────────────────
// GET  /api/printer/light   — returns { on: bool, known: bool }
// POST /api/printer/light   — body: { "on": bool } — sends ledctrl via MQTT

app.get('/api/printer/light', (req, res) => {
  try {
    const row = db.prepare("SELECT value FROM printer_state WHERE key = 'chamber_light'").get();
    if (!row) return res.json({ on: false, known: false });
    res.json({ on: JSON.parse(row.value) === true, known: true });
  } catch (err) {
    res.json({ on: false, known: false });
  }
});

app.post('/api/printer/light', (req, res) => {
  const on = req.body?.on;
  if (typeof on !== 'boolean') return res.status(400).json({ error: 'Body must be { "on": true/false }' });
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE || !PRINTER_SERIAL) {
    return res.status(503).json({ error: 'Printer not configured' });
  }

  console.log(`[light] Connecting to printer MQTT to turn light ${on ? 'ON' : 'OFF'}`);

  const client = mqtt.connect(`mqtts://${PRINTER_IP}:8883`, {
    username: 'bblp',
    password: PRINTER_ACCESS_CODE,
    clientId: `filament_light_${crypto.randomBytes(4).toString('hex')}`,
    rejectUnauthorized: false,
    connectTimeout: 10000,
    reconnectPeriod: 0
  });

  let settled = false;
  const settle = (err) => {
    if (settled) return;
    settled = true;
    if (err) {
      console.error('[light] Error:', err.message);
      try { client.end(true); } catch (_) {}
      if (!res.headersSent) res.status(500).json({ error: err.message });
    } else {
      if (!res.headersSent) res.json({ ok: true, on });
    }
  };

  const timer = setTimeout(() => settle(new Error('MQTT connection timed out')), 12000);

  client.on('connect', () => {
    console.log('[light] MQTT connected, publishing ledctrl command');
    clearTimeout(timer);
    const cmd = {
      system: {
        sequence_id: '1001',
        command: 'ledctrl',
        led_node: 'chamber_light',
        led_mode: on ? 'on' : 'off',
        led_on_time: 500,
        led_off_time: 500,
        loop_times: 1,
        interval_time: 1000
      }
    };
    client.publish(`device/${PRINTER_SERIAL}/request`, JSON.stringify(cmd), () => {
      console.log('[light] Command published, closing connection');
      db.prepare(`INSERT INTO printer_state (key, value, updated_at) VALUES ('chamber_light', ?, datetime('now'))
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`)
        .run(JSON.stringify(on));
      // Give the packet time to flush before closing
      setTimeout(() => { try { client.end(); } catch (_) {} settle(null); }, 300);
    });
  });

  client.on('error', (err) => { clearTimeout(timer); settle(err); });
});

// ── Printer File Browser ──────────────────────────────────────────────────────
// GET /api/printer/files?path=/   — lists files on the printer's internal/USB storage
// Connects to the printer via implicit FTPS (port 990, user bblp, pass ACCESS_CODE).
// Directories are returned first, then files, both sorted alphabetically.
app.get('/api/printer/files', async (req, res) => {
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE) {
    return res.status(503).json({ error: 'Printer not configured (PRINTER_IP / PRINTER_ACCESS_CODE missing)' });
  }
  const dirPath = (req.query.path || '/').replace(/\/{2,}/g, '/');
  const client = new ftp.Client();
  client.ftp.verbose = false;
  try {
    await client.access({
      host: PRINTER_IP,
      port: 990,
      user: 'bblp',
      password: PRINTER_ACCESS_CODE,
      secure: 'implicit',
      secureOptions: { rejectUnauthorized: false }
    });
    const list = await client.list(dirPath);
    const files = list
      .filter(f => f.name !== '.' && f.name !== '..')
      .map(f => {
        const sep = dirPath.endsWith('/') ? '' : '/';
        return {
          name: f.name,
          path: `${dirPath}${sep}${f.name}`,
          isDirectory: f.isDirectory,
          size: f.isDirectory ? null : (f.size || null),
          modifiedDate: f.rawModifiedAt || null
        };
      })
      .sort((a, b) => {
        if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.localeCompare(b.name);
      });
    res.json(files);
  } catch (err) {
    console.error('[files] FTP error:', err.message);
    res.status(500).json({ error: err.message });
  } finally {
    client.close();
  }
});

// ── Thumbnail ─────────────────────────────────────────────────────────────────
// GET /api/printer/thumbnail?path=/sdcard/...file.3mf[&key=APIKEY]
// Downloads the .3mf (ZIP) from the printer, extracts the first PNG thumbnail
// found under Metadata/, caches it in /tmp/ph_thumbs/, and returns it as PNG.
// Accepts ?key= query param for compatibility with AsyncImage (no custom headers).
app.get('/api/printer/thumbnail', async (req, res) => {
  // Auth: accept header OR ?key= query param
  const keyParam = req.query.key;
  if (keyParam && keyParam !== API_KEY) return res.status(401).json({ error: 'Unauthorized' });
  if (!keyParam && req.headers['x-api-key'] !== API_KEY) return res.status(401).json({ error: 'Unauthorized' });

  const filePath = req.query.path;
  if (!filePath || !filePath.toLowerCase().includes('.3mf')) {
    return res.status(400).json({ error: 'path must point to a .3mf file' });
  }
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE) {
    return res.status(503).json({ error: 'Printer not configured' });
  }

  // Cache key = base64 of path
  const cacheKey = Buffer.from(filePath).toString('base64url').replace(/[^a-zA-Z0-9_-]/g, '_') + '.png';
  const cachePath = path.join(THUMB_CACHE, cacheKey);

  if (fs.existsSync(cachePath)) {
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    return res.sendFile(cachePath);
  }

  const tempFile = path.join(os.tmpdir(), `ph_${Date.now()}_${Math.random().toString(36).slice(2)}.3mf`);
  const client = new ftp.Client();
  client.ftp.verbose = false;
  try {
    await client.access({
      host: PRINTER_IP, port: 990, user: 'bblp',
      password: PRINTER_ACCESS_CODE, secure: 'implicit',
      secureOptions: { rejectUnauthorized: false }
    });
    await client.downloadTo(tempFile, filePath);
    client.close();

    const zip = new AdmZip(tempFile);
    const entries = zip.getEntries();

    // Find first PNG under Metadata/ (plate_1.png, thumbnail.png, etc.)
    const thumb = entries.find(e => {
      const n = e.entryName.toLowerCase();
      return n.startsWith('metadata/') && n.endsWith('.png') && !e.isDirectory;
    }) || entries.find(e => e.entryName.toLowerCase().endsWith('.png') && !e.isDirectory);

    if (!thumb) {
      try { fs.unlinkSync(tempFile); } catch {}
      return res.status(404).json({ error: 'No thumbnail in this .3mf file' });
    }

    const imgData = zip.readFile(thumb);
    fs.writeFileSync(cachePath, imgData);
    try { fs.unlinkSync(tempFile); } catch {}

    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.send(imgData);
  } catch (err) {
    try { fs.unlinkSync(tempFile); } catch {}
    client.close();
    console.error('[thumbnail] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── Timelapse List ────────────────────────────────────────────────────────────
// GET /api/printer/timelapse  — searches known timelapse paths in order:
//   /usb/timelapse  →  /sdcard/timelapse  →  /timelapse
// Returns files from the first path that exists and contains .mp4 files.
app.get('/api/printer/timelapse', async (req, res) => {
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE) {
    return res.status(503).json({ error: 'Printer not configured' });
  }
  const client = new ftp.Client();
  client.ftp.verbose = false;
  try {
    await client.access({
      host: PRINTER_IP, port: 990, user: 'bblp',
      password: PRINTER_ACCESS_CODE, secure: 'implicit',
      secureOptions: { rejectUnauthorized: false }
    });

    // Build candidate paths dynamically from FTP root + known static paths
    const staticPaths = ['/usb/timelapse', '/sdcard/timelapse', '/timelapse'];
    const dynamicPaths = [];
    try {
      const root = await client.list('/');
      for (const entry of root.filter(f => f.isDirectory && f.name !== '.' && f.name !== '..')) {
        dynamicPaths.push(`/${entry.name}/timelapse`);
      }
    } catch (_) {}

    const searchPaths = [...new Set([...staticPaths, ...dynamicPaths])];
    console.log('[timelapse] Searching paths:', searchPaths);

    for (const dir of searchPaths) {
      try {
        const list = await client.list(dir);
        const files = list
          .filter(f => f.name !== '.' && f.name !== '..' && f.name.toLowerCase().endsWith('.mp4'))
          .map(f => ({
            name: f.name,
            path: `${dir}/${f.name}`,
            size: f.size || null,
            modifiedDate: f.rawModifiedAt || null
          }))
          .sort((a, b) => b.name.localeCompare(a.name));

        console.log(`[timelapse] ✓ Found ${files.length} file(s) in ${dir}`);
        if (files.length > 0) return res.json(files); // only stop if files found
      } catch (dirErr) {
        console.log(`[timelapse] ✗ ${dir}: ${dirErr.message}`);
      }
    }

    console.warn('[timelapse] No timelapse folder found in any path');
    res.json([]);
  } catch (err) {
    console.error('[timelapse] FTP connection error:', err.message);
    res.status(500).json({ error: err.message });
  } finally {
    client.close();
  }
});

// ── Timelapse Stream ──────────────────────────────────────────────────────────
// GET /api/printer/timelapse/stream?path=/timelapse/foo.mp4
// Downloads the FTP file to a temp file, then serves it over HTTP.
// Auth: X-API-Key header OR ?key= query param (needed for AVPlayer URLs).
app.get('/api/printer/timelapse/stream', async (req, res) => {
  console.log(`[timelapse/stream] Request: path=${req.query.path} keyProvided=${!!req.query.key}`);

  // Accept key as query param for AVPlayer compatibility
  const keyParam = req.query.key;
  if (keyParam && keyParam !== API_KEY) {
    console.warn('[timelapse/stream] 401 key mismatch');
    return res.status(401).json({ error: 'Unauthorized' });
  }
  if (!keyParam && req.headers['x-api-key'] !== API_KEY) {
    console.warn('[timelapse/stream] 401 no key');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const filePath = req.query.path;
  if (!filePath || !filePath.endsWith('.mp4') || filePath.includes('..')) {
    console.warn(`[timelapse/stream] 400 invalid path: ${filePath}`);
    return res.status(400).json({ error: 'Invalid path — must be an .mp4 file path' });
  }
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE) {
    console.warn('[timelapse/stream] 503 printer not configured');
    return res.status(503).json({ error: 'Printer not configured' });
  }

  // Use a unique temp file to avoid collisions between concurrent requests
  const tmpPath = path.join(THUMB_CACHE, `tl_${Date.now()}_${Math.random().toString(36).slice(2)}.mp4`);
  const client = new ftp.Client();
  client.ftp.verbose = false;
  try {
    console.log(`[timelapse/stream] Connecting to ${PRINTER_IP}:990 for ${filePath}`);
    await client.access({
      host: PRINTER_IP,
      port: 990,
      user: 'bblp',
      password: PRINTER_ACCESS_CODE,
      secure: 'implicit',
      secureOptions: { rejectUnauthorized: false }
    });

    // Download full file to temp path first — more reliable than piping PassThrough
    await client.downloadTo(tmpPath, filePath);
    client.close();
    console.log(`[timelapse/stream] FTP download complete: ${tmpPath}`);

    const fileName = filePath.split('/').pop();
    res.setHeader('Content-Disposition', `inline; filename="${fileName}"`);

    // sendFile handles Content-Type, Content-Length, Accept-Ranges, and Range (206)
    // automatically — AVPlayer requires range request support to stream video
    res.sendFile(tmpPath, { headers: { 'Content-Type': 'video/mp4' } }, (err) => {
      fs.unlink(tmpPath, () => {});
      if (err && !res.headersSent) res.status(500).json({ error: err.message });
    });
  } catch (err) {
    console.error('[timelapse/stream] Error:', err.message);
    try { client.close(); } catch (_) {}
    try { fs.unlinkSync(tmpPath); } catch (_) {}
    if (!res.headersSent) res.status(500).json({ error: err.message });
  }
});

// ── Start Print ───────────────────────────────────────────────────────────────
// POST /api/printer/print   — body: { "file_path": "/sdcard/benchy.3mf" }
// Sends a project_file print command to the printer via MQTT.
// The FTP URL uses the double-slash convention Bambu expects: ftp://IP//sdcard/file.3mf
app.post('/api/printer/print', (req, res) => {
  const { file_path } = req.body || {};
  if (!file_path) return res.status(400).json({ error: 'file_path is required' });
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE || !PRINTER_SERIAL) {
    return res.status(503).json({ error: 'Printer not configured' });
  }

  const fileName    = file_path.split('/').filter(Boolean).pop() || file_path;
  const subtaskName = fileName.replace(/\.(gcode\.3mf|3mf|gcode)$/i, '');
  // Bambu FTP URL: ftp://IP//absolute/path (double slash = absolute)
  const normalised  = file_path.startsWith('/') ? file_path.slice(1) : file_path;
  const ftpUrl      = `ftp://${PRINTER_IP}//${normalised}`;

  const mqttPayload = {
    print: {
      sequence_id:    String(Date.now()),
      command:        'project_file',
      param:          'Metadata/plate_1.gcode',
      subtask_name:   subtaskName,
      url:            ftpUrl,
      bed_type:       'auto',
      timelapse:      false,
      bed_leveling:   true,
      flow_cali:      false,
      vibration_cali: true,
      layer_inspect:  false,
      use_ams:        false
    }
  };

  console.log(`[printer] Starting print: ${fileName}  url=${ftpUrl}`);

  const client = mqtt.connect(`mqtts://${PRINTER_IP}:8883`, {
    username:        'bblp',
    password:        PRINTER_ACCESS_CODE,
    clientId:        `filament_print_${crypto.randomBytes(4).toString('hex')}`,
    rejectUnauthorized: false,
    connectTimeout:  10000,
    reconnectPeriod: 0
  });

  let settled = false;
  const settle = (err) => {
    if (settled) return;
    settled = true;
    if (err) {
      console.error('[printer] Print start error:', err.message);
      try { client.end(true); } catch (_) {}
      if (!res.headersSent) res.status(500).json({ error: err.message });
    } else {
      if (!res.headersSent) res.json({ ok: true });
    }
  };

  const timer = setTimeout(() => settle(new Error('MQTT connection timed out')), 12000);

  client.on('connect', () => {
    clearTimeout(timer);
    client.publish(`device/${PRINTER_SERIAL}/request`, JSON.stringify(mqttPayload), () => {
      setTimeout(() => { try { client.end(); } catch (_) {} settle(null); }, 300);
    });
  });

  client.on('error', (err) => { clearTimeout(timer); settle(err); });
});

// ── Printer Events ────────────────────────────────────────────────────────────
// GET print lifecycle events (started / completed / failed) since a given timestamp.
// iOS polls this to fire local notifications without needing APNs.
// ?since=<ISO8601>  — returns events newer than that timestamp, oldest first (max 50)
// (no since param)  — returns the 10 most recent events, newest first
app.get('/api/printer/events', (req, res) => {
  try {
    const { since } = req.query;
    let rows;
    if (since) {
      // Strip trailing Z if present — SQLite datetime() stores without it
      const sinceClean = since.replace('Z', '').replace('T', ' ');
      rows = db.prepare(`
        SELECT id, event_type, print_name, reason, created_at
        FROM printer_events
        WHERE created_at > datetime(?)
        ORDER BY created_at ASC
        LIMIT 50
      `).all(sinceClean);
    } else {
      rows = db.prepare(`
        SELECT id, event_type, print_name, reason, created_at
        FROM printer_events
        ORDER BY created_at DESC
        LIMIT 10
      `).all();
    }
    res.json(rows.map(r => ({
      id: r.id,
      eventType: r.event_type,
      printName: r.print_name || '',
      reason: r.reason || null,
      createdAt: r.created_at.replace(' ', 'T') + 'Z'
    })));
  } catch (err) {
    res.json([]);
  }
});

// ── Untracked Prints (prints the bridge couldn't auto-log) ───────────────────
// Returns all print_untracked events so the iOS app can prompt manual weight entry.
app.get('/api/printer/untracked-prints', authenticate, (req, res) => {
  try {
    const rows = db.prepare(`
      SELECT id, print_name, reason, created_at
      FROM printer_events
      WHERE event_type = 'print_untracked'
      ORDER BY created_at DESC
    `).all();
    res.json(rows.map(r => ({
      id: r.id,
      printName: r.print_name || '',
      reason: r.reason || null,
      createdAt: r.created_at.replace(' ', 'T') + 'Z'
    })));
  } catch (err) {
    res.json([]);
  }
});

// Dismiss an untracked print event (called after user manually logs the weight).
app.delete('/api/printer/untracked-prints/:id', authenticate, (req, res) => {
  try {
    db.prepare(`DELETE FROM printer_events WHERE id = ? AND event_type = 'print_untracked'`).run(req.params.id);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Image mirroring ───────────────────────────────────────────────────────────
// Downloads a remote image URL and stores it locally so it survives link rot.
// Same URL always produces the same filename (SHA-256 of URL), acting as a cache.

function downloadImageBuffer(imageUrl, callback, redirectCount = 0) {
  if (redirectCount > 5) return callback(new Error('Too many redirects'));
  let parsedUrl;
  try { parsedUrl = new URL(imageUrl); } catch (e) { return callback(e); }
  const protocol = parsedUrl.protocol === 'https:' ? https : http;
  const req = protocol.get(imageUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; FilamentInventory/1.0)',
      'Accept': 'image/webp,image/jpeg,image/png,image/*,*/*',
    }
  }, (response) => {
    if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
      response.resume();
      const redirectUrl = new URL(response.headers.location, imageUrl).href;
      return downloadImageBuffer(redirectUrl, callback, redirectCount + 1);
    }
    if (response.statusCode !== 200) {
      response.resume();
      return callback(new Error(`HTTP ${response.statusCode}`));
    }
    const contentType = (response.headers['content-type'] || '').split(';')[0].trim();
    const chunks = [];
    response.on('data', chunk => chunks.push(chunk));
    response.on('end', () => callback(null, Buffer.concat(chunks), contentType));
    response.on('error', callback);
  });
  req.on('error', callback);
  req.setTimeout(30000, () => { req.destroy(); callback(new Error('Timeout downloading image')); });
}

function extForContentType(ct) {
  const map = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp', 'image/gif': '.gif' };
  return map[ct] || '.jpg';
}

// POST /api/images/mirror — authenticated
app.post('/api/images/mirror', (req, res) => {
  const { url: imageUrl } = req.body;
  if (!imageUrl || typeof imageUrl !== 'string') {
    return res.status(400).json({ error: 'url is required' });
  }

  const urlHash = crypto.createHash('sha256').update(imageUrl).digest('hex').slice(0, 20);
  const baseUrl = BASE_URL || (req.protocol + '://' + req.get('host'));

  // Return cached file if it already exists (skip re-download)
  for (const ext of ['.jpg', '.png', '.webp', '.gif']) {
    if (fs.existsSync(path.join(imagesDir, urlHash + ext))) {
      return res.json({ localURL: `${baseUrl}/images/${urlHash}${ext}` });
    }
  }

  downloadImageBuffer(imageUrl, (err, data, contentType) => {
    if (err) {
      console.error('Image mirror failed:', err.message);
      return res.status(502).json({ error: 'Failed to download image: ' + err.message });
    }
    const ext = extForContentType(contentType);
    const filename = urlHash + ext;
    fs.writeFile(path.join(imagesDir, filename), data, (writeErr) => {
      if (writeErr) return res.status(500).json({ error: writeErr.message });
      res.json({ localURL: `${baseUrl}/images/${filename}` });
    });
  });
});

// ── Camera Stream ─────────────────────────────────────────────────────────────
// Proxies the Bambu Lab RTSPS camera as an MJPEG-over-HTTP stream so the iOS
// app can display a live feed without needing native RTSP support.
// Auth via X-API-Key header (same as all other endpoints).
app.get('/api/camera/stream', (req, res) => {
  if (!PRINTER_IP || !PRINTER_ACCESS_CODE) {
    return res.status(503).json({ error: 'Printer camera not configured — set PRINTER_IP and PRINTER_ACCESS_CODE in docker-compose.yml' });
  }

  const boundary = 'mjpeg_frame';
  const rtspUrl = `rtsps://bblp:${PRINTER_ACCESS_CODE}@${PRINTER_IP}:322/streaming/live/1`;

  const ffmpeg = spawn('ffmpeg', [
    '-loglevel', 'warning',
    '-rtsp_transport', 'tcp',
    '-tls_verify', '0',           // Bambu Lab uses a self-signed TLS cert on RTSPS
    '-timeout', '10000000',       // 10 s socket timeout — fail fast if printer unreachable
    '-allowed_media_types', 'video',
    '-i', rtspUrl,
    '-vf', 'scale=1920:1080,deflicker=size=10:mode=am',
    '-f', 'image2pipe',
    '-vcodec', 'mjpeg',
    '-q:v', '5',   // JPEG quality 1-31, lower = better
    '-r', '30',    // 30 fps — full framerate at 1920x1080
    'pipe:1'
  ]);

  // Delay sending 200 headers until the first JPEG frame arrives.
  // If ffmpeg exits or errors before producing any frame, send 503 instead —
  // this gives the iOS app a proper error rather than an empty-body 200.
  let headersSent = false;
  let buffer = Buffer.alloc(0);
  const SOI = Buffer.from([0xFF, 0xD8]);
  const EOI = Buffer.from([0xFF, 0xD9]);

  function sendStreamHeaders() {
    if (headersSent) return;
    headersSent = true;
    res.writeHead(200, {
      'Content-Type': `multipart/x-mixed-replace; boundary=${boundary}`,
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Connection': 'keep-alive',
      'Transfer-Encoding': 'chunked'
    });
  }

  ffmpeg.stdout.on('data', (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);

    // Extract every complete JPEG frame from the accumulated buffer
    while (buffer.length >= 4) {
      const startIdx = buffer.indexOf(SOI);
      if (startIdx === -1) { buffer = Buffer.alloc(0); break; }

      const endIdx = buffer.indexOf(EOI, startIdx + 2);
      if (endIdx === -1) {
        if (startIdx > 0) buffer = buffer.slice(startIdx);
        break;
      }

      const frame = buffer.slice(startIdx, endIdx + 2);
      sendStreamHeaders();  // safe to call repeatedly — only acts on first call

      const header = `--${boundary}\r\nContent-Type: image/jpeg\r\nContent-Length: ${frame.length}\r\n\r\n`;
      if (!res.writableEnded) {
        res.write(header);
        res.write(frame);
        res.write('\r\n');
      }

      buffer = buffer.slice(endIdx + 2);
    }
  });

  let stderrLog = '';
  ffmpeg.stderr.on('data', (data) => {
    const line = data.toString().trim();
    console.error('[camera]', line);
    stderrLog += line + '\n';
  });

  ffmpeg.on('close', (code) => {
    console.log(`[camera] ffmpeg exited (code ${code})`);
    if (!headersSent) {
      // ffmpeg failed before producing a single frame — return 503 so iOS shows a real error.
      // Include the last 300 chars of stderr so the user can see the actual ffmpeg error.
      const lastErr = stderrLog.trim().split('\n').slice(-3).join(' | ').slice(-300) || null;
      let reason;
      if (code === 1 && (!lastErr || lastErr.includes('Connection refused') || lastErr.includes('timed out') || lastErr.includes('No route'))) {
        reason = `Cannot reach printer camera at ${PRINTER_IP}:322 — is the printer on and reachable from the NAS?`;
      } else {
        reason = `Camera stream failed (ffmpeg exit ${code})${lastErr ? ': ' + lastErr : ' — check NAS logs'}`;
      }
      res.status(503).json({ error: reason });
    } else if (!res.writableEnded) {
      res.end();
    }
  });

  ffmpeg.on('error', (err) => {
    console.error('[camera] ffmpeg spawn error:', err.message);
    if (!headersSent) {
      res.status(503).json({ error: 'ffmpeg not available in container — check NAS Docker logs' });
    } else if (!res.writableEnded) {
      res.end();
    }
  });

  // Kill ffmpeg when the client disconnects
  res.on('close', () => { try { ffmpeg.kill('SIGTERM'); } catch (_) {} });
});

// ── Start
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🖨️  PrintHub Backend running on port ${PORT}`);
  console.log(`📁 Database: ${DB_PATH}`);
  console.log(`🔑 API Key configured: ${API_KEY !== 'change-this-to-a-strong-random-key' ? 'YES ✅' : 'NO ❌ (change it!)'}`);
});

module.exports = app;
