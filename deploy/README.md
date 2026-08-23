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
stack means backing up that one directory. Recommended approach:

- Use PocketBase's built-in backup mechanism (via the admin dashboard or
  its backup API) rather than copying the live SQLite file directly, to
  avoid grabbing it mid-write.
- Run a nightly encrypted backup job (e.g. `restic` or `borgmatic`) of
  `./data/` to a second machine or drive — don't rely on a single copy.
- Periodically test that a backup actually restores. A backup you've
  never restored isn't a backup.

This is deliberately a generic summary — if you're the project's
maintainer, your local knowledgebase has the fuller stack/security
write-up this repo doesn't otherwise carry.

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

## Verifying the stack

```sh
docker compose config   # validate the compose file
docker compose up -d
docker compose ps       # both services should report "healthy" after their start period
curl http://localhost:8090/api/health
```
