#!/usr/bin/env bash
#
# EcoLogits status line for Claude Code  (additive / wrapper)
#
# This is designed to ADD a line to your existing status line, not replace it.
# It runs your previously configured status line first (saved by install.sh to
# ~/.claude/ecologits-base.cmd), prints its output unchanged, then appends one
# extra line with the estimated environmental impact (CO₂eq + water) of the
# current session's generated tokens, via the public EcoLogits API.
#
# If no base status line is configured, it just prints the eco line on its own.
#
# Repo: https://github.com/<your-user>/ecologits-statusline
# Powered by EcoLogits — https://ecologits.ai  •  https://api.ecologits.ai
#
# Configurable via environment variables:
#   ECOLOGITS_API       estimations endpoint   (default: https://api.ecologits.ai/v1beta/estimations)
#   ECOLOGITS_MODEL     model sent to the API  (default: claude-opus-4-6)
#   ECOLOGITS_ZONE      electricity mix zone   (default: WOR — world average; e.g. USA, FRA)
#   ECOLOGITS_BASE_CMD  base status-line command to wrap (overrides the saved file)
#
# Dependencies: bash, jq, curl

input=$(cat)

SELF_MARKER="ecologits-statusline.sh"   # guard against wrapping ourselves
BASE_FILE="$HOME/.claude/ecologits-base.cmd"

SESSION=$(echo "$input" | jq -r '.session_id // "default"')
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // empty')

GRAY='\033[90m'; RESET='\033[0m'

# ---- Run the wrapped (existing) status line first, if any ------------------
BASE_CMD="${ECOLOGITS_BASE_CMD:-}"
if [ -z "$BASE_CMD" ] && [ -s "$BASE_FILE" ]; then
  BASE_CMD=$(cat "$BASE_FILE")
fi
BASE_OUT=""
if [ -n "$BASE_CMD" ] && [[ "$BASE_CMD" != *"$SELF_MARKER"* ]]; then
  # Feed the same stdin JSON to the wrapped status line and capture its output.
  BASE_OUT=$(printf '%s' "$input" | bash -c "$BASE_CMD" 2>/dev/null)
fi

# ---- EcoLogits environmental-impact counter --------------------------------
ECO_API="${ECOLOGITS_API:-https://api.ecologits.ai/v1beta/estimations}"
ECO_MODEL="${ECOLOGITS_MODEL:-claude-opus-4-6}"
ECO_ZONE="${ECOLOGITS_ZONE:-WOR}"
ECO_DIR="$HOME/.claude/ecologits-cache"
ECO_CACHE="$ECO_DIR/$SESSION.json"     # holds: "<tokens> <gwp_kg> <wcf_L> <energy_kWh>"
ECO_LOCK="$ECO_DIR/$SESSION.inflight"
mkdir -p "$ECO_DIR" 2>/dev/null

# Cumulative output tokens for this session (sum over the transcript).
TOKENS=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  TOKENS=$(jq -n 'reduce inputs as $x (0; . + ($x.message.usage.output_tokens // 0))' < "$TRANSCRIPT" 2>/dev/null)
  [ -z "$TOKENS" ] && TOKENS=0
fi

# Read cached impact values, if any.
CACHED_TOKENS=-1; GWP=""; WCF=""; ENERGY=""
if [ -f "$ECO_CACHE" ]; then
  read -r CACHED_TOKENS GWP WCF ENERGY < "$ECO_CACHE" 2>/dev/null
  [ -z "$CACHED_TOKENS" ] && CACHED_TOKENS=-1
fi

# Refresh in the background when output tokens have grown (or the cache predates
# the energy field), and not when a fetch for this exact token count is already
# in flight. No tokens / idle = no API call. The status line never blocks on
# the network.
if [ "$TOKENS" -gt 0 ] && { [ "$TOKENS" != "$CACHED_TOKENS" ] || [ -z "$ENERGY" ]; }; then
  INFLIGHT=""
  [ -f "$ECO_LOCK" ] && INFLIGHT=$(cat "$ECO_LOCK" 2>/dev/null)
  if [ "$INFLIGHT" != "$TOKENS" ]; then
    (
      echo "$TOKENS" > "$ECO_LOCK"
      RESP=$(curl -s --max-time 8 -X POST "$ECO_API" \
        -H "Content-Type: application/json" \
        -d "{\"provider\":\"anthropic\",\"model_name\":\"$ECO_MODEL\",\"output_token_count\":$TOKENS,\"electricity_mix_zone\":\"$ECO_ZONE\"}")
      LINE=$(echo "$RESP" | jq -r '
        if .impacts.gwp.value then
          "\(.impacts.gwp.value.min + .impacts.gwp.value.max | . / 2) \(.impacts.wcf.value.min + .impacts.wcf.value.max | . / 2) \(.impacts.energy.value.min + .impacts.energy.value.max | . / 2)"
        else empty end' 2>/dev/null)
      # Only overwrite the cache on a valid response, so a failed/offline
      # refresh keeps the last-known value instead of blanking it.
      if [ -n "$LINE" ]; then
        echo "$TOKENS $LINE" > "$ECO_CACHE.tmp" && mv "$ECO_CACHE.tmp" "$ECO_CACHE"
      fi
      rm -f "$ECO_LOCK"
    ) >/dev/null 2>&1 &
  fi
fi

# Auto-scaling unit formatters.
fmt_gwp() {  # kgCO₂eq -> mg / g / kg
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "—"; exit }
    if (v>=1)          printf "%.2f kgCO₂eq", v;
    else if (v>=0.001) { g=v*1000; if (g>=10) printf "%.0f gCO₂eq", g; else printf "%.1f gCO₂eq", g; }
    else               printf "%.0f mgCO₂eq", v*1000000;
  }'
}
fmt_wcf() {  # litres -> mL / L
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "—"; exit }
    if (v>=1) printf "%.2f L", v;
    else { ml=v*1000; if (ml>=10) printf "%.0f mL", ml; else if (ml>=1) printf "%.1f mL", ml; else printf "%.2f mL", ml; }
  }'
}
fmt_energy() {  # kWh -> mWh / Wh / kWh
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "—"; exit }
    if (v>=1) printf "%.2f kWh", v;
    else { wh=v*1000; if (wh>=10) printf "%.0f Wh", wh; else if (wh>=1) printf "%.1f Wh", wh; else printf "%.0f mWh", v*1000000; }
  }'
}

if [ -n "$GWP" ] && [ -n "$WCF" ] && [ -n "$ENERGY" ]; then
  ECO_LINE="🤖 ${ECO_MODEL} | ⚡ $(fmt_energy "$ENERGY") | 🔥 $(fmt_gwp "$GWP") | 💧 $(fmt_wcf "$WCF")"
else
  ECO_LINE="🤖 ${ECO_MODEL} | …"
fi

# ---- Render: existing status line unchanged, then the eco line below -------
[ -n "$BASE_OUT" ] && printf '%s\n' "$BASE_OUT"
printf '%b\n' "${GRAY}${ECO_LINE}${RESET}"
