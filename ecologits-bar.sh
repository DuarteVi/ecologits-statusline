#!/usr/bin/env bash
#
# EcoLogits impact bar for Claude Code  (drop-in component)
#
# This prints ONE line estimating the environmental impact — energy, greenhouse
# gas, freshwater — of the current session's generated tokens, via the public
# EcoLogits API. It is meant to be called from inside YOUR OWN statusline.sh,
# which keeps full ownership of its output. Add this after your line prints:
#
#     printf '%s' "$input" | ~/.claude/ecologits-bar.sh
#
# where $input holds the JSON Claude Code sent on stdin (the canonical
# `input=$(cat)` at the top of a statusline script). The bar reads that JSON on
# its own stdin and appends its line below yours.
#
# Repo: https://github.com/<your-user>/ecologits-statusline
# Powered by EcoLogits — https://ecologits.ai  •  https://api.ecologits.ai
#
# Configuration: edit ~/.claude/ecologits.config.sh (sourced below). Each value
# can also be overridden by an exported environment variable of the same name:
#   ECOLOGITS_MODEL     model sent to the API   (default: claude-opus-4-6)
#   ECOLOGITS_ZONE      electricity-mix zone for the server location (default: WOR)
#   ECOLOGITS_METRICS   impacts to display      (default: "gwp wcf energy")
#   ECOLOGITS_MODEL_LABEL  prefix before metrics (default: empty = hidden)
#   ECOLOGITS_API       estimations endpoint    (default: api.ecologits.ai)
#
# Dependencies: bash, jq, curl

input=$(cat)

CONFIG_FILE="$HOME/.claude/ecologits.config.sh"

# Load user configuration (real exported env vars still take precedence,
# because the config file uses `: "${VAR:=default}"` assignments).
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

GRAY='\033[90m'; RESET='\033[0m'

# ---- No usable input? Most likely the snippet's $input wasn't the captured
#      stdin (e.g. your script names it differently, or never ran `input=$(cat)`).
#      Print a visible hint rather than a normal-looking bar that never advances.
SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -z "$SESSION" ] && [ -z "$TRANSCRIPT" ]; then
  printf '%b\n' "${GRAY}🤖 EcoLogits: no input — is your captured stdin named \$input?${RESET}"
  exit 0
fi
[ -z "$SESSION" ] && SESSION="default"

# ---- EcoLogits environmental-impact counter --------------------------------
ECO_API="${ECOLOGITS_API:-https://api.ecologits.ai/v1beta/estimations}"
ECO_MODEL="${ECOLOGITS_MODEL:-claude-opus-4-6}"
ECO_ZONE="${ECOLOGITS_ZONE:-WOR}"
ECO_METRICS="${ECOLOGITS_METRICS:-gwp wcf energy}"
# Optional prefix shown before the metrics (hidden by default). Set
# ECOLOGITS_MODEL_LABEL in the config to display e.g. "🤖 $ECOLOGITS_MODEL".
ECO_LABEL="${ECOLOGITS_MODEL_LABEL:-}"
ECO_DIR="$HOME/.claude/ecologits-cache"
# Cache holds: "<tokens> <gwp_kg> <wcf_L> <energy_kWh> <adpe_kg> <pe_MJ>"
ECO_CACHE="$ECO_DIR/$SESSION.json"
ECO_LOCK="$ECO_DIR/$SESSION.inflight"
mkdir -p "$ECO_DIR" 2>/dev/null

# Cumulative output tokens for this session (sum over the transcript).
TOKENS=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  TOKENS=$(jq -n 'reduce inputs as $x (0; . + ($x.message.usage.output_tokens // 0))' < "$TRANSCRIPT" 2>/dev/null)
  [ -z "$TOKENS" ] && TOKENS=0
fi

# Read cached impact values, if any.
CACHED_TOKENS=-1; GWP=""; WCF=""; ENERGY=""; ADPE=""; PE=""
if [ -f "$ECO_CACHE" ]; then
  read -r CACHED_TOKENS GWP WCF ENERGY ADPE PE < "$ECO_CACHE" 2>/dev/null
  [ -z "$CACHED_TOKENS" ] && CACHED_TOKENS=-1
fi

# Refresh in the background when output tokens have grown, or when the cache is
# missing any metric (e.g. written by an older version), and not when a fetch
# for this exact token count is already in flight. No tokens / idle = no API
# call. The status line never blocks on the network.
NEED_REFRESH=0
[ "$TOKENS" != "$CACHED_TOKENS" ] && NEED_REFRESH=1
for v in "$GWP" "$WCF" "$ENERGY" "$ADPE" "$PE"; do
  [ -z "$v" ] && NEED_REFRESH=1
