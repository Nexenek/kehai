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

## Verifying the stack

```sh
docker compose config   # validate the compose file
docker compose up -d
docker compose ps       # both services should report "healthy" after their start period
curl http://localhost:8090/api/health
```
