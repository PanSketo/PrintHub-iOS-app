/**
 * Bambu Lab MQTT Bridge for Filament Inventory
 * -----------------------------------------------
 * Connects to a Bambu Lab P2S printer on the local network via MQTT,
 * listens for print completion events and filament usage data,
 * then automatically creates PrintJob records in the Filament Inventory
 * database and deducts weight from the correct filament spool.
 *
 * Bambu printers use MQTT over TLS (port 8883) with credentials:
 *   username: bblp
 *   password: <printer access code>  (found in printer Settings > Network)
 */

const mqtt = require('mqtt');
const Database = require('better-sqlite3');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// ── Configuration (from environment variables) ───────────────────────────────
const PRINTER_IP        = process.env.PRINTER_IP        || '';
const PRINTER_SERIAL    = process.env.PRINTER_SERIAL    || '';   // e.g. 01S00C123456789
const PRINTER_ACCESS_CODE = process.env.PRINTER_ACCESS_CODE || ''; // 8-char code from printer screen
const DB_PATH           = process.env.DB_PATH           || path.join(__dirname, '..', 'data', 'filaments.db');
const API_KEY           = process.env.API_KEY           || '';
const POLL_INTERVAL_MS  = 5000;  // request full status every 5 seconds

// ── Validate config ───────────────────────────────────────────────────────────
if (!PRINTER_IP || !PRINTER_SERIAL || !PRINTER_ACCESS_CODE) {
  console.error('❌ Missing required environment variables:');
  console.error('   PRINTER_IP, PRINTER_SERIAL, PRINTER_ACCESS_CODE');
  console.error('   Check your docker-compose.yml');
  process.exit(1);
}

// ── Database ──────────────────────────────────────────────────────────────────
const dataDir = path.dirname(DB_PATH);
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });

const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

// Create AMS mapping and printer state tables
db.exec(`
  CREATE TABLE IF NOT EXISTS ams_mappings (
    slot_key TEXT PRIMARY KEY,   -- e.g. "ams_0_slot_1"
    filament_id TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS printer_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS filaments (
    id TEXT PRIMARY KEY,
    data TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS print_jobs (
    id TEXT PRIMARY KEY,
    filament_id TEXT NOT NULL,
    data TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
  );

  CREATE TABLE IF NOT EXISTS printer_events (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,   -- 'print_started', 'print_completed', 'print_failed'
    print_name TEXT,
    reason TEXT,                -- NULL unless event_type = 'print_failed'
    created_at TEXT DEFAULT (datetime('now'))
  );
`);

// ── State tracking ────────────────────────────────────────────────────────────
let lastPrintState = null;
let currentPrintName = '';
let printStartTime = null;
let lastAMSReport = {};       // { "ams_0_slot_0": { tray_weight: 123, ... }, ... }
let weightAtStart = {};       // snapshot of weights when print began
let mqttClient = null;
let reconnectTimer = null;
let lastFilamentUsedReport = null;  // mc_print_filament_used grams from Bambu at end of print
let lastActiveSlotKey = null;       // most recent active AMS slot key during a print
let lastPrintError = null;          // print_error code from Bambu (non-zero when print fails)

// ── Helper: save printer state to DB (for iOS app to poll) ───────────────────
function savePrinterState(state) {
  const stmt = db.prepare(`
    INSERT INTO printer_state (key, value, updated_at)
    VALUES (?, ?, datetime('now'))
    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')
  `);
  for (const [key, value] of Object.entries(state)) {
    stmt.run(key, JSON.stringify(value));
  }
}

function getPrinterState(key) {
  const row = db.prepare('SELECT value FROM printer_state WHERE key = ?').get(key);
  return row ? JSON.parse(row.value) : null;
}

// ── Helper: record a printer lifecycle event (for iOS push polling) ───────────
function insertPrinterEvent(eventType, printName, reason) {
  try {
    db.prepare(`
      INSERT INTO printer_events (id, event_type, print_name, reason, created_at)
      VALUES (?, ?, ?, ?, datetime('now'))
    `).run(crypto.randomUUID(), eventType, printName || '', reason || null);
  } catch (err) {
    console.warn('Could not insert printer event:', err.message);
  }
}

