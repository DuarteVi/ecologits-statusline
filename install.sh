#!/usr/bin/env bash
#
# Installer for the EcoLogits Claude Code status line (additive / wrapper).
# - Verifies dependencies (jq, curl)
# - Copies ecologits-statusline.sh to ~/.claude/ecologits-statusline.sh
# - Saves your CURRENT status line command so EcoLogits can run it and append
#   its line below (instead of replacing your status line)
# - Points the statusLine setting at the EcoLogits wrapper (backup taken)
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/ecologits-statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
BASE_FILE="$CLAUDE_DIR/ecologits-base.cmd"
SELF_MARKER="ecologits-statusline.sh"

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

# 2. Install the wrapper script --------------------------------------------
mkdir -p "$CLAUDE_DIR/ecologits-cache"
cp "$SRC_DIR/ecologits-statusline.sh" "$DEST"
chmod +x "$DEST"
ok "Installed wrapper script -> $DEST"

# 3. Decide what to wrap, then point statusLine at the wrapper --------------
NEW_STATUSLINE=$(jq -n --arg cmd "$DEST" '{type: "command", command: $cmd, padding: 2}')

if [ -f "$SETTINGS" ]; then
  BACKUP="$SETTINGS.bak.$$"
  cp "$SETTINGS" "$BACKUP"

  existing_type=$(jq -r '.statusLine.type // empty' "$SETTINGS")
  existing_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  existing_any=$(jq -r 'if .statusLine then "yes" else "" end' "$SETTINGS")

  if [ -n "$existing_cmd" ] && [[ "$existing_cmd" == *"$SELF_MARKER"* ]]; then
    info "EcoLogits is already installed; keeping the wrapped base in $BASE_FILE"
  elif [ -n "$existing_cmd" ] && [ "$existing_type" = "command" ]; then
    printf '%s' "$existing_cmd" > "$BASE_FILE"
    info "Wrapping your existing status line (saved to $BASE_FILE):"
    echo "    $existing_cmd"
  elif [ -n "$existing_any" ]; then
    rm -f "$BASE_FILE"
    info "Existing statusLine is type '${existing_type:-?}' (not 'command') and can't be chained."
    info "The eco line will show standalone."
  else
    rm -f "$BASE_FILE"
    info "No existing status line found; the eco line will show standalone."
  fi

  tmp=$(mktemp)
  jq --argjson sl "$NEW_STATUSLINE" '.statusLine = $sl' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  ok "Updated $SETTINGS (backup: $BACKUP)"
else
  rm -f "$BASE_FILE"
  jq -n --argjson sl "$NEW_STATUSLINE" '{statusLine: $sl}' > "$SETTINGS"
  info "No existing status line found; the eco line will show standalone."
  ok "Created $SETTINGS"
fi

echo
ok "Done. Open a new Claude Code session (or wait for the next render)."
echo "  Your existing status line is preserved; the eco line is added below it."
echo "  It shows '…' until the first response, then live CO₂eq + water."
echo "  Customize via env vars: ECOLOGITS_MODEL, ECOLOGITS_ZONE, ECOLOGITS_API"
