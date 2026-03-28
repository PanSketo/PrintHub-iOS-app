# 🧵 Filament Inventory

A personal iOS app to manage your 3D printer filament inventory, synced to your Synology NAS. Built with SwiftUI, backed by a Node.js/SQLite server running in Docker.

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
- 📷 **Live camera feed** — MJPEG stream card (for webcam/printer cam monitoring)

### Multi-Printer Support
- 🖨️ **Multiple printer profiles** — each printer has its own name, NAS URL, and API key
- ✅ **Active printer switching** — tap a printer in Settings to set it as active
- 🔌 **Printer state monitoring** — live status from Bambu Lab printers via MQTT bridge
- 🗂️ **AMS slot mapping** — map each AMS filament slot to a spool in your inventory

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

---

## Project Structure

```
fil-inv/
├── iOS/
│   └── FilamentInventory/
│       ├── FilamentInventoryApp.swift
│       ├── ContentView.swift
│       ├── Models/
│       │   └── FilamentModel.swift          # Filament, PrintJob, PrinterConfig, etc.
│       ├── Services/
│       │   ├── NASService.swift             # REST API client + image mirroring
│       │   ├── InventoryStore.swift         # Central ObservableObject state store
│       │   ├── PrinterManager.swift         # Multi-printer config management
│       │   ├── FilamentLookupService.swift  # Barcode / image / logo lookup
│       │   ├── CloudBackupService.swift     # JSON export & import
│       │   └── NotificationManager.swift   # Push notification scheduling
│       ├── Intents/
│       │   └── FilamentIntents.swift        # Siri Shortcuts / App Intents
│       └── Views/
│           ├── DashboardView.swift          # Customisable home dashboard
│           ├── DashboardCustomizeSheet.swift
│           ├── InventoryListView.swift      # Grid/list with filters
│           ├── AddFilamentView.swift        # Add spool (barcode or manual)
│           ├── FilamentDetailView.swift     # Spool detail + weight update + history
│           ├── LogPrintView.swift           # Log a print job
│           ├── PrintLogView.swift           # Global print job history
│           ├── RestockView.swift            # Restock an existing spool
│           ├── ChartsView.swift             # Statistics & charts
│           ├── ShoppingListView.swift       # Auto shopping list
│           ├── PriceHistoryView.swift       # Price trend per filament
│           ├── PrinterView.swift            # Printer status + AMS mapping
│           ├── CameraFeedCard.swift         # Live MJPEG camera stream
│           ├── BarcodeScannerView.swift     # AVFoundation camera scanner
│           ├── SettingsView.swift           # NAS config, printers, backup, theme
│           └── GlassStyle.swift            # Liquid glass / card styling
├── NAS-Backend/
│   ├── server.js                           # Express REST API + SQLite
│   ├── package.json
│   ├── docker-compose.yml
│   └── mqtt-bridge/
│       ├── bridge.js                       # Bambu Lab MQTT → NAS bridge
│       └── package.json
├── codemagic.yaml                          # Codemagic CI/CD build
└── .github/workflows/
    └── build-ipa.yml                       # GitHub Actions IPA build (free)
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

2. **Set your API key**
   - Edit `docker-compose.yml`
   - Replace `your-super-secret-api-key-change-this` with a strong random string
   - Example: `FilInv-a8f3kd92-xP9mQ7nL4wR1`
   - **Save this key — you'll enter it in the app**

3. **Start the container** (via SSH)
   ```bash
   cd /volume2/docker/filament-backend
   sudo docker compose up -d
   sudo docker compose logs --tail=30
   ```
   Or via **Container Manager** → **Project** → **Create** → set path → **Deploy**

4. **Verify it works**
   ```
   http://192.168.1.200:3456/api/health
   → {"status":"ok","version":"1.0.0",...}
   ```

5. **Remote access (optional)**
   - Router: forward external port `3456` → `192.168.1.200:3456`
   - Test: `http://pansketo.arcdns.tech:3456/api/health`

### Updating the backend
```bash
cd /volume2/docker/filament-backend
git pull origin main
sudo docker compose down && sudo docker compose up -d
sudo docker compose logs --tail=30
```

---

## Step 2 — Build the iOS App (No Mac needed)

### Option A: GitHub Actions — FREE ✅ (Recommended)

1. Push this repo to a **private** GitHub repository
2. Go to **Actions** tab → **"Build Filament Inventory IPA"** → **Run workflow**
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

1. Open **Filament Inventory** on your iPhone
2. The NAS Setup screen will appear automatically
3. Enter:
   - **NAS URL:** `http://pansketo.arcdns.tech:3456` *(remote)* or `http://192.168.1.200:3456` *(home Wi-Fi)*
   - **API Key:** the key you set in `docker-compose.yml`
4. Tap **Test Connection** → wait for ✅
5. Tap **Continue** — you're in!

> You can add additional printers later in **Settings → Printers → Add Printer**, each with its own NAS URL and API key.

---

## API Endpoints Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/filaments` | Get all filaments |
| GET | `/api/filaments/:id` | Get single filament |
| POST | `/api/filaments` | Add new filament |
| PUT | `/api/filaments/:id` | Update filament |
| DELETE | `/api/filaments/:id` | Delete filament |
| GET | `/api/printjobs` | Get all print jobs |
| GET | `/api/printjobs/filament/:id` | Get jobs for one filament |
| POST | `/api/printjobs` | Log a print job |
| GET | `/api/stats` | Inventory stats |
| GET | `/api/ams-mappings` | Get AMS slot mappings |
| PUT | `/api/ams-mappings/:slot` | Update AMS slot mapping |
| GET | `/api/printer-state` | Get cached printer state |
| POST | `/api/printer-state` | Update printer state (MQTT bridge) |
| POST | `/api/images/mirror` | Mirror a remote image to NAS storage |

---

## Troubleshooting

**"Cannot connect to NAS"**
- Confirm the container is running: `sudo docker compose ps`
- Try the local URL first: `http://192.168.1.200:3456/api/health`
- Check port 3456 is not blocked by Synology Firewall (Control Panel → Security → Firewall)

**"Permission denied" running docker commands on NAS**
- Prefix with `sudo`: `sudo docker compose down && sudo docker compose up -d`

**"Barcode scan not working"**
- iPhone Settings → Filament Inventory → Camera → Allow

**"No push notifications"**
- iPhone Settings → Filament Inventory → Notifications → Allow All

**"Build failed on GitHub Actions"**
- Check the Actions log for the exact error
- Most common: Xcode version mismatch — edit `.github/workflows/build-ipa.yml` and update the Xcode version to the latest available on the runner

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS app | Swift 5.9 + SwiftUI + AVFoundation + App Intents |
| Min iOS | 16.0 (Liquid Glass UI on iOS 26+) |
| Backend | Node.js + Express + better-sqlite3 |
| Database | SQLite (Docker volume on NAS) |
| MQTT bridge | Node.js (Bambu Lab printer telemetry) |
| Barcode lookup | UPC Item DB + Open Food Facts |
| Image search | Web scraping via FilamentLookupService |
| Brand logos | Clearbit Logo API |
| CI/CD | GitHub Actions + Codemagic |
