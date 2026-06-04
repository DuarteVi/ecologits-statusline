#!/usr/bin/env bash
#
# EcoLogits status line for Claude Code
# Shows the estimated environmental impact (CO₂eq + water) of the current
# session's generated tokens, using the public EcoLogits API.
#
# Repo: https://github.com/<your-user>/ecologits-statusline
# Powered by EcoLogits — https://ecologits.ai  •  https://api.ecologits.ai
#
# Configurable via environment variables (set them in your shell profile):
#   ECOLOGITS_API    estimations endpoint   (default: https://api.ecologits.ai/v1beta/estimations)
#   ECOLOGITS_MODEL  model sent to the API  (default: claude-opus-4-6 — highest the public API serves)
#   ECOLOGITS_ZONE   electricity mix zone   (default: WOR — world average; e.g. USA, FRA)
#
# Dependencies: bash, jq, curl

input=$(cat)

# ---- Status-line input -----------------------------------------------------
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
TRANSCRIPT=$(echo "$input" | jq -r '.transcript_path // empty')
SESSION=$(echo "$input" | jq -r '.session_id // "default"')

CYAN='\033[36m'; GRAY='\033[90m'; RESET='\033[0m'

BRANCH=""
if [ -n "$DIR" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  BRANCH=" | 🌿 $(git -C "$DIR" branch --show-current 2>/dev/null)"
fi

# ---- EcoLogits environmental-impact counter --------------------------------
ECO_API="${ECOLOGITS_API:-https://api.ecologits.ai/v1beta/estimations}"
ECO_MODEL="${ECOLOGITS_MODEL:-claude-opus-4-6}"
ECO_ZONE="${ECOLOGITS_ZONE:-WOR}"
ECO_DIR="$HOME/.claude/ecologits-cache"
ECO_CACHE="$ECO_DIR/$SESSION.json"     # holds: "<tokens> <gwp_kg> <wcf_L>"
ECO_LOCK="$ECO_DIR/$SESSION.inflight"
mkdir -p "$ECO_DIR" 2>/dev/null

# Cumulative output tokens for this session (sum over the transcript).
TOKENS=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  TOKENS=$(jq -n 'reduce inputs as $x (0; . + ($x.message.usage.output_tokens // 0))' < "$TRANSCRIPT" 2>/dev/null)
  [ -z "$TOKENS" ] && TOKENS=0
fi

# Read cached impact values, if any.
CACHED_TOKENS=-1; GWP=""; WCF=""
if [ -f "$ECO_CACHE" ]; then
  read -r CACHED_TOKENS GWP WCF < "$ECO_CACHE" 2>/dev/null
  [ -z "$CACHED_TOKENS" ] && CACHED_TOKENS=-1
fi

# Refresh in the background only when output tokens have grown, and not when a
# fetch for this exact token count is already in flight. No tokens / idle = no
# API call. The status line itself never blocks on the network.
if [ "$TOKENS" -gt 0 ] && [ "$TOKENS" != "$CACHED_TOKENS" ]; then
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
          "\(.impacts.gwp.value.min + .impacts.gwp.value.max | . / 2) \(.impacts.wcf.value.min + .impacts.wcf.value.max | . / 2)"
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

if [ -n "$GWP" ] && [ -n "$WCF" ]; then
  ECO_LINE="🤖 ${ECO_MODEL} | 🔥 $(fmt_gwp "$GWP") | 💧 $(fmt_wcf "$WCF")"
else
  ECO_LINE="🤖 ${ECO_MODEL} | …"
fi

# ---- Render ----------------------------------------------------------------
echo -e "${CYAN}[$MODEL]${RESET} 📁 ${DIR##*/}$BRANCH"
echo -e "${GRAY}${ECO_LINE}${RESET}"
