<div align="center">

# 🖨️ PrintHub

**Self-hosted filament inventory & Bambu Lab printer control for iPhone**

[![iOS](https://img.shields.io/badge/iOS-16.0%2B-black?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)](https://developer.apple.com/swiftui/)
[![Node.js](https://img.shields.io/badge/Node.js-20-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-MIT-orange)](LICENSE)

*No cloud subscription. No vendor lock-in. Your data stays on your hardware.*

</div>

---

## 📋 Table of Contents

- [✨ Features](#-features)
- [⚙️ Requirements](#️-requirements)
- [🚀 Setup](#-setup)
- [🔄 Updating the Server](#-updating-the-server)
- [🛠️ Troubleshooting](#️-troubleshooting)
- [🧰 Tech Stack](#-tech-stack)
- [📁 Project Structure](#-project-structure)
- [📄 License](#-license)

---

## ✨ Features

### 📦 Filament Inventory
- 📷 **Barcode scanning** — camera scan auto-fills brand, SKU, colour, and fetches a spool image
- 🧵 **Full spool tracking** — brand, type (PLA / PETG / ABS / TPU / ASA / PA / PC / …), colour, weight, price, notes
- 🎨 **Colour picker** — preset swatches + full colour wheel with hex display
- 🔍 **Filter & search** — by brand, colour, type, or stock status (In Stock / Low / Empty)
- 🖼️ **Spool images** — auto-fetched and mirrored to your server for offline use
- 🔁 **Restock detection** — scanning a duplicate SKU prompts a restock instead of adding a duplicate

### ⚖️ Weight & Cost Tracking
- 📏 **Two weight update methods** — enter grams directly, or measure the gap from the spool rim to estimate remaining weight
- 💶 **Cost per print** — automatically calculated from price-per-gram × grams used
- 📈 **Price history** — log and chart price changes per filament over time
- 💰 **Spend analytics** — total spend, cost per gram, cost per print

### 🗂️ Print Logging
- 📝 **Log print jobs** — name, duration, grams used, success/fail, multi-filament support
- ⚡ **Auto weight deduction** — remaining weight updated automatically on save
- 📜 **Print history per spool** — full job list with weight, cost, and duration
- 🌐 **Global print log** — all jobs across all spools in one view, with total weight used, filament length, and total cost

### 🖨️ Printer Control (Bambu Lab)
- 📡 **Live printer status** — progress bar, layer count, elapsed time, finish time, temperatures
- ▶️ **Start prints remotely** — browse your printer's SD card and USB drive, tap any `.3mf` file to start
- ⏸️ **Pause / Resume / Stop** — full in-app print control
- 🌡️ **Temperature control** — tap nozzle or bed tile to set a target temperature
- 💡 **Chamber light toggle** — turn the LED on/off from the dashboard
- 🔀 **AMS slot mapping** — map AMS 2 Pro slots to spools for automatic weight deduction
- 🖥️ **Multi-printer support** — add multiple printer profiles, switch between them instantly

### 📂 File Management
- 💾 **SD card browser** — navigate the full directory tree on your printer's internal storage
- 🗑️ **Multi-select delete** — long press a file to get a context menu; select multiple files and delete in bulk
- 🎬 **Timelapse viewer** — browse, stream full-screen, save to Photos, or delete recordings

### 🏠 Dashboard
- 🃏 **Customisable cards** — drag to reorder, show/hide sections
- 📊 **Stats cards** — total spools (by kg), weight remaining, low stock count, total spend
- 📉 **Charts** — filament type breakdown, spend by brand, price trends
- 🛒 **Shopping list** — auto-generated from low-stock spools
- 📸 **Live camera feed** — MJPEG stream from your printer cam
- 🕐 **Recent prints** — quick glance at the latest activity

### 🧮 Print Cost Calculator
- 💼 **Full business cost model** — filament, electricity, printer depreciation, consumables, fixed overhead
- 📐 **Profit margin** — true margin as % of selling price
- 🔢 **Live breakdown** — see exactly what drives each cost
- 💾 All settings saved across app restarts

### 🔧 General
- 🎙️ **Siri Shortcuts** — App Intents integration for inventory queries
- 📤 **Export / Import** — full JSON backup of filaments and print jobs via share sheet
- 🔔 **Push notifications** — alert when any spool drops below your low-stock threshold
- 🪟 **Liquid Glass UI** — iOS 26 native design, graceful fallback on iOS 16–25
- 🇪🇺 **European number formatting** — dot thousands separator, comma decimal separator

---

## ⚙️ Requirements

### 🖥️ Server
- Any machine that can run Docker (Synology NAS, Raspberry Pi, home server, VPS, etc.)
- Docker + Docker Compose installed
- A Bambu Lab printer on your local network (X1 / P1 / A1 series with LAN mode enabled)

### 📱 iOS
- iPhone running **iOS 16.0** or later
- A way to install unsigned IPAs: [Signulous](https://www.signulous.com) *(recommended)* or [Sideloadly](https://sideloadly.io)

---

## 🚀 Setup

### Step 1 — 🖥️ Server

**1. Clone the repo on your server**
```bash
git clone https://github.com/PanSketo/PrintHub-iOS-app.git
cd PrintHub-iOS-app
```

**2. Create your environment file**
```bash
cp NAS-Backend/.env.example .env
```

Edit `.env` and fill in your values:
```env
API_KEY=your_long_random_secret_key
PRINTER_IP=192.168.1.x
PRINTER_SERIAL=XXXXXXXXXXXXXXXX
PRINTER_ACCESS_CODE=XXXXXXXX
BASE_URL=http://your-server-ip:3456
```

| Variable | Description |
|---|---|
| `API_KEY` | Any strong random string — you'll enter this in the app |
| `PRINTER_IP` | Your Bambu printer's local IP address |
| `PRINTER_SERIAL` | Shown on the printer screen under **Settings → Device** |
| `PRINTER_ACCESS_CODE` | Shown on the printer screen under **Settings → Network** |
| `BASE_URL` | Your server's address (local IP or DDNS hostname) |

**3. Start the containers**
```bash
sudo docker-compose up -d
sudo docker-compose logs --tail=20
```

A successful start shows:
```
🖨️  PrintHub Backend running on port 3456
📁 Database: /data/filaments.db
🔑 API Key configured: YES ✅
```

**4. Verify it's working**

Open `http://YOUR_SERVER_IP:3456/api/health` in a browser — it should return `{"status":"ok",...}`.

**5. Remote access (optional)**

Forward port `3456` on your router to your server's local IP. Use a DDNS hostname for a stable remote URL.

---

### Step 2 — 📦 Build the iOS App

> No Mac required — use GitHub Actions (free).

1. Fork this repo to your GitHub account
2. Go to **Actions → Build PrintHub IPA → Run workflow → Run workflow**
3. Wait ~10 minutes
4. Download `PrintHub.ipa` from the **Artifacts** section when the build goes green ✅

---

### Step 3 — 📲 Install the App

**Signulous** *(recommended — no expiry, no re-signing)*
1. Upload the `.ipa` to [signulous.com](https://www.signulous.com)
2. Install directly to your iPhone

**Sideloadly** *(free, requires re-signing every 7 days with a free Apple ID)*
1. Download [Sideloadly](https://sideloadly.io) on your Mac or PC
2. Connect your iPhone, drag the `.ipa` in, sign with your Apple ID
3. On iPhone: **Settings → General → VPN & Device Management → trust your Apple ID**

---

### Step 4 — 🏁 First Launch

1. Open **PrintHub** on your iPhone
2. Enter your **Server URL** and **API Key** when prompted
3. Tap **Test Connection** → ✅
4. Tap **Continue** — you're in!

> To add more printers later: **Settings → Printers → Add Printer**

---

## 🔄 Updating the Server

```bash
cd /volume2/docker/filament-backend
git pull origin main
sudo docker-compose down && sudo docker-compose up -d
```

---

## 🛠️ Troubleshooting

<details>
<summary><strong>❌ Cannot connect to server</strong></summary>

- Check the container is running: `sudo docker-compose ps`
- Test locally first: `http://YOUR_SERVER_IP:3456/api/health`
- Make sure port `3456` isn't blocked by a firewall

</details>

<details>
<summary><strong>❌ Print files tab shows an error</strong></summary>

- Verify `PRINTER_IP` and `PRINTER_ACCESS_CODE` in your `.env`
- The printer must be powered on and on the same network as the server
- LAN mode must be enabled on the printer

</details>

<details>
<summary><strong>❌ Timelapse list is empty</strong></summary>

- Timelapses only appear after the first timelapse is recorded
- Enable timelapse recording in **Bambu Studio** or **Bambu Handy** before starting a print

</details>

<details>
<summary><strong>❌ GitHub Actions build fails</strong></summary>

- Check the Actions log for the specific error
- Most common cause: Xcode version — the workflow auto-selects the latest available

</details>

<details>
<summary><strong>❌ Barcode scanning not working</strong></summary>

- Go to iPhone **Settings → PrintHub → Camera → Allow**

</details>

<details>
<summary><strong>❌ No push notifications</strong></summary>

- Go to iPhone **Settings → PrintHub → Notifications → Allow All**

</details>

---

## 🧰 Tech Stack

| Layer | Technology |
|---|---|
| 📱 iOS app | Swift + SwiftUI + AVKit + Photos + App Intents |
| 🔢 Minimum iOS | 16.0 |
| 🖥️ Backend | Node.js + Express + SQLite (better-sqlite3) |
| 📡 Printer communication | MQTT over TLS + implicit FTPS port 990 |
| 🔁 MQTT bridge | Node.js Docker sidecar |
| 🔍 Barcode lookup | UPC Item DB + Open Food Facts |
| ⚙️ CI/CD | GitHub Actions |

---

## 📁 Project Structure

```
PrintHub-iOS-app/
├── 📱 iOS/
│   └── FilamentInventory/
│       ├── Models/          # Data models
│       ├── Services/        # NAS API client, inventory store, notifications
│       ├── Intents/         # Siri Shortcuts
│       ├── Extensions/      # Shared utilities (number formatting, etc.)
│       └── Views/           # All SwiftUI views
├── 🖥️ NAS-Backend/
│   ├── server.js            # Express REST API + SQLite + FTP proxy
│   ├── docker-compose.yml   # Docker setup
│   ├── .env.example         # Environment variable template
│   └── mqtt-bridge/
│       └── bridge.js        # Bambu Lab MQTT → server bridge
└── ⚙️ .github/workflows/
    └── build-ipa.yml        # GitHub Actions IPA builder
```

---

## 📄 License

MIT — use it, fork it, adapt it for your own setup.

---

<div align="center">

Built with ❤️ by [Pantelis Tzelesis](https://github.com/PanSketo)

</div>
