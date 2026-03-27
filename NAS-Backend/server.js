const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const http = require('http');
const { spawn } = require('child_process');
const mqtt = require('mqtt');

const app = express();
const PORT = process.env.PORT || 3456;
const API_KEY = process.env.API_KEY || 'change-this-to-a-strong-random-key';
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

// Auth middleware
function authenticate(req, res, next) {
  const key = req.headers['x-api-key'];
  if (!key || key !== API_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

// ── Public health (no auth — used by Docker healthcheck and uptime monitors) ──
app.get('/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', timestamp: new Date().toISOString() });
});

// ── Debug: dump printer_state table — PUBLIC, no auth needed
app.get('/api/printer/debug', (req, res) => {
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

  const client = mqtt.connect(`mqtts://${PRINTER_IP}:8883`, {
    username: 'bblp',
    password: PRINTER_ACCESS_CODE,
    clientId: `filament_light_${crypto.randomBytes(4).toString('hex')}`,
    rejectUnauthorized: false,
    connectTimeout: 10000,
    reconnectPeriod: 0
  });

  const done = (err) => { try { client.end(true); } catch (_) {} if (!res.headersSent) err ? res.status(500).json({ error: err.message }) : res.json({ ok: true, on }); };
  const timer = setTimeout(() => done(new Error('MQTT connection timed out')), 12000);

  client.on('connect', () => {
    clearTimeout(timer);
    const cmd = {
      system: {
        sequence_id: String(Date.now()),
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
      // Optimistically persist the new state so the next GET reflects it immediately
      db.prepare(`INSERT INTO printer_state (key, value, updated_at) VALUES ('chamber_light', ?, datetime('now'))
        ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`)
        .run(JSON.stringify(on));
      done(null);
    });
  });

  client.on('error', (err) => { clearTimeout(timer); done(err); });
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
  console.log(`🧵 Filament Inventory Backend running on port ${PORT}`);
  console.log(`📁 Database: ${DB_PATH}`);
  console.log(`🔑 API Key configured: ${API_KEY !== 'change-this-to-a-strong-random-key' ? 'YES ✅' : 'NO ❌ (change it!)'}`);
});

module.exports = app;
