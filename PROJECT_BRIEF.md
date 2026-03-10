# lot-builder — Project Brief

> Commit to repo root as `PROJECT_BRIEF.md`.
> Reference at the start of every Claude Code session.

---

## Purpose

Eliminate the manual time cost of building auctions. Today: photos → FTP → point-and-click
in a web admin. Goal: photos → JSON → review on PC → one-click upload to any auction platform.

---

## Core Design Principle — Platform Agnostic Until Upload

Everything in this tool is completely independent of any auction platform.
The Flutter app, JSON pipeline, PC viewer, and AI analysis have no knowledge
of AuctionWorx, or any other platform. Only the final upload step is
platform-specific — and that step is a swappable adapter module.

```
PLATFORM-AGNOSTIC (permanent, never changes)
─────────────────────────────────────────────
Flutter Phone App      →  captures lots as photos + JSON
JSON Pipeline          →  source of truth at every stage
PC Viewer (review)     →  reorder, edit, manage lots
OpenAI Analysis        →  generates titles + descriptions
        │
        │  clean adapter interface
        ▼
PLATFORM-SPECIFIC (swappable adapter)
──────────────────────────────────────
/upload/auctionworx.js    ←  current
/upload/platform.js       ←  future custom platform
/upload/[anything].js     ←  any future platform
```

Swapping platforms = writing one new adapter module. Nothing else changes.

---

## Architecture — No Backend Required

Everything runs locally until the final upload step.
No server to host, no API keys exposed on the internet.

```
┌─────────────────────┐
│   Flutter Phone App  │  ← Offline. Camera + filesystem only.
│   (Android)          │    No internet required during capture.
└────────┬────────────┘
         │ USB transfer (wireless over LAN post-MVP)
         ▼
┌─────────────────────┐
│  SvelteKit PC Viewer │  ← Runs locally (npm run dev → localhost:5173)
│  (localhost)         │    Reads JSON + images from local filesystem
└────────┬────────────┘
         │
    ┌────┴────────────────────┐
    ▼                         ▼
┌──────────┐        ┌──────────────────────────┐
│  OpenAI  │        │  Upload Adapter           │
│  Vision  │        │  (platform-specific)      │
│  (gpt-4o)│        │  auctionworx.js / etc.    │
└──────────┘        └──────────────────────────┘
```

---

## Data Architecture — Two-Level Hierarchy

The phone captures **sessions**. Sessions live inside **auctions**.
The PC viewer assembles the final auction from one or more sessions.

### Folder Structure on Device

```
/Documents/lot-builder/
  spring-sale_20260309/          ← auction folder (name-first for USB readability)
    auction.json                  ← auction metadata only
    20260309_142500_morning/      ← session folder (timestamp-first for sort order)
      session.json                ← source of truth for this session
      device01_20260309_142501_234.jpg
      device01_20260309_142502_891.jpg
      device02_20260309_142501_445.jpg   ← second device, no filename collision
    20260309_154000_afternoon/
      session.json
      device01_20260309_154012_007.jpg
```

### auction.json (minimal — metadata only)

```json
{
  "name": "Spring Sale",
  "created_at": "2026-03-09T14:25:00Z"
}
```

### session.json (source of truth for one capture session)

```json
{
  "version": "2.0",
  "session_id": "sess_20260309_142500",
  "captured_at": "2026-03-09T14:25:00Z",
  "name": "Morning Session",
  "device": "device01",
  "lots": [
    {
      "images": ["device01_20260309_142501_234.jpg", "device01_20260309_142502_891.jpg"],
      "notes": ""
    },
    {
      "images": ["device01_20260309_142615_123.jpg"],
      "notes": "chipped on base"
    }
  ]
}
```

### Key Design Decisions
- **No lot IDs or sequence numbers** — array index is the sequence; derived fields
  reduce complexity when deleting, splitting, and inserting lots.
- **Image filenames** — `deviceId_YYYYMMDD_HHMMSS_mmm.jpg`. Timestamp with milliseconds
  guarantees global uniqueness even across simultaneous captures on multiple devices.
  Enables safe folder flattening at import time with zero collision risk.
- **Session folders sort chronologically** — timestamp-first naming ensures correct
  order even after deletions and additions.
- **JSON written after every change** — app crash loses nothing.
- **Platform fields absent from phone JSON** — PC viewer adds `ai_title`,
  `ai_description`, `platform_lot_id`, etc. at review/analysis time.

### PC-Side Lot Status Pipeline
```
captured → analyzed → reviewed → uploaded
```

---

## Component 1 — Flutter Phone App

### Platform
- Android (primary). Flutter = free iOS build later with zero code changes.
- Android Studio already installed. USB testing ready.

### Role — Session Recorder (not auction builder)
The phone captures **sessions**. It has no knowledge of the final auction structure,
lot numbering, titles, or descriptions. That assembly happens on the PC.

