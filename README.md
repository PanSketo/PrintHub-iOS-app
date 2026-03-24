# 🧵 Filament Inventory

A personal iOS app to manage your 3D printer filament inventory, synced to your Synology NAS.

## Features
- 📷 Barcode scanning via camera (auto-fills filament info from the web)
- 🏷️ Track brand, SKU, type, colour, weight, and price
- 📊 Dashboard with total spend, weight remaining, and low stock alerts
- 🔍 Filter and search by brand, colour, type, or status
- ⚖️ Weight management: manual entry, auto-deduct on print log, or full/partial/empty status
- 🖨️ Print job logging with filament deduction and history
- 💰 Cost tracking and spend analytics
- 🔔 Push notifications when filament drops below 200g
- 🌐 Synced to Synology NAS via REST API + SQLite

---

## Project Structure

```
FilamentInventory/
├── iOS/                          ← Swift/SwiftUI Xcode project
│   ├── FilamentInventory.xcodeproj/
│   └── FilamentInventory/
│       ├── FilamentInventoryApp.swift
│       ├── ContentView.swift
│       ├── Info.plist
│       ├── Assets.xcassets/
│       ├── Models/
│       │   └── FilamentModel.swift
│       ├── Services/
│       │   ├── NASService.swift
│       │   ├── InventoryStore.swift
│       │   ├── FilamentLookupService.swift
│       │   └── NotificationManager.swift
│       └── Views/
│           ├── DashboardView.swift
│           ├── InventoryListView.swift
│           ├── AddFilamentView.swift
│           ├── BarcodeScannerView.swift
│           ├── FilamentDetailView.swift
│           ├── LogPrintView.swift
│           ├── PrintLogView.swift
│           └── SettingsView.swift
├── NAS-Backend/                  ← Node.js backend for Synology
│   ├── server.js
│   ├── package.json
│   └── docker-compose.yml
├── .github/workflows/
│   └── build-ipa.yml             ← GitHub Actions build (free)
├── codemagic.yaml                ← Codemagic CI/CD build (alternative)
└── .gitignore
```

---

## Step 1 — Deploy Backend on Synology NAS

### Prerequisites
- Synology NAS with **Container Manager** (or Docker) installed
- Port 3456 open on your router (forward to REDACTED-PRINTER-IP0:3456)

### Steps

1. **Copy the backend to your NAS**
   - Open File Station on your Synology
   - Create folder: `/docker/filament-backend`
   - Upload everything from `NAS-Backend/` into that folder

2. **Set your API key**
   - Edit `docker-compose.yml`
   - Change `your-super-secret-api-key-change-this` to a strong random string
   - Example: `FilInv-a8f3kd92-xP9mQ7nL4wR1`
   - **Save this key — you'll enter it in the app later**

3. **Start the container**
   - Open **Container Manager** → **Project** → **Create**
   - Set the path to `/docker/filament-backend`
   - Click **Build** → **Deploy**
   - The API starts automatically on port 3456

4. **Verify it works**
   - Open a browser on any device on your network
   - Visit: `http://REDACTED-PRINTER-IP0:3456/api/health`
   - You should see: `{"status":"ok","version":"1.0.0",...}`

5. **Port forwarding for remote access**
   - In your router admin panel, add a port forward rule:
     - External port: 3456 → Internal IP: REDACTED-PRINTER-IP0 → Internal port: 3456
   - Test from outside: `http://REDACTED-DDNS:3456/api/health`

---

## Step 2 — Build the iOS App (No Mac needed)

### Option A: GitHub Actions (FREE — Recommended)

1. **Create a private GitHub repository**
   - Go to github.com → New Repository → Private
   - Name it `filament-inventory`

2. **Push this entire project to GitHub**
   ```
   # On your Windows PC, install Git from git-scm.com
   # Open PowerShell in the FilamentInventory folder, then:

   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/filament-inventory.git
   git push -u origin main
   ```

3. **Trigger the build**
   - Go to your repo on GitHub → **Actions** tab
   - You'll see **"Build Filament Inventory IPA"** workflow
   - Click **Run workflow** → **Run workflow**
   - Wait ~15 minutes for it to complete ☕

4. **Download your IPA**
   - When the build turns green ✅, click on it
   - Scroll down to **Artifacts**
   - Click **FilamentInventory-v1.0-build1** to download the `.ipa` file

### Option B: Codemagic.io (Alternative, also free tier)

1. Sign up at [codemagic.io](https://codemagic.io) with your GitHub account
2. Click **Add application** → connect your GitHub repo
3. Codemagic will detect the `codemagic.yaml` automatically
4. Click **Start build** → download the `.ipa` when done

---

## Step 3 — Sign and Install with Signulous

1. Open **Signulous** on your iPhone (or their website)
2. Upload the `FilamentInventory.ipa` you downloaded
3. Signulous will sign it with your certificate
4. Install it on your iPhone — done! 🎉

---

## Step 4 — First Launch Setup

1. Open **Filament Inventory** on your iPhone
2. The NAS Setup screen will appear
3. Enter:
   - **NAS URL:** `http://REDACTED-DDNS:3456`  
     *(or `http://REDACTED-PRINTER-IP0:3456` when on home Wi-Fi)*
   - **API Key:** the key you set in `docker-compose.yml`
4. Tap **Test Connection** — wait for the green ✅
5. Tap **Continue** — you're in!

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
| POST | `/api/printjobs` | Log a print job |
| GET | `/api/stats` | Get inventory stats |

---

## Troubleshooting

**"Cannot connect to NAS"**
- Make sure the Docker container is running in Container Manager
- Check port 3456 is not blocked by Synology firewall
- Try the local IP first: `http://REDACTED-PRINTER-IP0:3456/api/health`

**"Barcode scan not working"**
- Go to iPhone Settings → Filament Inventory → Camera → Allow

**"No notifications"**  
- Go to iPhone Settings → Filament Inventory → Notifications → Allow All

**Build failed on GitHub Actions**
- Check the Actions log for errors
- Most common: wrong Xcode version. Edit `.github/workflows/build-ipa.yml` and change `Xcode_15.4` to the latest available

---

## Tech Stack

- **iOS:** Swift 5.9 + SwiftUI + AVFoundation
- **Min iOS:** 16.0
- **Backend:** Node.js + Express + better-sqlite3
- **Database:** SQLite (stored in Docker volume on NAS)
- **Barcode lookup:** UPC Item DB API + Open Food Facts
- **Brand logos:** Clearbit Logo API
