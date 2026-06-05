#!/usr/bin/env bash
#
# EcoLogits status line — user configuration.
#
# Edit this file to customize the EcoLogits API call (input) and what the
# status line displays (output). The installer copies it to
# ~/.claude/ecologits.config.sh and the status line sources it on each render.
#
# Each setting uses `: "${VAR:=default}"`, so a real exported environment
# variable (if you set one) takes precedence over the value written here.

# ── INPUT — which Claude model to estimate ─────────────────────────────────
# Impact depends on the model, so pick the one you actually use.
# Valid values come from the public endpoint (friendly aliases):
#     https://api.ecologits.ai/v1beta/models/anthropic
#   claude-opus-4-6    claude-opus-4-5    claude-opus-4-1    claude-opus-4-0
#   claude-sonnet-4-6  claude-sonnet-4-5  claude-sonnet-4-0
#   claude-haiku-4-5
: "${ECOLOGITS_MODEL:=claude-opus-4-6}"

# Electricity-mix zone for the server location (ISO-3166 alpha-3): where the
# data center running the model sits, since the local power mix drives its
# carbon intensity. WOR = world average; e.g. FRA, USA.
: "${ECOLOGITS_ZONE:=WOR}"

# ── OUTPUT — which impacts to display, and in what order ────────────────────
# Space-separated list, rendered left to right. Available metrics:
#
#   key     emoji  meaning                                unit (auto-scaled)
#   ------  -----  -------------------------------------  ------------------
#   gwp      🔥    Greenhouse-gas emissions               mg/g/kg CO₂eq
#   wcf      💧    Fresh water consumed                   mL/L
#   energy   ⚡️    Energy consumed by the request         mWh/Wh/kWh
#   adpe     ⛏️    Mineral & metal resource depletion     µg/mg/g Sbeq
#   pe       🛢️    Total primary energy consumed          J/kJ/MJ
#
# Default shows greenhouse gas, water, and energy:
: "${ECOLOGITS_METRICS:=gwp wcf energy}"

# Optional label shown BEFORE the metrics (e.g. which model is being estimated).
# Empty by default → nothing is shown, the line starts straight at the metrics:
#     🔥 4.2 gCO₂eq | 💧 43 mL | ⚡️ 8.4 Wh
# Set it to any text to prepend it (a " | " separator is added automatically).
# You can interpolate the model with $ECOLOGITS_MODEL, e.g.:
#     : "${ECOLOGITS_MODEL_LABEL:=🤖 $ECOLOGITS_MODEL}"   → 🤖 claude-opus-4-6 | 🔥 …
: "${ECOLOGITS_MODEL_LABEL:=}"

# ── ADVANCED ───────────────────────────────────────────────────────────────
# Override the estimations endpoint (e.g. a self-hosted EcoLogits deployment).
: "${ECOLOGITS_API:=https://api.ecologits.ai/v1beta/estimations}"
