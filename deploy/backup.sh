#!/bin/sh
# Nightly backup of the PocketBase data dir (deploy/README.md "Backups").
#
# The tricky part: data.db and auxiliary.db are live SQLite databases in
# WAL mode (data.db-wal/-shm sit next to them) while the server is running.
# A raw `cp`/`tar` of those files can grab a half-written page or miss
# committed-but-not-checkpointed WAL frames. `sqlite3 "$db" ".backup ..."`
# uses SQLite's online backup API instead — it locks and copies a
# consistent snapshot while the server keeps writing, no downtime and no
# torn pages. Everything else under /pb_data (uploaded files in storage/,
# the .notify state dir) isn't a database, so it's just copied.
set -eu

SRC=/pb_data
OUT_DIR=/backups
KEEP=14
STAMP=$(date +%Y%m%d)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT_DIR"

for db in data.db auxiliary.db; do
  if [ -f "$SRC/$db" ]; then
    sqlite3 "$SRC/$db" ".backup '$WORK/$db'"
  fi
done

# Everything that isn't one of the db files/journals above (storage/,
# .notify/, and anything future migrations add) copied as-is.
find "$SRC" -mindepth 1 -maxdepth 1 \
  ! -name 'data.db*' ! -name 'auxiliary.db*' \
  -exec cp -a {} "$WORK/" \;

OUT="$OUT_DIR/kehai-$STAMP.tar.gz"
tar -C "$WORK" -czf "$OUT.tmp" .
mv "$OUT.tmp" "$OUT"
echo "$(date -Iseconds) wrote $OUT ($(du -h "$OUT" | cut -f1))"

# Retention: keep the most recent $KEEP nightly archives.
# shellcheck disable=SC2012
ls -1t "$OUT_DIR"/kehai-*.tar.gz 2>/dev/null | tail -n "+$((KEEP + 1))" | \
  while IFS= read -r stale; do
    rm -f "$stale"
    echo "$(date -Iseconds) pruned $stale"
  done
