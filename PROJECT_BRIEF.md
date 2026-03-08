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

## The JSON — Source of Truth

Every action on phone or PC updates `auction.json`.
This file defines the auction completely at every stage of the pipeline.

```json
{
  "version": "1.0",
  "created_at": "2026-03-07T10:00:00Z",
  "auction": {
    "title": "",
    "description": "",
    "platform_id": null
  },
  "lots": [
    {
      "id": "lot_001",
      "sequence": 1,
      "images": [
        { "filename": "img_001.jpg", "platform_uuid": null },
        { "filename": "img_002.jpg", "platform_uuid": null }
      ],
      "ai_title": null,
      "ai_description": null,
      "title": null,
      "description": null,
      "notes": "",
      "platform_lot_id": null,
      "status": "captured"
    }
  ]
}
```

### Key JSON Design Decisions
- `platform_id`, `platform_uuid`, `platform_lot_id` — generic names, not AW-specific.
  The active adapter populates these with whatever IDs the target platform returns.
- Partial upload failures are always resumable — adapter checks existing IDs before
  creating anything, never duplicates.
- JSON is written to disk after every change — app crash or browser close loses nothing.

### Lot Status Pipeline
```
captured → analyzed → reviewed → uploaded
```

---

## Component 1 — Flutter Phone App

### Platform
- Android (primary). Flutter = free iOS build later with zero code changes.
- Android Studio already installed. USB testing ready.

### Core Workflow
1. Open app → **New Auction** → creates `auction.json` + timestamped folder
2. Point camera at lot → take photos (multiple per lot)
3. **Next Lot** → closes current lot, starts new one
4. Repeat until all lots captured
5. USB transfer folder to PC

### What the App Intentionally Does NOT Do
- No internet required — fully offline
- No API calls of any kind
- No titles, descriptions, or lot numbers — PC viewer's job
- No image processing — raw photos only
- No platform knowledge whatsoever

### Scaffold Command
Run from inside `lot-builder/` once Flutter is in PATH:
```bash
flutter create --project-name lot_builder flutter-app
```
Note: Dart package names use underscores (`lot_builder`), directory name stays `flutter-app`.

### Flutter Implementation Details
- File storage: `path_provider` — saves to device Documents folder
- Camera: `image_picker` package (simpler than `camera` for this use case)
- JSON: `dart:convert` — straightforward encode/decode
- Folder structure on device:
  ```
  /Documents/lot-builder/
    /auction_20260307_142500/    ← timestamp = unique, supports multiple auctions
      auction.json
      img_001.jpg
      img_002.jpg
      img_003.jpg
      ...
  ```

### UI — Intentionally Minimal
- Home screen: list of existing auction folders + "New Auction" button
- Capture screen: full-screen camera viewfinder, shutter button, "Next Lot" button,
  current lot number + photo count display
- No nav, no settings, no complexity — this is a capture tool

### Post-MVP Additions
- Wireless transfer over local WiFi (same network as PC)
- Quick notes field per lot before tapping Next Lot
- Swipe left to delete last photo
- Thumbnail review strip showing photos taken for current lot

---

## Component 2 — SvelteKit PC Viewer

### How It Runs
```bash
cd lot-builder/pc-viewer
npm run dev
# Open browser to localhost:5173
```
User selects their auction folder via a folder picker.
Viewer reads `auction.json` and renders all lot images from disk.

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
 * @param {Object} auctionJson  — the full auction.json object
 * @param {string} folderPath   — absolute path to the auction folder (for reading images)
 * @param {Object} config       — platform credentials from config.json
 * @param {Function} onProgress — callback(lotId, step, status) for UI updates
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
├── /flutter-app                    # Flutter phone app
│   ├── /lib
│   │   ├── main.dart
│   │   ├── /screens
│   │   │   ├── home_screen.dart    # auction folder list + new auction
│   │   │   └── capture_screen.dart # camera + next lot
│   │   └── /services
│   │       ├── auction_service.dart  # JSON read/write, folder management
│   │       └── camera_service.dart   # image capture helpers
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
