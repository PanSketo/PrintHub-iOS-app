# 🖨️ PrintHub

A personal iOS app to manage your 3D printer filament inventory, monitor live printer status, browse and start prints, and watch timelapse recordings — all synced to your Synology NAS. Built with SwiftUI, backed by a Node.js/SQLite server running in Docker.

> Formerly named *Filament Inventory* — renamed to **PrintHub** to reflect the full scope of features.

---

## Features

### Inventory Management
- 📷 **Barcode scanning** — camera-based scan auto-fills brand, SKU, colour, and image from the web
- 🏷️ **Full spool tracking** — brand, SKU, type (PLA/PETG/ABS/TPU/ASA/PA/PC/…), colour, weight, price, notes
- 🎨 **Colour picker** — preset swatches + full iOS colour wheel with hex code display
- 🔍 **Filter & search** — by brand, colour, type, or stock status (In Stock / Low / Empty)
- 🖼️ **Spool images** — auto-fetched from the web and mirrored to your NAS for offline use
- 🏭 **Brand logos** — automatically fetched and cached
- 📦 **Restock detection** — scanning or entering a duplicate SKU/barcode prompts a restock instead of a duplicate
- ➕ **Add spool from Inventory tab** — tap the **+** button in the top-right corner of the Inventory screen; no separate tab needed

### Weight & Cost Tracking
- ⚖️ **Two-option weight update** on every spool:
  - *Enter grams manually* — type the exact remaining weight
  - *Measure spool gap* — measure the gap (cm) from the spool's outer rim to the filament surface; the app estimates remaining weight using standard 200 mm spool geometry
- 💰 **Cost per print job** — automatically calculated from filament price per gram × grams used
- 📈 **Price history** — log and chart price changes per filament over time
- 💸 **Spend analytics** — total spend, cost per gram, cost per print

### Print Logging
- 🖨️ **Log print jobs** — name, duration, grams used, success/fail flag
- 🔢 **Auto-deduction** — remaining weight updated automatically on save
- 📋 **Print history per spool** — full job list with weight and cost per job
- 🧮 **Global print log** — all jobs across all spools in one view

### Dashboard & Analytics
- 📊 **Customisable dashboard** — drag-to-reorder cards; show/hide sections
- 📉 **Statistics & Charts** — filament type breakdown (donut chart), spend by brand, price trends
- 🛒 **Shopping list** — auto-generated from low-stock spools
- 📷 **Live camera feed** — MJPEG stream card (for webcam/printer cam monitoring) with chamber light toggle
- 🎬 **Timelapse viewer** — browse all `.mp4` timelapse recordings stored on the printer's SD card, tap to play full-screen, or save directly to your iPhone's Photos library

### Printer Control (Bambu Lab)
- 🔌 **Live printer status** — connection banner, print progress, layer count, time remaining, temperatures
- ▶️ **Start a print remotely** — browse your printer's internal SD card (`/sdcard`) and USB drive (`/usb`) directly in the app; tap any `.3mf` or `.gcode` file to send a print command via MQTT
- ⏸️ **Pause / Resume / Stop** — full in-app print control
- 🌡️ **Temperature control** — tap nozzle or bed tile to set a target temperature
- 💡 **Chamber light toggle** — turn the printer's chamber LED on/off from the dashboard camera card
- 🗂️ **AMS slot mapping** — map each AMS 2 Pro slot to a spool in your inventory for automatic weight deduction
- 📡 **MQTT bridge** — real-time telemetry from Bambu Lab printers via a lightweight Docker sidecar

### Multi-Printer Support
- 🖨️ **Multiple printer profiles** — each printer has its own name, NAS URL, and API key
- ✅ **Active printer switching** — tap a printer chip at the top of the Printer tab to switch
- 📁 **Per-printer file browser** — the Print Files and timelapse endpoints use the active printer's credentials

### Backup & Sync
- 📤 **Export inventory** — saves a full JSON backup (filaments + print jobs) via the iOS share sheet
- 📥 **Import backup** — restore from any previously exported JSON file
- 🔄 **NAS sync** — all data is live-synced to your Synology NAS over REST API
- ⚡ **Force sync** — manual pull from NAS in Settings

