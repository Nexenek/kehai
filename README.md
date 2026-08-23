# Kehai — 気配

> *kehai (気配): the sense that someone is present — before you see or hear them.*
>
> **czuję, że tam jesteś (´-ω-`) ♡**

A self-hosted little world for two. Kehai is a private couples app — built for long-distance, lovely for any couple — that runs entirely on your own server and makes two people feel close all day: not through more messages, but through ambient signs of each other. What they're listening to. Whether they're at their computer or asleep. Their mood as a kaomoji. A doodle that appears on your screen because they were thinking of you.

Y2K pastel-pixel aesthetic — chunky retro windows, pixel fonts, soft pinks and lavenders, kaomoji everywhere.

## What works today

- **Pairing**: two accounts, one invite code, your own server — nobody else's cloud
- **Live mood statuses** with kaomoji, synced in realtime between all devices
- **Presence**: see whether your person is on their phone, at their computer, or both; "at their computer", "away", now-playing from Linux media players (MPRIS), battery + charging state
- **Doodles**: draw something small and it shows up on their home screen
- **Countdowns** to reunions & a "together N days" counter
- **Shared sticky notes** in pastel colors

## Planned

Location sharing with honest privacy toggles · Android always-on status notification + home widget · desktop floating partner window · Windows/Android now-playing · shared calendar (CalDAV) · photo "instants" · a shared pet to take care of together · always-on video portal for an old tablet · smart-home hooks (webhooks/MQTT) · watch-together via Jellyfin SyncPlay

## Stack

- **Server**: single Go binary built on [PocketBase](https://pocketbase.io) (auth, SQLite, realtime, file storage) — ~50 MB RAM
- **Push**: self-hosted [ntfy](https://ntfy.sh) (UnifiedPush) — no Google required
- **Clients**: one Flutter codebase for Android, Windows, Linux (macOS/iOS someday)
- **Networking**: designed for [Tailscale](https://tailscale.com) — zero exposed ports

## Quickstart

```bash
# server (any box with Docker — a Pi is plenty)
cd deploy && docker compose up -d       # API on :8090, ntfy on :8091

# desktop client
cd app && flutter run -d linux          # or -d windows on Windows
```

Open the app, point it at your server address, register, create your couple, send the invite code to your person ♡

Windows note: build from a Windows-side checkout (not a WSL share) — Flutter toolchains fight over shared state. Android: `flutter build apk`.

## Self-hosting notes

Everything private-by-default: couple-scoped API rules, locked-down ntfy, no telemetry, no third-party APIs required (Spotify etc. are optional enrichment only). See `deploy/README.md` for setup, backups, and networking guidance.