// ── Helper: get AMS slot → filament mapping ───────────────────────────────────
function getFilamentForSlot(amsIndex, slotIndex) {
  const key = `ams_${amsIndex}_slot_${slotIndex}`;
  const row = db.prepare('SELECT filament_id FROM ams_mappings WHERE slot_key = ?').get(key);
  return row ? row.filament_id : null;
}

// ── Helper: get filament from DB ──────────────────────────────────────────────
function getFilament(id) {
  const row = db.prepare('SELECT data FROM filaments WHERE id = ?').get(id);
  return row ? JSON.parse(row.data) : null;
}

// ── Helper: update filament weight in DB ──────────────────────────────────────
function deductFilamentWeight(filamentId, weightUsedG, printName, durationSeconds) {
  const filament = getFilament(filamentId);
  if (!filament) {
    console.warn(`⚠️  Filament ${filamentId} not found in DB`);
    return null;
  }

  // Create print job record
  const job = {
    id: crypto.randomUUID(),
    filamentId: filamentId,
    printName: printName || 'Auto-logged print',
    weightUsedG: Math.round(weightUsedG * 10) / 10,
    duration: durationSeconds || null,
    date: new Date().toISOString(),
    notes: 'Auto-logged by Bambu Lab MQTT bridge',
    success: true,
    source: 'bambu_auto'
  };

  db.prepare(`
    INSERT INTO print_jobs (id, filament_id, data, created_at)
    VALUES (?, ?, ?, datetime('now'))
  `).run(job.id, filamentId, JSON.stringify(job));

  // Deduct weight from filament
  const newRemaining = Math.max(0, (filament.remainingWeightG || 0) - weightUsedG);
  filament.remainingWeightG = Math.round(newRemaining * 10) / 10;
  filament.lastUpdated = new Date().toISOString();

  // Update stock status
  const pct = filament.totalWeightG > 0 ? filament.remainingWeightG / filament.totalWeightG : 0;
  if (filament.remainingWeightG <= 0) filament.stockStatus = 'Empty';
  else if (filament.remainingWeightG < 200) filament.stockStatus = 'Low';
  else if (pct < 0.5) filament.stockStatus = 'Partial';
  else filament.stockStatus = 'Full';

  // Add to print jobs array on filament
  if (!filament.printJobs) filament.printJobs = [];
  filament.printJobs.push(job);

  db.prepare(`
    UPDATE filaments SET data = ?, updated_at = datetime('now') WHERE id = ?
  `).run(JSON.stringify(filament), filamentId);

  console.log(`✅ Auto-logged: "${printName}" used ${weightUsedG.toFixed(1)}g from ${filament.brand} ${filament.type} ${filament.color?.name}`);
  console.log(`   Remaining: ${filament.remainingWeightG}g (was ${(filament.remainingWeightG + weightUsedG).toFixed(1)}g)`);

  return job;
}

