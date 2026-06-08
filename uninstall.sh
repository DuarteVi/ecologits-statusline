#!/usr/bin/env bash
#
# Uninstaller for the EcoLogits Claude Code impact bar (drop-in component).
#
# Removes the bar script and its cache. Since the bar is a block YOU pasted into
# your own statusline.sh, we can't safely un-paste it — we print the exact block
# to delete instead. Your config is kept unless you pass --purge.
#
#   ./uninstall.sh          remove bar + cache, keep config
#   ./uninstall.sh --purge  also remove ecologits.config.sh
#
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/ecologits-bar.sh"
CONFIG_DEST="$CLAUDE_DIR/ecologits.config.sh"
CACHE_DIR="$CLAUDE_DIR/ecologits-cache"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }

# 1. Remove the bar + cache -------------------------------------------------
rm -f "$DEST"
rm -rf "$CACHE_DIR"
ok "Removed impact bar and cache directory"

if [ "$PURGE" -eq 1 ]; then
  rm -f "$CONFIG_DEST"
  ok "Removed config -> $CONFIG_DEST"
else
  info "Kept your config -> $CONFIG_DEST (pass --purge to remove it)"
fi

# 2. Remind the user to delete the pasted line ------------------------------
echo
info "Now delete the EcoLogits block from your statusline.sh (we don't edit it for you):"
echo
printf '\033[90m    # ─── EcoLogits impact bar — https://ecologits.ai ───\033[0m\n'
printf '    ECOLOGITS_LINE=$(printf '\''%%s'\'' "$input" | ~/.claude/ecologits-bar.sh)\n'
printf '    echo -e "${ECOLOGITS_LINE}"\n'
echo
ok "Done. Open a new Claude Code session (or wait for the next render)."