### Core Workflow
1. Open app → **Auctions** list → **New Auction** (names the folder)
2. Open auction → **Sessions** list → **New Session** (names the session)
3. Camera opens → take photos per lot → tap **Next Lot** to advance
4. **Lot Preview** screen — review thumbnails, split lots, delete photos, add notes
5. USB-transfer the auction folder to PC

### What the App Intentionally Does NOT Do
- No internet required — fully offline
- No API calls of any kind
- No AI titles or descriptions — PC viewer's job
- No platform knowledge whatsoever

### Flutter Dependencies
```yaml
path_provider: ^2.1.0          # device filesystem paths
camera: ^0.11.0                # embedded viewfinder
image_picker: ^1.1.0           # native camera mode (optional, higher quality)
permission_handler: ^11.0.0    # storage permission (Android)
sensors_plus: ^4.0.0           # accelerometer for capture orientation
```

### Camera Modes (user-configurable in Settings)
- **Embedded viewfinder** (default) — faster workflow, one tap per photo
- **Native camera** — opens Google Camera, full HDR+ processing, ~3× larger files,
  requires one confirmation tap per photo. Configured via `useNativeCamera` toggle.

### Image Quality Note
- Resolution preset: `max` (full sensor, typically 3:4 portrait on Pixel 7 Pro = ~12 MP)
- Lower presets yield 16:9 crops (less useful for product photos)
- Images should be resized before sending to OpenAI Vision on the PC side
  (full-sensor files are unnecessarily large for AI analysis)

### Capture Orientation
The phone UI is locked to portrait, but photos are saved with correct EXIF orientation
regardless of how the phone is physically held. An accelerometer listener tracks the
physical orientation at capture time, applies `lockCaptureOrientation()` for the
snapshot only, then immediately releases it so the preview is unaffected.

### Screens
| Screen | Purpose |
|---|---|
| `HomeScreen` | Auction folder list + new auction. Forces device ID setup on first launch. |
| `AuctionScreen` | Session list within an auction + new session. |
| `CaptureScreen` | Full-screen camera, shutter, Next Lot, photo strip, lot number animation. |
| `LotPreviewScreen` | Thumbnail grid per lot, split lots, delete photos, notes, insert lots. |
| `SettingsScreen` | Image quality, thumbnail size, quick-delete toggle, device ID, camera mode. |
| `DeviceSetupScreen` | Non-dismissible first-launch screen to set device ID. |

### Device ID
Each device must have a unique ID (e.g. `device01`, `device02`). The ID is prefixed to
every photo filename. Multiple devices can contribute to the same auction session folder
without filename collisions. Set on first launch; changeable in Settings.

### Post-MVP Additions
- Wireless transfer over local WiFi (same network as PC)

---

## Component 2 — SvelteKit PC Viewer

### How It Runs
```bash
cd lot-builder/pc-viewer
npm run dev
# Open browser to localhost:5173
```
User selects their auction folder via a folder picker.
Viewer reads all `session.json` files from sub-folders, merges the lots into a single
working auction view, and renders images from disk.

### Import Step (at folder open)
1. Walk auction folder → find all `session.json` files
2. Merge lots from all sessions into a flat, ordered list
3. Image paths = `sessionFolder/filename` (no flattening needed — sessions stay separate)
4. Build working `auction.json` in memory (or save to disk for persistence)

---

### Stage 1 — Review & Edit

The most important stage. Visually verify every lot before analysis.

- **Lot grid** — each lot shown as a card with thumbnail strip
- **Reorder lots** — drag cards to change sequence → updates `sequence` in JSON
- **Reorder images** — drag within a lot card → updates `images` array order
- **Delete image** — click × on any thumbnail
- **Move image** — drag from one lot card to another
- **Split lot** — one lot becomes two (images divided at a split point)
- **Merge lots** — combine two adjacent lots into one
- **Notes** — freetext note field per lot
- Every change writes `auction.json` to disk immediately — no save button needed

---

### Stage 2 — Analyze

- **Analyze All** — processes every lot with status `captured` or `reviewed`
- **Analyze One** — per-lot button for re-analysis or fixes
- Sends all images for a lot to OpenAI Vision (gpt-4o)
- System prompt instructs model to return only JSON:
  ```json
  { "title": "...", "description": "..." }
  ```
- Results displayed inline — fully editable before accepting
- Accepted results set `ai_title`, `ai_description` + status → `analyzed`
- Manual override: edit title/description directly, sets `title`/`description` fields
  (these take precedence over `ai_title`/`ai_description` at upload time)
- OpenAI API key in `config.json` (never committed)

---

### Stage 3 — Upload

This is the only stage that knows about any auction platform.

#### The Adapter Interface

Every upload adapter implements this single function:

```javascript
// /src/lib/upload/adapter-interface.js
/**
 * Upload a complete auction to a platform.
 * @param {Object} auctionJson  — merged working auction object (built from session.json files)
 * @param {string} folderPath   — absolute path to the auction folder (for reading images)
 * @param {Object} config       — platform credentials from config.json
 * @param {Function} onProgress — callback(lotIndex, step, status) for UI updates
 * @returns {Object}            — updated auctionJson with platform IDs populated
 */
export async function uploadAuction(auctionJson, folderPath, config, onProgress) {}
```

