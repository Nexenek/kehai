#!/usr/bin/env bash
# fake-asleep.sh — pretend one account's phone is deep in the night, so you
# can watch the partner's app flip to "asleep zzZ" without waiting for 22:00
# (or being unconscious while it happens).
#
# What the asleep rung actually needs (see app/lib/domain/models/ambient_line.dart):
#   - an ONLINE device of kind "phone" (heartbeat within the last 2 minutes)
#   - EITHER idle_seconds >= 45 min AND local hour at the phone's reported
#     UTC offset in 22:00–08:00, OR idle_seconds >= 3 h at any hour (the
#     gremlin-hours rung — deep idle beats the clock)
# Nothing is ever "sent" as asleep — the VIEWER computes it from these plain
# heartbeat fields. This script just posts heartbeats with a big idle and a
# timezone where it is currently night, as a separate device named
# "sleep-test" (so your real phone's record is never touched).
#
# Usage:  ./fake-asleep.sh EMAIL PASSWORD [SERVER_URL]
#         (the EMAIL account is the one that will LOOK asleep; watch the
#         OTHER account's app. Ctrl-C to stop — the fake device goes stale
#         and stops counting ~2 minutes later.)
#
# Caveat: higher ambient rungs win. If the faked account is also playing
# music, showing an activity, or actively using a low-idle device, that
# shows instead of zzZ — leave its real devices alone during the test.

set -euo pipefail

EMAIL="${1:?usage: fake-asleep.sh EMAIL PASSWORD [SERVER_URL]}"
PASSWORD="${2:?usage: fake-asleep.sh EMAIL PASSWORD [SERVER_URL]}"
SERVER="${3:-http://localhost:8090}"

TOKEN=$(curl -sf -X POST "$SERVER/api/collections/users/auth-with-password" \
  -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" |
  sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "login failed for $EMAIL at $SERVER" >&2; exit 1; }

# Pick a UTC offset where the local clock currently reads 23:xx.
utc_hour=$(date -u +%-H)
offset=$(( (23 - utc_hour + 24) % 24 ))
[ "$offset" -gt 14 ] && offset=$((offset - 24))
tz=$(printf 'UTC%+03d:00' "$offset")

echo "posting sleeping-phone heartbeats as device 'sleep-test' ($tz, idle 60min)"
echo "watch the PARTNER's app — 'asleep zzZ' should appear within ~30s. Ctrl-C to stop."

while true; do
  curl -sf -X POST "$SERVER/api/heartbeat" \
    -H "Authorization: $TOKEN" -H 'Content-Type: application/json' \
    -d "{\"kind\":\"phone\",\"name\":\"sleep-test\",\"idle_seconds\":3600,\"timezone\":\"$tz\"}" \
    > /dev/null && printf '.' || printf 'x'
  sleep 25
done
