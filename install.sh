#!/usr/bin/env bash
#
# Installer for the EcoLogits Claude Code status line.
# - Verifies dependencies (jq, curl)
# - Copies statusline.sh to ~/.claude/ecologits-statusline.sh
# - Merges the statusLine setting into ~/.claude/settings.json (with a backup)
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/ecologits-statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
err()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; }

# 1. Dependencies -----------------------------------------------------------
missing=()
command -v jq   >/dev/null 2>&1 || missing+=("jq")
command -v curl >/dev/null 2>&1 || missing+=("curl")
if [ "${#missing[@]}" -gt 0 ]; then
  err "Missing dependencies: ${missing[*]}"
  echo "  macOS:        brew install ${missing[*]}"
  echo "  Debian/Ubuntu: sudo apt-get install -y ${missing[*]}"
  exit 1
fi
ok "Dependencies present (jq, curl)"

# 2. Install the script -----------------------------------------------------
mkdir -p "$CLAUDE_DIR/ecologits-cache"
cp "$SRC_DIR/statusline.sh" "$DEST"
chmod +x "$DEST"
ok "Installed status line script -> $DEST"

# 3. Merge the statusLine setting ------------------------------------------
NEW_STATUSLINE=$(jq -n --arg cmd "$DEST" \
  '{type: "command", command: $cmd, padding: 2}')

if [ -f "$SETTINGS" ]; then
  BACKUP="$SETTINGS.bak.$$"
  cp "$SETTINGS" "$BACKUP"
  if jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
    info "An existing statusLine was found; it will be replaced (backup: $BACKUP)"
  fi
  tmp=$(mktemp)
  jq --argjson sl "$NEW_STATUSLINE" '.statusLine = $sl' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  ok "Updated $SETTINGS (backup: $BACKUP)"
else
  jq -n --argjson sl "$NEW_STATUSLINE" '{statusLine: $sl}' > "$SETTINGS"
  ok "Created $SETTINGS"
fi

echo
ok "Done. Open a new Claude Code session (or wait for the next render)."
echo "  The eco line shows '…' until the first response, then live CO₂eq + water."
echo "  Customize via env vars: ECOLOGITS_MODEL, ECOLOGITS_ZONE, ECOLOGITS_API"
