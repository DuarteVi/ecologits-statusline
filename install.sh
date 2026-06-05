#!/usr/bin/env bash
#
# Installer for the EcoLogits Claude Code impact bar (drop-in component).
#
# Non-destructive by design: it NEVER edits your settings.json or any
# statusline.sh. It only:
#   - Verifies dependencies (jq, curl)
#   - Copies ecologits-bar.sh to ~/.claude/ecologits-bar.sh
#   - Copies ecologits.config.sh to ~/.claude (without clobbering an existing one)
#   - Prints the two lines you paste into your own statusline.sh
#
# If you don't have a status line yet, it prints a complete starter instead.
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
DEST="$CLAUDE_DIR/ecologits-bar.sh"
CONFIG_DEST="$CLAUDE_DIR/ecologits.config.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

info() { printf '\033[36m▸ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }
err()  { printf '\033[31m✗ %s\033[0m\n' "$1" >&2; }

# The exact block users paste into their own statusline.sh. Inline model:
# capture the bar into a variable, then drop ${ECOLOGITS_LINE} into your line.
print_snippet() {
  printf '\033[90m# ─── EcoLogits impact bar — https://ecologits.ai ───\033[0m\n'
  printf '\033[90m# 1) After "input=$(cat)", capture the bar into a variable:\033[0m\n'
  printf 'ECOLOGITS_LINE=$(printf '\''%%s'\'' "$input" | ~/.claude/ecologits-bar.sh)\n'
  printf '\033[90m# 2) Then drop ${ECOLOGITS_LINE} anywhere in your own line, e.g.:\033[0m\n'
  printf 'echo -e "...your status line... | ${ECOLOGITS_LINE}"\n'
}

# 1. Dependencies -----------------------------------------------------------
missing=()
command -v jq   >/dev/null 2>&1 || missing+=("jq")
command -v curl >/dev/null 2>&1 || missing+=("curl")
if [ "${#missing[@]}" -gt 0 ]; then
  err "Missing dependencies: ${missing[*]}"
  echo "  macOS:         brew install ${missing[*]}"
  echo "  Debian/Ubuntu: sudo apt-get install -y ${missing[*]}"
  exit 1
fi
ok "Dependencies present (jq, curl)"

# 2. Install the bar script + config ----------------------------------------
mkdir -p "$CLAUDE_DIR/ecologits-cache"
cp "$SRC_DIR/ecologits-bar.sh" "$DEST"
chmod +x "$DEST"
ok "Installed impact bar -> $DEST"

if [ -f "$CONFIG_DEST" ]; then
  info "Keeping your existing config -> $CONFIG_DEST"
else
  cp "$SRC_DIR/ecologits.config.sh" "$CONFIG_DEST"
  ok "Installed config -> $CONFIG_DEST (edit to pick model & metrics)"
fi

# 3. Tell the user exactly what to paste, branching on whether they already
#    have a status line. We never modify their files. ------------------------
echo

existing_type=""
existing_cmd=""
if [ -f "$SETTINGS" ]; then
  existing_type=$(jq -r '.statusLine.type // empty' "$SETTINGS" 2>/dev/null || true)
  existing_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null || true)
fi

if [ "$existing_type" = "command" ] && [ -n "$existing_cmd" ]; then
  info "You already have a status line. Add the capture line below to your"
  info "script (it must capture stdin via: input=\$(cat)), then place"
  info "\${ECOLOGITS_LINE} wherever you want the impact figures to appear."

  # If the command resolves to a script file we can name, point right at it.
  script_path="${existing_cmd%% *}"
  script_path="${script_path/#\~/$HOME}"
  if [ -f "$script_path" ]; then
    echo "  Your status line script: $script_path"
  else
    echo "  Your status line command: $existing_cmd"
  fi
  echo
  print_snippet
else
  info "No 'command' status line found — here's a complete starter."
  info "1) Create ~/.claude/statusline.sh with:"
  echo
  cat <<'STARTER'
    #!/usr/bin/env bash
    input=$(cat)

    # ─── EcoLogits impact bar — https://ecologits.ai ───
    # 1) Capture the impact bar into a variable:
    ECOLOGITS_LINE=$(printf '%s' "$input" | ~/.claude/ecologits-bar.sh)

    # 2) Place ${ECOLOGITS_LINE} anywhere in your own status line:
    echo -e "my prompt | ${ECOLOGITS_LINE}"
STARTER
  echo
  info "2) Make it executable:  chmod +x ~/.claude/statusline.sh"
  info "3) Point Claude Code at it — add this to ~/.claude/settings.json:"
  echo
  cat <<'SETTINGS_JSON'
    "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 2 }
SETTINGS_JSON
fi

echo
ok "Done. Open a new Claude Code session (or wait for the next render)."
echo "  The bar shows 0 until the first response, then live impact figures."
echo "  Customize the model & displayed metrics in: $CONFIG_DEST"