### Siri & Shortcuts
- 🎙️ **App Intents** — Siri Shortcuts integration for quick inventory actions

### Settings & UI
- 🌗 **Appearance themes** — System / Light / Dark mode
- 🔔 **Configurable low-stock threshold** — slider from 50 g to 500 g (default 200 g)
- 🔔 **Push notifications** — alert when any spool drops below the threshold
- 🪟 **Liquid Glass UI** — adaptive glass morphism style (iOS 26 native, graceful fallback on iOS 16–25)
- ⌨️ **Keyboard UX** — scroll to dismiss keyboard; all form buttons respond on first tap
- ✅ **iOS 26 compatible** — all deprecated APIs replaced (`NavigationView` → `NavigationStack`, `.accentColor` → `.tint`, `.cornerRadius` → `.clipShape`, `.onChange` two-parameter form)

---

## App Layout

PrintHub uses a **4-tab** structure:

| Tab | Icon | Contents |
|-----|------|----------|
| Dashboard | `square.grid.2x2.fill` | Stats cards, camera feed, timelapse viewer, low stock, recent prints |
| Inventory | `shippingbox.fill` | Grid/list of spools, filter chips, search; **+** button opens Add Spool sheet |
| Printer | `printer.fill` | **Live Status** · **Print Files** · **Print Log** (segmented picker) |
| Settings | `gearshape.fill` | NAS config, printer profiles, backup/restore, charts, shopping list, appearance |

---

## Project Structure

```
fil-inv/
├── iOS/
│   └── FilamentInventory/
│       ├── FilamentInventoryApp.swift
│       ├── ContentView.swift
│       ├── Models/
│       │   └── FilamentModel.swift           # Filament, PrintJob, PrinterConfig, etc.
│       ├── Services/
│       │   ├── NASService.swift              # REST API client + printer file/timelapse proxy
│       │   ├── InventoryStore.swift          # Central ObservableObject state store
│       │   ├── PrinterManager.swift          # Multi-printer config management
│       │   ├── FilamentLookupService.swift   # Barcode / image / logo lookup
│       │   ├── CloudBackupService.swift      # JSON export & import
│       │   └── NotificationManager.swift    # Push notification scheduling
│       ├── Intents/
│       │   └── FilamentIntents.swift         # Siri Shortcuts / App Intents
│       └── Views/
│           ├── DashboardView.swift           # Customisable home dashboard
│           ├── DashboardCustomizeSheet.swift
│           ├── InventoryListView.swift       # Grid/list with filters + Add sheet
│           ├── AddFilamentView.swift         # Add spool (barcode or manual)
│           ├── FilamentDetailView.swift      # Spool detail + weight update + history
│           ├── LogPrintView.swift            # Log a print job
│           ├── PrintLogView.swift            # Global print job history
│           ├── RestockView.swift             # Restock an existing spool
│           ├── PrintFilesView.swift          # Printer SD card / USB file browser
│           ├── TimelapseCard.swift           # Timelapse viewer + save to Photos
│           ├── ChartsView.swift              # Statistics & charts
│           ├── ShoppingListView.swift        # Auto shopping list
│           ├── PriceHistoryView.swift        # Price trend per filament
│           ├── PrinterView.swift             # Printer hub (status + files + log)
│           ├── CameraFeedCard.swift          # Live MJPEG camera stream + light toggle
│           ├── BarcodeScannerView.swift      # AVFoundation camera scanner
│           ├── SettingsView.swift            # NAS config, printers, backup, theme
│           └── GlassStyle.swift             # Liquid glass / card styling
├── NAS-Backend/
│   ├── server.js                            # Express REST API + SQLite + FTP proxy
│   ├── package.json                         # Dependencies incl. basic-ftp, mqtt
│   ├── docker-compose.yml
│   └── mqtt-bridge/
│       ├── bridge.js                        # Bambu Lab MQTT → NAS bridge
│       └── package.json
├── codemagic.yaml                           # Codemagic CI/CD build
└── .github/workflows/
    └── build-ipa.yml                        # GitHub Actions IPA build
```

---

## Step 1 — Deploy the Backend on Synology NAS

