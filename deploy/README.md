# Deploying the couples-app stack

A small Docker Compose stack meant to run on a home server (a Pi 4/5, an
old laptop, a NAS — anything with a couple hundred MB of spare RAM), with
Tailscale as the default way clients reach it.

## Quickstart

```sh
cd deploy
docker compose up -d server
```

This builds and starts the `server` container (our Go/PocketBase binary)
on port `8090`, with its data (SQLite database, uploaded files) persisted
in `./data/pb`.

On first boot, the server logs a one-time admin-setup link, e.g.:

```
(!) Launch the URL below in the browser if it hasn't been open already to create your first superuser account:
http://<host>:8090/_/#/pbinstall/<token>
```

Open that URL (over your tailnet address, see below) to create the admin
account for the built-in PocketBase dashboard at `/_/`. This admin account
is for server administration only — it is separate from the couple
accounts the app itself creates via `POST /api/couple/create` /
`POST /api/couple/join`. Create your first *couple* account the normal
way, through the app itself (or with `curl` against
`/api/collections/users/records` if the app isn't built yet).

To also bring up push notifications:

```sh
docker compose up -d ntfy
```

then follow the setup comment block at the top of the `ntfy` service in
`docker-compose.yml` (create an account, lock a topic down to just the
couple). `ntfy` ships locked down by default (`auth-default-access:
deny-all` — nobody can read or publish anything without an explicit
account), so this step isn't optional.

The `baikal`, `coturn`, and `caddy` services are commented out in
`docker-compose.yml` — they belong to later phases (shared calendar,
WebRTC portal relay, and public HTTPS respectively) and aren't needed yet.

## Networking: Tailscale by default

This stack is designed to have **zero exposed ports** to the public
internet. Install [Tailscale](https://tailscale.com) on the server and on
every client device (phone, desktop, tablet); the app then talks to the
server over its tailnet address, e.g. `http://my-server:8090` or
`https://my-server.<your-tailnet>.ts.net` if you've issued a Tailscale
TLS cert with `tailscale cert`. The free Tailscale plan (6 users / 100
devices) is plenty for a couple.

Only reach for the commented-out `caddy` service (reverse proxy +
Let's Encrypt) if some device genuinely can't run Tailscale and a
service has to be reachable from the public internet. If you do, put a
strong auth story and rate limiting in front of anything you expose, and
consider `fail2ban`.

## Backups

Everything persistent lives under `./data/` (one tree — `data/pb`,
`data/ntfy`, and so on as more services come online), so backing up the
stack means backing up that one directory.

### Built in: the `backup` sidecar

`docker-compose.yml` ships a `backup` service — a plain `alpine` container
that runs `deploy/backup.sh` on a cron schedule (`crond`, 03:00 nightly,
nothing to install beyond the `sqlite` apk package it grabs on first
start). Bring it up alongside the server:

```sh
docker compose up -d server backup
```

It writes `./backups/kehai-YYYYMMDD.tar.gz` and keeps the most recent 14.
The one thing that makes a naive `tar ./data` wrong — `data/pb/data.db` and
`data/pb/auxiliary.db` are live SQLite databases in WAL mode while the
server is running, so a raw file copy can grab a torn page or miss
WAL frames that haven't been checkpointed yet — is handled with SQLite's
own online backup API: `sqlite3 "$db" ".backup '...'"` takes a consistent
snapshot while the server keeps writing, no downtime, no stop-the-world.
(The alternative would be PocketBase's own `POST /api/backups` — it does
the same `.backup` trick internally, but needs a superuser auth token
threaded into the sidecar, which is more moving parts for the same
result. `sqlite3 .backup` gets there directly.) Everything else under
`data/pb/` — `storage/` (uploaded files), `.notify/` — isn't a database,
so it's copied as-is.

Verify a specific archive is actually sound before you need it:

```sh
tar -xzf backups/kehai-20260823.tar.gz -C /tmp/verify
sqlite3 /tmp/verify/data.db "PRAGMA integrity_check;"        # expect: ok
sqlite3 /tmp/verify/auxiliary.db "PRAGMA integrity_check;"   # expect: ok
```

Restoring: stop the server, replace `./data/pb/` with the extracted
archive's contents (drop any stray `-wal`/`-shm` files first — the backup
already checkpointed, so the plain `.db` files are the whole story), start
the server back up.

```sh
docker compose stop server
rm -rf data/pb && mkdir -p data/pb
tar -xzf backups/kehai-20260823.tar.gz -C data/pb
docker compose start server
```

This tier is "good enough for a home server with a spare drive" — it's
one archive on the same box's disk, which protects against a bad
migration or a fat-fingered delete, not against the disk itself dying.
For the real 3-2-1 story (kb/selfhosting.md's Backups section: live copy +
local backup + **encrypted offsite** copy), upgrade to borgmatic below.

### Upgrade path: borgmatic (encrypted, offsite, real 3-2-1)

[borgmatic](https://torsion.org/borgmatic/) wraps BorgBackup with
scheduling, retention, and encryption config in one YAML file. It runs
fine as its own container next to this stack, pointed at the same
`./data/`; no changes to the `backup` service above are needed — borgmatic
replaces it outright when you're ready for offsite.

`deploy/borgmatic/config.yaml` (create this file; not shipped by default
since it needs a passphrase and a real remote target):

```yaml
source_directories:
  - /data

repositories:
  - path: ssh://user@your-second-machine/./kehai-backups
    label: offsite

# generate one: openssl rand -base64 48
encryption_passphrase: "put a real generated passphrase here, not this text"

keep_daily: 14
keep_weekly: 8
keep_monthly: 12

before_backup:
  - sqlite3 /data/pb/data.db ".backup '/tmp/data.db.borg'"
  - sqlite3 /data/pb/auxiliary.db ".backup '/tmp/auxiliary.db.borg'"
```

(Same reasoning as the sidecar above — hot-copy the SQLite files instead
of trusting borg to catch a live WAL-mode db mid-write; point
`source_directories` at the hot-copy location instead of `/data/pb`
directly if you want to be strict about never archiving the live files.)

Add it to `docker-compose.yml`:

```yaml
  borgmatic:
    image: b3vis/borgmatic
    container_name: kehai-borgmatic
    restart: unless-stopped
    volumes:
      - ./data:/data:ro
      - ./borgmatic/config.yaml:/etc/borgmatic.d/config.yaml
      - ./borgmatic/ssh:/root/.ssh:ro   # key auth to the offsite target
      - borgmatic-cache:/root/.cache/borg
volumes:
  borgmatic-cache:
```

First run initializes the repo (`docker compose exec borgmatic borgmatic
init --encryption repokey`), then it schedules itself off the config's
`keep_*` retention. Test a restore *before* you need one:

```sh
docker compose exec borgmatic borgmatic list                     # archives
docker compose exec borgmatic borgmatic extract --archive latest \
  --destination /tmp/restore-test
sqlite3 /tmp/restore-test/data/pb/data.db "PRAGMA integrity_check;"
```

A backup you've never restored isn't a backup — run that check
periodically, not just once at setup.

## Webhooks (smart home)

The server can fire outbound webhooks on couple events — the "smart-lamp /
power-user API" from `kb/features.md`. It's off by default and needs zero
setup to stay off: no config, no cost, no code path even runs.

### Config

| Env var | Required | Effect |
|---|---|---|
| `KEHAI_WEBHOOK_URLS` | no (default: unset) | Comma-separated list of URLs to `POST` to. Empty/unset = feature off. |
| `KEHAI_WEBHOOK_SECRET` | no | When set, every request carries `X-Kehai-Signature: hex(hmac-sha256(secret, body))` so your receiver can verify it actually came from your server. |

```sh
# docker-compose.yml, server service:
environment:
  KEHAI_WEBHOOK_URLS: "http://homeassistant.local:8123/api/webhook/kehai-mood,https://ntfy.example.ts.net/kehai"
  KEHAI_WEBHOOK_SECRET: "a long random string, e.g. openssl rand -hex 32"
```

Multiple URLs all get the same event, delivered independently — one goroutine
per URL, 5s timeout, no retries. A dead or slow URL never slows down the API:
the record save that triggered the event has already returned to the client
before delivery is attempted.

### Events

**`mood_changed`** — fires on every `statuses` record create/update (mood
picker, note edit):

```json
{
  "event": "mood_changed",
  "user": "u_abc123",
  "user_name": "Kasia",
  "mood": "content_kitten",
  "note": "good day, miss you",
  "at": "2026-08-23T14:02:11Z"
}
```

**`presence_changed`** — fires on a `devices` update where `activity` or
`now_playing` actually changed (a bare heartbeat with nothing new stays
silent). Debounced to at most once per user per 10 seconds, since heartbeats
can arrive every few seconds:

```json
{
  "event": "presence_changed",
  "user": "u_abc123",
  "user_name": "Kasia",
  "kind": "desktop",
  "activity": "🎮 gaming",
  "now_playing": { "title": "...", "artist": "...", "album_art": "..." },
  "at": "2026-08-23T14:02:11Z"
}
```

`now_playing` is `null` when nothing's playing.

### Home Assistant recipe

Create a [webhook trigger automation](https://www.home-assistant.io/docs/automation/trigger/#webhook-trigger)
that changes a light's color based on mood. In HA: **Settings → Automations
→ Create Automation → Skip (start with an empty automation)**, then switch to
YAML mode and paste:

```yaml
alias: Kehai mood lamp
description: Turn the bedroom lamp a color matching the partner's mood.
triggers:
  - trigger: webhook
    webhook_id: kehai-mood
    allowed_methods: [POST]
    local_only: true
conditions:
  - condition: template
    value_template: "{{ trigger.json.event == 'mood_changed' }}"
actions:
  - variables:
      mood: "{{ trigger.json.mood }}"
      color_map:
        content_kitten: [255, 200, 80]
        sleepy: [80, 60, 160]
        excited: [255, 60, 120]
        chill: [60, 160, 255]
  - action: light.turn_on
    target:
      entity_id: light.bedroom_lamp
    data:
      rgb_color: "{{ color_map.get(mood, [255, 255, 255]) }}"
      brightness_pct: 60
mode: single
```

The webhook URL to give `KEHAI_WEBHOOK_URLS` is
`http://<homeassistant-host>:8123/api/webhook/kehai-mood` (the id in
`webhook_id:` above is the last path segment — `local_only: true` keeps it
reachable only from inside the tailnet/LAN, matching this stack's no-exposed-
ports default). Home Assistant webhook triggers don't verify a shared secret
out of the box, so if you also set `KEHAI_WEBHOOK_SECRET`, add a
`condition: template` checking
`trigger.json.event` alongside a header check via a
[REST-based verification](https://www.home-assistant.io/integrations/rest/)
if you want to be stricter than "webhook URL is the secret."

### ntfy example

For a plain push notification instead of (or in addition to) a HA
automation, point a URL at your `ntfy` topic and use `curl` to confirm it
works the same way ntfy itself would receive it:

```sh
curl -s http://ntfy.example.ts.net/kehai-presence \
  -H "Title: Kehai" \
  -d "presence_changed"
```

Since ntfy expects its own simple payload format rather than raw Kehai JSON,
the practical pattern is a tiny relay: point `KEHAI_WEBHOOK_URLS` at a small
script/HA automation (webhook → REST command) that reshapes the event into
an ntfy-friendly `POST`, e.g.:

```sh
# what that relay ends up running, given a mood_changed payload:
curl -s -H "Title: Mood update" -H "Tags: mood" \
  -d "Kasia is feeling content_kitten: good day, miss you" \
  https://ntfy.example.ts.net/kehai
```

## Tailscale, built in

The base stack publishes ports on the host and leaves reaching them to you.
The Tailscale override makes the box itself a node on your tailnet — no
Tailscale install on the host, no port forwarding, nothing on the LAN or the
internet — with a real HTTPS certificate on top:

```
https://kehai.<your-tailnet>.ts.net        → the Kehai server
https://kehai.<your-tailnet>.ts.net:8443   → ntfy
```

One-time setup:

1. In the [Tailscale admin console](https://login.tailscale.com/admin/dns),
   enable **MagicDNS** and **HTTPS Certificates**.
2. Create an auth key at *Settings → Keys* (reusable: no, ephemeral: no).
3. `cp .env.example .env` and fill in `TS_AUTHKEY` (and `TS_HOSTNAME` if
   you want something other than `kehai`).
4. Start the stack with both files:

   ```sh
   docker compose -f docker-compose.yml -f docker-compose.tailscale.yml up -d
   docker compose logs tailscale        # shows the node coming up + its name
   ```

5. Install Tailscale on your phones/laptops (same tailnet), and in the app
   enter `https://kehai.<your-tailnet>.ts.net` as the server address.
6. Once you know the tailnet name, set `NTFY_PUBLIC_URL` in `.env` to the
   `:8443` URL above and `docker compose ... up -d` again so ntfy knows its
   own address.

Notes: the node runs in userspace networking mode (works on rootless Docker
and needs no capabilities); its identity persists in `./data/tailscale`, so
the auth key is only used once. Sharing the tailnet with your partner is a
matter of inviting them to it (or [sharing the node](https://tailscale.com/kb/1084/sharing)).
The plain base file keeps working exactly as before — the override only
adds, never changes, the default.

## Portal mode: TURN relay (optional)

The portal (video window between your homes) streams **peer-to-peer** —
video never touches this server. When both devices are on your Tailscale
tailnet they connect directly and nothing here is needed: `GET /api/turn`
answers an empty server list and the app quietly proceeds without a relay.

Enable the coturn relay only if you want the portal to work off-tailnet
(cellular, hotel wifi, a tablet at a place without Tailscale):

1. Generate a shared secret: `openssl rand -hex 32`
2. In `.env` (next to this compose file):

   ```sh
   KEHAI_TURN_SECRET=<that secret>
   KEHAI_TURN_URLS=turn:your-host:3478?transport=udp,turn:your-host:3478?transport=tcp
   ```

3. Add both variables under the `server` service's `environment:` and
   uncomment the `coturn` block in `docker-compose.yml`.
4. `docker compose up -d` — and open UDP 3478 + UDP 49160-49200 (and TCP
   3478) toward the host if a firewall sits in front.

The server hands each logged-in client a **time-limited** credential
(coturn's REST-auth scheme, 6h expiry, derived from the secret — nothing
long-lived ever reaches a phone). The relay only shovels encrypted bytes;
it cannot see or decrypt the call.

## Verifying the stack

```sh
docker compose config   # validate the compose file
docker compose up -d
docker compose ps       # both services should report "healthy" after their start period
curl http://localhost:8090/api/health
```
