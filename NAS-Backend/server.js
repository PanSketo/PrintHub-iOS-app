const express = require('express');
const Database = require('better-sqlite3');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3456;
const API_KEY = process.env.API_KEY || 'change-this-to-a-strong-random-key';
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'data', 'filaments.db');

// Ensure data directory exists
const dataDir = path.dirname(DB_PATH);
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

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

// ── Health (public - no auth required for container healthcheck) ─────────────
app.get('/api/health', (req, res) => {
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

// CORS for local dev — must be before authenticate so 401 responses include CORS headers
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Content-Type, X-API-Key');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

app.use(authenticate);

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

// ── Start
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🧵 Filament Inventory Backend running on port ${PORT}`);
  console.log(`📁 Database: ${DB_PATH}`);
  console.log(`🔑 API Key configured: ${API_KEY !== 'change-this-to-a-strong-random-key' ? 'YES ✅' : 'NO ❌ (change it!)'}`);
});

module.exports = app;
