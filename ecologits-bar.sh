#!/usr/bin/env bash
#
# EcoLogits impact bar for Claude Code  (drop-in component)
#
# This prints ONE line estimating the environmental impact — energy, greenhouse
# gas, freshwater — of the current session, via the public EcoLogits API. It
# estimates EACH Claude HTTP request separately (using that request's own model
# and generated tokens) and displays the SUM across the current transcript. It
# is meant to be called from inside YOUR OWN statusline.sh,
# which keeps full ownership of its output. Add this after your line prints:
#
#     printf '%s' "$input" | ~/.claude/ecologits-bar.sh
#
# where $input holds the JSON Claude Code sent on stdin (the canonical
# `input=$(cat)` at the top of a statusline script). The bar reads that JSON on
# its own stdin and appends its line below yours.
#
# Repo: https://github.com/DuarteVi/ecologits-statusline
# Powered by EcoLogits — https://ecologits.ai  •  https://api.ecologits.ai
#
# Configuration: edit ~/.claude/ecologits.config.sh (sourced below). Each value
# can also be overridden by an exported environment variable of the same name:
#   ECOLOGITS_MODEL     model sent to the API, or "auto" to track the session's
#                       current model   (default: auto)
#   ECOLOGITS_ZONE      electricity-mix zone for the server location (default: WOR)
#   ECOLOGITS_METRICS   impacts to display      (default: "gwp wcf energy")
#                       add "model" to show the estimated model in the bar
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
ECO_MODEL="${ECOLOGITS_MODEL:-auto}"
ECO_ZONE="${ECOLOGITS_ZONE:-WOR}"

# ---- Per-request model resolution ------------------------------------------
# Every Claude HTTP request is estimated against the model that actually
# generated it (the per-request `.message.model` in the transcript), resolved
# offline to an API-accepted alias. The family fallback keeps an unknown id in
# the right ballpark (a brand-new opus estimates as the latest known opus, never
# as a haiku). When ECOLOGITS_MODEL is a specific id (not "auto") it PINS every
# request to that model instead.
#
#   KNOWN_SET     model ids the EcoLogits API accepts (alias forms; dated and
#                 [1m] variants normalize down to these). Update when the API at
#                 https://api.ecologits.ai/v1beta/models/anthropic gains models.
#   FAMILY_LATEST newest known id per family, used when an id isn't in KNOWN_SET.
ECO_KNOWN_SET="claude-opus-4-8 claude-opus-4-7 claude-opus-4-6 claude-opus-4-5 claude-opus-4-1 claude-opus-4-0 claude-sonnet-4-6 claude-sonnet-4-5 claude-sonnet-4-0 claude-haiku-4-5"
eco_family_latest() { case "$1" in
  opus)   echo "claude-opus-4-8";;
  sonnet) echo "claude-sonnet-4-6";;
  haiku)  echo "claude-haiku-4-5";;
esac; }

# Resolve a raw model id ("claude-opus-4-8[1m]", "Claude-Sonnet-4-6-20250101",
# …) to an API alias. Unrecognizable ids fall back to the configured default.
eco_resolve_model() {
  # Normalize: lowercase, strip a trailing [..] context-window variant (e.g.
  # "[1m]") and a trailing -YYYYMMDD date, leaving the API alias form.
  norm=$(printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/\[[^]]*\]$//; s/-[0-9]{8}$//')
  for m in $ECO_KNOWN_SET; do
    [ "$m" = "$norm" ] && { echo "$m"; return; }
  done
  case "$norm" in
    *opus*)   eco_family_latest opus;;
    *sonnet*) eco_family_latest sonnet;;
    *haiku*)  eco_family_latest haiku;;
    *)        eco_family_latest opus;; # Default
  esac
}

# "auto" (default) → resolve each request's own model; otherwise pin to ECO_MODEL.
ECO_PIN=""
[ "$ECO_MODEL" != "auto" ] && ECO_PIN="$ECO_MODEL"

ECO_METRICS="${ECOLOGITS_METRICS:-gwp wcf energy}"
ECO_DIR="$HOME/.claude/ecologits-cache"
# Global per-request memo. One file per (requestId, model, zone), holding the
# midpoint impacts "<gwp_kg> <wcf_L> <energy_kWh> <adpe_kg> <pe_MJ>". A request's
# impact is immutable, so this is a pure cache; changing the pinned model or zone
# simply points at (and back-fills) a different file.
ECO_REQ_DIR="$ECO_DIR/req"
ECO_LOCK="$ECO_DIR/$SESSION.inflight"
mkdir -p "$ECO_REQ_DIR" 2>/dev/null
# Drop the previous design's per-session aggregate cache if it lingers.
rm -f "$ECO_DIR/$SESSION.json" 2>/dev/null

