#!/usr/bin/env bash
#
# Uninstaller for the EcoLogits Claude Code status line (additive / wrapper).
# - Restores your original status line command (the one EcoLogits was wrapping),
#   or removes the statusLine entry entirely if you had none (backup taken)
# - Removes the wrapper script, the saved base command, and the cache directory
#
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/ecologits-statusline.sh"
CONFIG_DEST="$CLAUDE_DIR/ecologits.config.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
BASE_FILE="$CLAUDE_DIR/ecologits-wrapped-statusline.txt"
CACHE_DIR="$CLAUDE_DIR/ecologits-cache"
SELF_MARKER="ecologits-statusline.sh"

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
err()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; }

# 1. Restore the original status line ---------------------------------------
if [ -f "$SETTINGS" ]; then
  current_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS")

  if [ -n "$current_cmd" ] && [[ "$current_cmd" == *"$SELF_MARKER"* ]]; then
    BACKUP="$SETTINGS.bak.$$"
    cp "$SETTINGS" "$BACKUP"

    base_cmd=""
    [ -f "$BASE_FILE" ] && base_cmd=$(cat "$BASE_FILE")

    tmp=$(mktemp)
    if [ -n "$base_cmd" ]; then
      jq --arg c "$base_cmd" \
        '.statusLine = {type: "command", command: $c, padding: 2}' \
        "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      info "Restored your original status line:"
      echo "    $base_cmd"
    else
      jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      info "No wrapped status line was saved; removed the statusLine entry."
    fi
    ok "Updated $SETTINGS (backup: $BACKUP)"
  elif [ -n "$current_cmd" ]; then
    info "statusLine doesn't point at EcoLogits; leaving $SETTINGS untouched."
  else
    info "No statusLine entry found; leaving $SETTINGS untouched."
  fi
else
  info "No settings file at $SETTINGS; nothing to restore."
fi

# 2. Remove EcoLogits files -------------------------------------------------
rm -f "$DEST" "$CONFIG_DEST" "$BASE_FILE"
rm -rf "$CACHE_DIR"
ok "Removed wrapper script, config, saved base command, and cache directory"

echo
ok "Done. EcoLogits status line uninstalled."
echo "  Open a new Claude Code session (or wait for the next render) to see the change."
