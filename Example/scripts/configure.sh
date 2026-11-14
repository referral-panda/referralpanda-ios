#!/bin/sh
# Writes Local.xcconfig from the file the React Native playground uses
# (apps/playground/.env.local, made by `pnpm --filter @referralpanda/e2e seed:playground`),
# then generates the Xcode project. The key is a sandbox public key. It is not committed.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
env_file="$here/../../../apps/playground/.env.local"
out="$here/Local.xcconfig"

value() { [ -f "$env_file" ] && sed -n "s/^$1=//p" "$env_file" | head -1 || true; }
# In an xcconfig file "//" starts a comment, so a URL is written with an empty variable in it.
url() { printf '%s' "$1" | sed 's|//|/$()/|'; }

key="$(value EXPO_PUBLIC_RP_API_KEY)"
api="$(value EXPO_PUBLIC_RP_API_URL)"
host="$(value EXPO_PUBLIC_RP_LINK_HOST)"
{
  echo "RP_API_KEY = $key"
  [ -n "$api" ] && echo "RP_API_URL = $(url "$api")"
  [ -n "$host" ] && echo "RP_LINK_HOST = $host"
  echo "RP_AUTO_USER = ${RP_AUTO_USER:-}"
} > "$out"

if [ -z "$key" ]; then
  echo "No key found in apps/playground/.env.local. Only the Fixtures tab will work."
else
  echo "Wrote Local.xcconfig with a sandbox key."
fi
cd "$here" && xcodegen generate --quiet
echo "Generated ReferralPandaPlayground.xcodeproj"