### Prerequisites
- Synology NAS with **Container Manager** (Docker) installed
- Port **3456** forwarded on your router → `192.168.1.200:3456`

### Steps

1. **Copy the backend to your NAS**
   - Open **File Station** → create `/docker/filament-backend`
   - Upload everything from `NAS-Backend/` into that folder

2. **Set your API key and printer credentials**
   - Edit `docker-compose.yml`
   - Replace the placeholder values:
     ```yaml
     environment:
       API_KEY: "your-super-secret-key"       # any strong random string
       PRINTER_IP: "192.168.1.XXX"            # your Bambu printer's local IP
       PRINTER_ACCESS_CODE: "XXXXXXXX"        # 8-char code from printer screen
       PRINTER_SERIAL: "XXXXXXXXXXXXXXXX"     # serial shown on printer screen
     ```
   - Find the **Access Code** on your Bambu printer: *Settings → Network → Access Code*
   - **Save the API key — you'll enter it in the app**

3. **Start the containers** (via SSH)
   ```bash
   cd /volume1/docker/filament-backend
   sudo docker-compose down
   sudo docker-compose up -d --build
   sudo docker-compose logs --tail=30
   ```
   A healthy start looks like:
   ```
   🖨️  PrintHub Backend running on port 3456
   📁 Database: /data/filaments.db
   🔑 API Key configured: YES ✅
   ```

4. **Verify it works**
   ```
   http://192.168.1.200:3456/api/health
   → {"status":"ok","version":"1.0.0",...}
   ```

5. **Remote access (optional)**
   - Router: forward external port `3456` → `192.168.1.200:3456`
   - Test: `http://your-ddns-hostname:3456/api/health`

### Updating the backend
```bash
cd /volume1/docker/filament-backend
sudo git pull origin main
sudo docker-compose down
sudo docker-compose up -d --build
sudo docker-compose logs --tail=30
```

---

## Step 2 — Build the iOS App (No Mac needed)

### Option A: GitHub Actions — FREE ✅ (Recommended)

1. Push this repo to a **private** GitHub repository
2. Go to **Actions** tab → **"Build PrintHub IPA"** → **Run workflow**
3. Wait ~15 minutes ☕
4. Download the `.ipa` from **Artifacts** when the build turns green ✅

### Option B: Codemagic.io (free tier)

