# syntax=docker/dockerfile:1

# --- build stage ------------------------------------------------------
# go.mod declares `go 1.27`; the module has no CGO dependency (PocketBase
# uses the pure-Go modernc.org/sqlite driver), so this cross-compiles cleanly.
FROM golang:1.27-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/couples-server .

# --- runtime stage ------------------------------------------------------
FROM alpine:3.22 AS runtime

# ca-certificates: outbound HTTPS (webhooks, optional external APIs later)
# tzdata: correct local-time handling for timestamps
# wget: used by HEALTHCHECK below (part of busybox, tiny)
RUN apk add --no-cache ca-certificates tzdata wget

COPY --from=build /out/couples-server /usr/local/bin/couples-server

# PocketBase's data dir: SQLite db, uploaded files, logs. Mount a volume here.
#
# Runs as root deliberately: this is a single-tenant, self-hosted app meant
# to be operated by non-experts (see kb/README.md), and /pb_data is normally
# a *bind* mount of a host directory (deploy/docker-compose.yml), not a named
# volume. A non-root container user would need its UID to match the host
# directory owner or every deploy would crash with "unable to open database
# file" — a bad first-run experience for exactly the audience this app is
# for. If you want to harden this, either chown the host's ./data/pb to a
# fixed UID and add a matching `user:` to the compose service, or switch to
# a named Docker volume (which Docker initializes with this image's owner).
RUN mkdir -p /pb_data
VOLUME ["/pb_data"]

EXPOSE 8090

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
	CMD wget -q -O - http://127.0.0.1:8090/api/health || exit 1

ENTRYPOINT ["/usr/local/bin/couples-server", "serve", "--http=0.0.0.0:8090", "--dir", "/pb_data"]