// ── Process incoming MQTT message ─────────────────────────────────────────────
function processPrinterMessage(payload) {
  try {
    const msg = JSON.parse(payload.toString());
    const print = msg.print;
    if (!print) return;

    // ── Update live printer state (for iOS polling) ───────────────────────────
    const liveState = {
      print_status: print.gcode_state || 'IDLE',
      print_name: print.subtask_name || currentPrintName || '',
      progress: print.mc_percent || 0,
      remaining_minutes: print.mc_remaining_time || 0,
      layer_current: print.layer_num || 0,
      layer_total: print.total_layer_num || 0,
      nozzle_temp: print.nozzle_temper || 0,
      bed_temp: print.bed_temper || 0,
      chamber_temp: print.chamber_temper || 0,
      print_speed: print.spd_lvl || 2,
      wifi_signal: print.wifi_signal || '',
      timestamp: new Date().toISOString()
    };

    // ── Track AMS filament data ───────────────────────────────────────────────
    if (print.ams?.ams) {
      const amsUnits = print.ams.ams;
      const amsSlots = {};

      amsUnits.forEach((amsUnit, amsIdx) => {
        if (amsUnit.tray) {
          amsUnit.tray.forEach((tray, slotIdx) => {
            const key = `ams_${amsIdx}_slot_${slotIdx}`;
            amsSlots[key] = {
              ams_index: amsIdx,
              slot_index: slotIdx,
              tray_color: tray.tray_color || '',
              tray_type: tray.tray_type || '',
              tray_sub_brands: tray.tray_sub_brands || '',
              remain: tray.remain !== undefined ? tray.remain : -1,  // % remaining if available
              cols: tray.cols || []
            };
          });
        }
      });

      lastAMSReport = amsSlots;
      liveState.ams_slots = amsSlots;

      // Track which slot is currently active
      // Stringify so the iOS decoder (String?) doesn't get a type-mismatch on Int
      if (print.ams.tray_now !== undefined) {
        liveState.active_ams_slot = String(print.ams.tray_now);
        const slotIdx = parseInt(print.ams.tray_now);
        if (!isNaN(slotIdx) && slotIdx !== 255) {
          lastActiveSlotKey = `ams_0_slot_${slotIdx}`;
        }
      }
    }

    // ── Capture exact filament usage reported by printer (grams) ─────────────
    if (print.mc_print_filament_used !== undefined) {
      lastFilamentUsedReport = print.mc_print_filament_used;
      console.log(`📊 Filament used report from printer: ${lastFilamentUsedReport}g`);
    }

    // ── Capture print error code (non-zero when the printer reports a fault) ─
    if (print.print_error !== undefined && print.print_error !== 0) {
      lastPrintError = print.print_error;
    }

    // ── Track chamber light state ─────────────────────────────────────────────
    if (print.lights_report) {
      const chamberLight = print.lights_report.find(l => l.node === 'chamber_light');
      if (chamberLight) {
        savePrinterState({ chamber_light: chamberLight.mode === 'on' });
      }
    }

    savePrinterState({ live: liveState });

    // Track print name
    if (print.subtask_name) {
      currentPrintName = print.subtask_name;
    }

    // ── Detect state transitions ──────────────────────────────────────────────
    const currentState = print.gcode_state;

    if (currentState && currentState !== lastPrintState) {
      console.log(`🖨️  Printer state: ${lastPrintState || 'UNKNOWN'} → ${currentState}`);

      // Print just started
      if (currentState === 'RUNNING' && lastPrintState !== 'RUNNING') {
        printStartTime = Date.now();
        // Snapshot current AMS slot weights for delta calculation
        weightAtStart = {};
        Object.entries(lastAMSReport).forEach(([key, slot]) => {
          weightAtStart[key] = slot.remain;
        });
        lastFilamentUsedReport = null;
        lastActiveSlotKey = null;
        lastPrintError = null;
        console.log(`▶️  Print started: "${currentPrintName}"`);
        insertPrinterEvent('print_started', currentPrintName, null);
      }

      // Print just finished successfully
      if (currentState === 'FINISH' && lastPrintState === 'RUNNING') {
        insertPrinterEvent('print_completed', currentPrintName, null);
        handlePrintComplete(false);
      }

      // Print failed
      if (currentState === 'FAILED' && lastPrintState === 'RUNNING') {
        const reason = lastPrintError ? `Error code: ${lastPrintError}` : null;
        insertPrinterEvent('print_failed', currentPrintName, reason);
        handlePrintComplete(true);
      }

      lastPrintState = currentState;
    }

  } catch (err) {
    console.error('Error processing MQTT message:', err.message);
  }
}