1. Sign up at [codemagic.io](https://codemagic.io) with your GitHub account
2. **Add application** → connect your repo
3. Codemagic detects `codemagic.yaml` automatically
4. **Start build** → download `.ipa` when done

---

## Step 3 — Sign and Install with Signulous

1. Open **Signulous** on your iPhone (or their website)
2. Upload the `FilamentInventory.ipa` you downloaded
3. Signulous signs it with your certificate
4. Install on your iPhone — done! 🎉

---

## Step 4 — First Launch Setup

1. Open **PrintHub** on your iPhone
2. The NAS Setup screen appears automatically
3. Enter:
   - **NAS URL:** `http://your-ddns-hostname:3456` *(remote)* or `http://192.168.1.200:3456` *(home Wi-Fi)*
   - **API Key:** the key you set in `docker-compose.yml`
4. Tap **Test Connection** → wait for ✅
5. Tap **Continue** — you're in!

> Add extra printers later in **Settings → Printers → Add Printer**, each with its own NAS URL and API key.

---

## API Endpoints Reference

### Inventory

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/filaments` | List all filaments |
| GET | `/api/filaments/:id` | Get single filament |
| POST | `/api/filaments` | Add filament |
| PUT | `/api/filaments/:id` | Update filament |
| DELETE | `/api/filaments/:id` | Delete filament |
| GET | `/api/printjobs` | List all print jobs |
| GET | `/api/printjobs/filament/:id` | Jobs for one filament |
| POST | `/api/printjobs` | Log a print job |
| GET | `/api/stats` | Inventory statistics |

### AMS & Printer State

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/ams-mappings` | Get AMS slot→filament mappings |
| PUT | `/api/ams-mappings/:slot` | Update a slot mapping |
| DELETE | `/api/ams-mappings/:slot` | Clear a slot mapping |
| GET | `/api/printer-state` | Cached live printer state |
| POST | `/api/printer-state` | Push state update (MQTT bridge) |
| GET | `/api/printer/light` | Get chamber light state |
| POST | `/api/printer/light` | Toggle chamber light `{ "on": true }` |
| POST | `/api/printer/command` | Send printer command (pause/resume/stop/speed) |

### Print Files & Timelapse

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/printer/files?path=/` | Browse printer SD card / USB via FTPS |
| POST | `/api/printer/print` | Start a print `{ "file_path": "/sdcard/foo.3mf" }` |
| GET | `/api/printer/timelapse` | List timelapse `.mp4` files from `/sdcard/timelapse/` |
| GET | `/api/printer/timelapse/stream?path=…&key=…` | Stream a timelapse video over HTTP (FTP proxy) |

### Images

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/images/mirror` | Mirror a remote image URL to NAS local storage |
| GET | `/api/images/:filename` | Serve a mirrored image |

---

## Printer File Browser

The **Print Files** tab inside the Printer screen lets you navigate the full directory tree on your printer's internal storage (`/sdcard`) and any connected USB drive (`/usb`). Supported file types:

| Extension | Icon | Action |
|-----------|------|--------|
| `.3mf` / `.gcode.3mf` | Cube | Tap → confirm → print |
| `.gcode` | Document | Tap → confirm → print |
| Folder | Folder | Tap to navigate in |

The backend connects to your printer via **implicit FTPS** (port 990, username `bblp`, password = Access Code) — the same protocol Bambu Studio uses.

---

## Timelapse Viewer

The **Timelapses** card on the Dashboard lists all `.mp4` timelapse recordings stored at `/sdcard/timelapse/` on the printer. Each recording can be:

- **▶ Played** full-screen via iOS `AVPlayer` — the video is streamed live through the NAS backend proxy (no direct printer connection needed from the phone)
- **⬇ Saved** to your iPhone's Photos library with one tap

> The stream endpoint (`/api/printer/timelapse/stream`) accepts the API key as a `?key=` query parameter so that `AVPlayer` can authenticate without custom HTTP headers.

---

## Troubleshooting

**"Cannot connect to NAS"**
- Confirm the container is running: `sudo docker-compose ps`
- Try the local URL first: `http://192.168.1.200:3456/api/health`
- Check port 3456 is not blocked by Synology Firewall (Control Panel → Security → Firewall)

**"Permission denied" running docker commands on NAS**
- Prefix with `sudo`: `sudo docker-compose down && sudo docker-compose up -d --build`

**Print files tab shows error**
- Verify `PRINTER_IP`, `PRINTER_ACCESS_CODE` are set correctly in `docker-compose.yml`
- The printer must be on and on the same network as the NAS
- FTPS port 990 must be reachable from the NAS to the printer (LAN only — not required to be internet-facing)

**Timelapse list is empty**
- The printer only creates `/sdcard/timelapse/` after the first timelapse is recorded
- Enable timelapse in Bambu Studio / Bambu Handy before starting a print

**"Barcode scan not working"**
- iPhone Settings → PrintHub → Camera → Allow

**"No push notifications"**
- iPhone Settings → PrintHub → Notifications → Allow All

**"Build failed on GitHub Actions"**
- Check the Actions log for the exact error
- Most common: Xcode version mismatch — edit `.github/workflows/build-ipa.yml` and update the Xcode version

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS app | Swift 5.9 + SwiftUI + AVKit + Photos + AVFoundation + App Intents |
| Min iOS | 16.0 (Liquid Glass UI on iOS 26+, fully iOS 26 API-compatible) |
| Backend | Node.js + Express + better-sqlite3 |
| Database | SQLite (Docker volume on NAS) |
| Printer comms | MQTT over TLS (Bambu Lab) + implicit FTPS port 990 (basic-ftp) |
| MQTT bridge | Node.js Docker sidecar |
| Barcode lookup | UPC Item DB + Open Food Facts |
| Image search | Web scraping via FilamentLookupService |
| Brand logos | Clearbit Logo API |
| CI/CD | GitHub Actions + Codemagic |