#### Current Adapter — AuctionWorx (`/src/lib/upload/auctionworx.js`)

AuctionWorx upload sequence per lot:
1. Upload each image to AW media pool → receive UUID
2. Write `platform_uuid` per image to JSON
3. Create lot in AW with title, description, image UUIDs
4. Write `platform_lot_id` to JSON
5. Set lot status → `uploaded`

Safe to re-run: adapter checks `platform_uuid` and `platform_lot_id` before
creating anything. Already-uploaded items are skipped silently.

**AW API questions to confirm before building:**
- Does lot creation accept external image URLs, or must images be pre-uploaded for UUIDs?
- Rate limits on media upload endpoint?
- Auth method: API key header, OAuth, or session token?
- Endpoint for creating auction vs. adding lots to existing auction?

#### Future Adapter — Custom Platform (`/src/lib/upload/platform.js`)
Same interface. Targets the custom auction platform API instead of AW.
Write this adapter when the custom platform is built. Nothing else in this
repo needs to change.

#### Upload UI
- Active adapter selected via `config.json` → `"upload_adapter": "auctionworx"`
- Progress shown per lot, per step — clear success/failure indicators
- Failed lots can be retried individually
- On complete: summary of all lots created + link to platform admin

---

### config.json (local only — always gitignored)

```json
{
  "openai_api_key": "sk-...",
  "upload_adapter": "auctionworx",
  "adapters": {
    "auctionworx": {
      "api_key": "...",
      "base_url": "https://your-instance.auctionworx.com/api"
    },
    "platform": {
      "api_key": "...",
      "base_url": "https://your-custom-platform.com/api"
    }
  }
}
```

---

## Build Order

Each stage is independently useful — stop at any point and it already saves time.

1. **Flutter app** — immediately useful at next auction
2. **PC viewer Stage 1** — review/edit lot grid
3. **PC viewer Stage 2** — OpenAI analysis
4. **PC viewer Stage 3** — AuctionWorx upload adapter
5. **Future** — custom platform upload adapter (when platform is built)

---

## Tech Stack

| Component | Tech | Notes |
|---|---|---|
| Phone app | Flutter (Dart) | Android primary, iOS free later |
| PC viewer | SvelteKit | Local dev server, filesystem access |
| AI analysis | OpenAI Vision (gpt-4o) | Called from PC browser |
| Upload — current | AuctionWorx Admin API | Adapter pattern |
| Upload — future | Custom platform API | Same adapter interface |
| Config | `config.json` | Local only, gitignored |
| Source of truth | `auction.json` | Per auction folder |

---

## Repo Structure

```
/lot-builder
│
├── /flutter-app                    # Flutter phone app (Android)
│   ├── /lib
│   │   ├── main.dart
│   │   ├── /screens
│   │   │   ├── home_screen.dart         # auction list + new auction
│   │   │   ├── auction_screen.dart      # session list within auction
│   │   │   ├── capture_screen.dart      # camera viewfinder + lot controls
│   │   │   ├── lot_preview_screen.dart  # review/split/delete per lot
│   │   │   ├── settings_screen.dart     # quality, device ID, camera mode
│   │   │   └── device_setup_screen.dart # first-launch device ID setup
│   │   └── /services
│   │       ├── session_service.dart  # auction/session/lot/image CRUD + JSON
│   │       ├── settings_service.dart # app settings persistence
│   │       └── camera_service.dart   # camera init, capture helpers
│   └── pubspec.yaml
│
├── /pc-viewer                      # SvelteKit local viewer
│   ├── /src
│   │   ├── /routes
│   │   │   ├── /                   # folder picker, auction selector
│   │   │   ├── /review             # lot grid, drag reorder
│   │   │   ├── /analyze            # OpenAI analysis stage
│   │   │   └── /upload             # upload stage + progress UI
│   │   └── /lib
│   │       ├── /auction            # JSON read/write, lot manipulation
│   │       ├── /openai             # Vision API wrapper
│   │       └── /upload
│   │           ├── adapter-interface.js   # the contract
│   │           ├── auctionworx.js         # current adapter
│   │           └── platform.js            # future adapter (stub)
│   ├── package.json
│   └── config.json.example         # copy to config.json, fill in keys
│
└── PROJECT_BRIEF.md

```

---

## Future Integration with auction-platform

When the custom auction platform is built, this tool slots in cleanly:

- Flutter app: **unchanged** — captures to JSON regardless of platform
- PC viewer Stages 1 & 2: **unchanged** — platform-agnostic
- PC viewer Stage 3: **add `platform.js` adapter** — implement the same
  `uploadAuction()` interface targeting the custom platform API
- Switch `"upload_adapter": "platform"` in `config.json`
- Done — full migration with no architectural changes

This repo can be moved into the `auction-platform` monorepo at that point,
living at `/auction-platform/lot-builder/`.