// ── Handle print completion ───────────────────────────────────────────────────
function handlePrintComplete(failed) {
  const durationMs = printStartTime ? Date.now() - printStartTime : null;
  const durationSeconds = durationMs ? Math.round(durationMs / 1000) : null;

  console.log(`${failed ? '❌' : '✅'} Print ${failed ? 'FAILED' : 'FINISHED'}: "${currentPrintName}"`);

  // Get all AMS mappings
  const mappings = db.prepare('SELECT slot_key, filament_id FROM ams_mappings').all();
  if (mappings.length === 0) {
    console.warn('⚠️  No AMS mappings configured — set them up in the iOS app Settings > Printer');
    return;
  }

  // For each mapped slot, calculate weight used
  // Bambu reports "remain" as a percentage — we use the delta vs start snapshot
  // If no delta available (Bambu doesn't always report %), we use a reasonable estimate
  let totalDeducted = 0;

  mappings.forEach(({ slot_key, filament_id }) => {
    const slotData = lastAMSReport[slot_key];
    if (!slotData) return;

    const filament = getFilament(filament_id);
    if (!filament) return;

    // Calculate weight used
    let weightUsed = 0;

    if (slotData.remain >= 0 && weightAtStart[slot_key] >= 0) {
      // Use percentage delta × total weight
      const remainDelta = weightAtStart[slot_key] - slotData.remain;
      if (remainDelta > 0) {
        weightUsed = (remainDelta / 100) * (filament.totalWeightG || 1000);
      }
    }

    // Minimum threshold — only log if meaningful weight was used (>0.5g)
    if (weightUsed > 0.5) {
      deductFilamentWeight(
        filament_id,
        weightUsed,
        `${currentPrintName}${failed ? ' (failed)' : ''}`,
        durationSeconds
      );
      totalDeducted += weightUsed;
    }
  });

  // Fallback: AMS % delta unavailable (non-NFC spools) — use exact grams from printer
  if (totalDeducted === 0 && lastFilamentUsedReport !== null) {
    const totalGrams = parseFloat(lastFilamentUsedReport);
    if (totalGrams > 0.5) {
      // Prefer the slot that was last active; fall back to first mapped slot
      const targetMapping =
        mappings.find(m => m.slot_key === lastActiveSlotKey) || mappings[0];
      if (targetMapping) {
        deductFilamentWeight(
          targetMapping.filament_id,
          totalGrams,
          `${currentPrintName}${failed ? ' (failed)' : ''}`,
          durationSeconds
        );
        totalDeducted = totalGrams;
        console.log(`ℹ️  AMS % unavailable — used printer report: ${totalGrams}g → ${targetMapping.slot_key}`);
      }
    }
  }

  if (totalDeducted === 0) {
    console.log('ℹ️  No weight deducted (no printer weight data and AMS% unavailable)');
  }

  // Reset tracking
  printStartTime = null;
  weightAtStart = {};
  lastFilamentUsedReport = null;
  lastActiveSlotKey = null;
  lastPrintError = null;
}

// ── Connect to printer MQTT ───────────────────────────────────────────────────
function connect() {
  const topic = `device/${PRINTER_SERIAL}/report`;
  const requestTopic = `device/${PRINTER_SERIAL}/request`;

  console.log(`\n🔌 Connecting to Bambu Lab P2S at ${PRINTER_IP}:8883`);
  console.log(`   Serial: ${PRINTER_SERIAL}`);

  mqttClient = mqtt.connect(`mqtts://${PRINTER_IP}:8883`, {
    username: 'bblp',
    password: PRINTER_ACCESS_CODE,
    clientId: `filament_inventory_${crypto.randomBytes(4).toString('hex')}`,
    rejectUnauthorized: false,   // Bambu uses self-signed cert
    reconnectPeriod: 5000,
    connectTimeout: 15000,
    keepalive: 30
  });

  mqttClient.on('connect', () => {
    console.log('✅ Connected to printer MQTT broker');
    savePrinterState({ connected: true, connected_at: new Date().toISOString() });

    // Subscribe to printer report topic
    mqttClient.subscribe(topic, (err) => {
      if (err) console.error('Subscribe error:', err);
      else console.log(`📡 Subscribed to: ${topic}`);
    });

    // Request full status immediately
    requestFullStatus(requestTopic);

    // Poll for status updates every 5 seconds
    if (reconnectTimer) clearInterval(reconnectTimer);
    reconnectTimer = setInterval(() => requestFullStatus(requestTopic), POLL_INTERVAL_MS);
  });

  mqttClient.on('message', (topic, payload) => {
    processPrinterMessage(payload);
  });

  mqttClient.on('error', (err) => {
    console.error('MQTT error:', err.message);
    savePrinterState({ connected: false, last_error: err.message });
  });

  mqttClient.on('offline', () => {
    console.warn('📡 MQTT offline — will retry');
    savePrinterState({ connected: false });
    if (reconnectTimer) clearInterval(reconnectTimer);
  });

  mqttClient.on('reconnect', () => {
    console.log('🔄 Reconnecting to printer...');
  });
}

// ── Request full printer status ───────────────────────────────────────────────
function requestFullStatus(requestTopic) {
  if (!mqttClient?.connected) return;
  const cmd = {
    pushing: { sequence_id: '0', command: 'pushall' }
  };
  mqttClient.publish(requestTopic, JSON.stringify(cmd));
}

// ── Start ─────────────────────────────────────────────────────────────────────
console.log('🧵 Filament Inventory — Bambu Lab MQTT Bridge v1.0');
connect();

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Shutting down MQTT bridge...');
  if (reconnectTimer) clearInterval(reconnectTimer);
  mqttClient?.end();
  process.exit(0);
});