done
if [ "$TOKENS" -gt 0 ] && [ "$NEED_REFRESH" -eq 1 ]; then
  INFLIGHT=""
  [ -f "$ECO_LOCK" ] && INFLIGHT=$(cat "$ECO_LOCK" 2>/dev/null)
  if [ "$INFLIGHT" != "$TOKENS" ]; then
    (
      echo "$TOKENS" > "$ECO_LOCK"
      RESP=$(curl -s --max-time 8 -X POST "$ECO_API" \
        -H "Content-Type: application/json" \
        -d "{\"provider\":\"anthropic\",\"model_name\":\"$ECO_MODEL\",\"output_token_count\":$TOKENS,\"electricity_mix_zone\":\"$ECO_ZONE\"}")
      LINE=$(echo "$RESP" | jq -r '
        def mid(x): (x.min + x.max) / 2;
        if .impacts.gwp.value then
          "\(mid(.impacts.gwp.value)) \(mid(.impacts.wcf.value)) \(mid(.impacts.energy.value)) \(mid(.impacts.adpe.value)) \(mid(.impacts.pe.value))"
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

# Auto-scaling unit formatters (one per metric).
fmt_gwp() {  # kgCO₂eq -> mg / g / kg
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "0"; exit }
    if (v>=1)          printf "%.2f kgCO₂eq", v;
    else if (v>=0.001) { g=v*1000; if (g>=10) printf "%.0f gCO₂eq", g; else printf "%.1f gCO₂eq", g; }
    else               printf "%.0f mgCO₂eq", v*1000000;
  }'
}
fmt_wcf() {  # litres -> mL / L
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "0"; exit }
    if (v>=1) printf "%.2f L", v;
    else { ml=v*1000; if (ml>=10) printf "%.0f mL", ml; else if (ml>=1) printf "%.1f mL", ml; else printf "%.2f mL", ml; }
  }'
}
fmt_energy() {  # kWh -> mWh / Wh / kWh
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "0"; exit }
    if (v>=1) printf "%.2f kWh", v;
    else { wh=v*1000; if (wh>=10) printf "%.0f Wh", wh; else if (wh>=1) printf "%.1f Wh", wh; else printf "%.0f mWh", v*1000000; }
  }'
}
fmt_adpe() {  # kgSbeq -> µg / mg / g / kg
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "0"; exit }
    if (v>=1)            printf "%.2f kgSbeq", v;
    else if (v>=0.001)   printf "%.1f gSbeq", v*1000;
    else if (v>=0.000001){ mg=v*1000000; if (mg>=10) printf "%.0f mgSbeq", mg; else printf "%.1f mgSbeq", mg; }
    else                 printf "%.0f µgSbeq", v*1000000000;
  }'
}
fmt_pe() {  # MJ -> J / kJ / MJ
  awk -v v="$1" 'BEGIN{
    if (v=="" || v+0<=0) { print "0"; exit }
    if (v>=1)          printf "%.2f MJ", v;
    else if (v>=0.001) { kj=v*1000; if (kj>=10) printf "%.0f kJ", kj; else printf "%.1f kJ", kj; }
    else               printf "%.0f J", v*1000000;
  }'
}

# Map a metric key to its emoji + formatted cached value.
render_metric() { case "$1" in
  gwp)    printf '🔥 %s' "$(fmt_gwp "$GWP")";;
  wcf)    printf '💧 %s' "$(fmt_wcf "$WCF")";;
  energy) printf '⚡️ %s' "$(fmt_energy "$ENERGY")";;
  adpe)   printf '⛏️ %s' "$(fmt_adpe "$ADPE")";;
  pe)     printf '🛢️ %s' "$(fmt_pe "$PE")";;
esac; }

# Build the eco line from the selected metrics, in order. Metrics with no value
# yet (cache not populated) render as "0" via the formatters — never "…".
SELECTED=()
for key in $ECO_METRICS; do
  case "$key" in
    gwp|wcf|energy|adpe|pe) ;;
    *) continue;;            # ignore unknown keys
  esac
  SELECTED+=("$key")
done
[ "${#SELECTED[@]}" -eq 0 ] && SELECTED=(gwp wcf energy)

# Optional model label prefix (hidden unless ECOLOGITS_MODEL_LABEL is set).
ECO_LINE="$ECO_LABEL"
for key in "${SELECTED[@]}"; do
  piece="$(render_metric "$key")"
  if [ -z "$ECO_LINE" ]; then ECO_LINE="$piece"; else ECO_LINE="$ECO_LINE | $piece"; fi
done

# ---- Render: one line, appended below whatever your status line printed -----
printf '%b\n' "${GRAY}${ECO_LINE}${RESET}"