# ---- Enumerate this session's Claude requests ------------------------------
# One row per request (deduped by requestId — the transcript writes several
# lines per message, all sharing the same immutable requestId). Rows stay in
# chronological order, so the LAST row is the most recent request. Subagent
# (sidechain) requests are included; they consume real energy.
#   row = "<requestId>\t<model>\t<output_tokens>\t<durationMs|null>"
REQ_ROWS=""
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
  REQ_ROWS=$(jq -rc '
    select(.type=="assistant"
           and (.requestId // "") != ""
           and (.message.usage.output_tokens // 0) > 0)
    | [.requestId, (.message.model // ""), (.message.usage.output_tokens), (.durationMs // "null")]
    | @tsv' < "$TRANSCRIPT" 2>/dev/null | awk -F'\t' '!seen[$1]++')
fi

# ---- Sum cached impacts; collect the requests still needing estimation ------
GWP=0; WCF=0; ENERGY=0; ADPE=0; PE=0
LAST_MODEL=""
PENDING=()          # "<file>|<model>|<tokens>|<latency>" for the backfill job
SUM_FILES=()        # cache files present, to sum
if [ -n "$REQ_ROWS" ]; then
  while IFS=$'\t' read -r reqid rawmodel tokens durms; do
    [ -z "$reqid" ] && continue
    if [ -n "$ECO_PIN" ]; then model="$ECO_PIN"; else model=$(eco_resolve_model "$rawmodel"); fi
    LAST_MODEL="$model"
    # durationMs → request_latency (seconds); omit when absent.
    latency="null"
    [ "$durms" != "null" ] && [ -n "$durms" ] && latency=$(awk -v d="$durms" 'BEGIN{printf "%.3f", d/1000}')
    file="$ECO_REQ_DIR/${reqid}__${model}__${ECO_ZONE}"
    if [ -s "$file" ]; then
      SUM_FILES+=("$file")
    else
      PENDING+=("$file|$model|$tokens|$latency")
    fi
  done <<< "$REQ_ROWS"
fi

# Sum the five metrics across every cached request in one awk pass.
if [ "${#SUM_FILES[@]}" -gt 0 ]; then
  read -r GWP WCF ENERGY ADPE PE < <(
    cat "${SUM_FILES[@]}" 2>/dev/null | awk '
      { g+=$1; w+=$2; e+=$3; a+=$4; p+=$5 }
      END { printf "%.12g %.12g %.12g %.12g %.12g", g, w, e, a, p }')
fi

# ---- Monotonic per-session accumulator -------------------------------------
# The displayed total must never go DOWN within one discussion. The transcript
# is append-only (so requests never disappear) and each request's estimate is
# immutable, so the sum is already monotonic in practice — this is a belt-and-
# suspenders floor that also survives the 30-day cache prune deleting a file
# still referenced by a long, resumed session, or a mid-session model/zone
# change pointing at a cheaper estimate.
#
# Keyed on session_id: `/clear` starts a NEW session_id → a fresh floor (resets
# to ~0); `/compact` keeps the SAME session_id → the floor persists and keeps
# climbing. Confirmed against the Claude Code docs.
ECO_ACC="$ECO_DIR/$SESSION.acc"
if [ -s "$ECO_ACC" ]; then
  read -r AGWP AWCF AENERGY AADPE APE < "$ECO_ACC" 2>/dev/null
  read -r GWP WCF ENERGY ADPE PE < <(awk \
    -v g="$GWP" -v w="$WCF" -v e="$ENERGY" -v a="$ADPE" -v p="$PE" \
    -v ag="${AGWP:-0}" -v aw="${AWCF:-0}" -v ae="${AENERGY:-0}" -v aa="${AADPE:-0}" -v ap="${APE:-0}" \
    'BEGIN { printf "%.12g %.12g %.12g %.12g %.12g",
      (g>ag?g:ag), (w>aw?w:aw), (e>ae?e:ae), (a>aa?a:aa), (p>ap?p:ap) }')
fi
# Persist the (possibly raised) floor. Atomic write so a concurrent render never
# reads a half-written file.
printf '%s %s %s %s %s\n' "$GWP" "$WCF" "$ENERGY" "$ADPE" "$PE" > "$ECO_ACC.tmp" 2>/dev/null \
  && mv "$ECO_ACC.tmp" "$ECO_ACC" 2>/dev/null

# ---- Background backfill for the requests not yet estimated -----------------
# Non-blocking: the line shows the sum of what is cached now (with a trailing "…"
# while estimation is in flight) and converges over the next few renders. A
# per-session lock keyed to the pending set avoids double-spawning; a stale lock
# (job died >2min ago) is ignored so backfill can never wedge.
ECO_DISPLAY_PENDING=0
if [ "${#PENDING[@]}" -gt 0 ]; then
  ECO_DISPLAY_PENDING=1
  SIG=$(printf '%s\n' "${PENDING[@]}" | sort | cksum | awk '{print $1}')
  INFLIGHT=""
  [ -f "$ECO_LOCK" ] && INFLIGHT=$(cat "$ECO_LOCK" 2>/dev/null)
  STALE=0
  [ -n "$(find "$ECO_LOCK" -mmin +2 2>/dev/null)" ] && STALE=1
  if [ "$INFLIGHT" != "$SIG" ] || [ "$STALE" -eq 1 ]; then
    (
      echo "$SIG" > "$ECO_LOCK"
      n=0
      for task in "${PENDING[@]}"; do
        file="${task%%|*}"; rest="${task#*|}"
        model="${rest%%|*}"; rest="${rest#*|}"
        tokens="${rest%%|*}"; latency="${rest##*|}"
        (
          body="{\"provider\":\"anthropic\",\"model_name\":\"$model\",\"output_token_count\":$tokens,\"electricity_mix_zone\":\"$ECO_ZONE\""
          [ "$latency" != "null" ] && body="$body,\"request_latency\":$latency"
          body="$body}"
          RESP=$(curl -s --max-time 8 -X POST "$ECO_API" \
            -H "Content-Type: application/json" -d "$body")
          LINE=$(echo "$RESP" | jq -r '
            def mid(x): (x.min + x.max) / 2;
            if .impacts.gwp.value then
              "\(mid(.impacts.gwp.value)) \(mid(.impacts.wcf.value)) \(mid(.impacts.energy.value)) \(mid(.impacts.adpe.value)) \(mid(.impacts.pe.value))"
            else empty end' 2>/dev/null)
          # Only write on a valid response, so an offline request stays pending
          # and retries on a later render rather than caching a blank.
          [ -n "$LINE" ] && { echo "$LINE" > "$file.tmp" && mv "$file.tmp" "$file"; }
        ) &
        n=$((n + 1))
        # Bound concurrency to 4 (portable: barrier every 4 launches).
        [ $((n % 4)) -eq 0 ] && wait
      done
      wait
      # Opportunistic housekeeping: forget per-request entries and stale session
      # accumulators older than 30 days.
      find "$ECO_REQ_DIR" -type f -mtime +30 -delete 2>/dev/null
      find "$ECO_DIR" -maxdepth 1 -name '*.acc' -mtime +30 -delete 2>/dev/null
      rm -f "$ECO_LOCK"
    ) >/dev/null 2>&1 &
  fi
fi

# Resolved id shown by the "model" metric: the most recent request's model (or
# the pin). The "claude-" prefix is dropped for brevity at render time.
ECO_MODEL="${ECO_PIN:-${LAST_MODEL:-claude-opus-4-8}}"

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
  model)  printf '🤖 %s' "${ECO_MODEL#claude-}";;
esac; }

# Build the eco line from the selected metrics, in order. Metrics with no value
# yet (cache not populated) render as "0" via the formatters — never "…".
SELECTED=()
for key in $ECO_METRICS; do
  case "$key" in
    gwp|wcf|energy|adpe|pe|model) ;;
    *) continue;;            # ignore unknown keys
  esac
  SELECTED+=("$key")
done
[ "${#SELECTED[@]}" -eq 0 ] && SELECTED=(gwp wcf energy)

ECO_LINE=""
for key in "${SELECTED[@]}"; do
  piece="$(render_metric "$key")"
  if [ -z "$ECO_LINE" ]; then ECO_LINE="$piece"; else ECO_LINE="$ECO_LINE | $piece"; fi
done

# While some requests are still being estimated in the background, the sum is
# partial — flag it with a trailing "…" so it isn't mistaken for the final total.
[ "$ECO_DISPLAY_PENDING" -eq 1 ] && ECO_LINE="$ECO_LINE …"

# ---- Render: one line, appended below whatever your status line printed -----
printf '%b\n' "${GRAY}${ECO_LINE}${RESET}"
