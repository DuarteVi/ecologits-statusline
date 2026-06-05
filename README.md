# EcoLogits impact bar for Claude Code

A [Claude Code](https://claude.com/claude-code) status-line add-on that estimates
the **environmental impact of your session** — energy use (kWh), greenhouse-gas
emissions (kgCO₂eq) and freshwater consumption (L) — from the tokens Claude
generates, using the public [EcoLogits API](https://api.ecologits.ai).

It's a **drop-in component**, not a status line. You keep full ownership of your
own `statusline.sh` and add **one line** that appends the eco bar below yours:

```
your existing status line, unchanged…
🔥 0.21 kgCO₂eq | 💧 3.1 L | ⚡️ 0.4 kWh  ← added by EcoLogits
```

The impact grows live as you use Claude Code. Units auto-scale
(mWh → Wh → kWh energy, mg → g → kg CO₂eq, mL → L water) so the numbers stay
readable from the first token onward. Before the first response the metrics
read `0`. Want the model name shown too? Set
[`ECOLOGITS_MODEL_LABEL`](#other-settings) to get `🤖 claude-opus-4-6 | 🔥 …`.

## Why a snippet?

Many people already have a customized status line. Rather than take it over,
EcoLogits gives you a tiny script — `~/.claude/ecologits-bar.sh` — that reads the
same JSON Claude Code hands your status line and prints **one extra line**. You
call it from your own script, so nothing of yours changes except the two lines
you paste.

## Requirements

- `bash`, [`jq`](https://jqlang.github.io/jq/), `curl`
  - macOS: `brew install jq` (curl is preinstalled)
  - Debian/Ubuntu: `sudo apt-get install -y jq curl`

## Install

```bash
git clone https://github.com/<your-user>/ecologits-statusline.git
cd ecologits-statusline
./install.sh
```

The installer is **non-destructive** — it never edits your `settings.json` or any
`statusline.sh`. It copies `ecologits-bar.sh` and a config file into `~/.claude`,
then prints the snippet to paste.

### Add the bar to your status line

Your `statusline.sh` must capture the JSON Claude Code sends on stdin — the
canonical first line does this:

```bash
input=$(cat)
```

Then, **after your own status line prints**, add these two lines at the bottom:

```bash
# ─── EcoLogits impact bar — https://ecologits.ai ───
printf '%s' "$input" | ~/.claude/ecologits-bar.sh
```

That's it. Start a new session — your status line stays exactly as it was, with
the eco bar added below it (showing `…` until the first response lands).

> The snippet assumes your captured stdin is in a variable named `input`. If you
> named it something else, use that name instead (e.g. `printf '%s' "$STDIN"`).
> If the bar can't see the JSON it prints `🤖 EcoLogits: no input …` so you can
> spot the mismatch.

### No status line yet?

Create `~/.claude/statusline.sh`:

```bash
#!/usr/bin/env bash
input=$(cat)

# (Optional) your own status line goes here, e.g.:
# echo "my prompt"

# ─── EcoLogits impact bar — https://ecologits.ai ───
printf '%s' "$input" | ~/.claude/ecologits-bar.sh
```

Make it executable and point Claude Code at it:

```bash
chmod +x ~/.claude/statusline.sh
```

```json
{
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 2 }
}
```

(Running `./install.sh` prints this same starter when it detects no status line.)

## How it works

- Sums `output_tokens` across the **current session's** transcript (resets each
  session).
- Sends that total to `POST /v1beta/estimations` on the public EcoLogits API and
  shows the **midpoint** of the returned `energy` (kWh), `gwp` (CO₂eq) and `wcf`
  (water) ranges.
- **Never blocks your terminal:** each render prints instantly from a small cache
  in `~/.claude/ecologits-cache/`. A refresh runs in the background **only when
  your token count grows** — idle sessions make zero API calls. If a refresh
  fails (offline, etc.) the last-known value is kept, never blanked.

## Configuration

Edit **`~/.claude/ecologits.config.sh`** — it's sourced on every render. The two
things most people change: the **model** (input) and **which impacts to show**
(output).

```bash
# INPUT — the Claude model to estimate
: "${ECOLOGITS_MODEL:=claude-opus-4-6}"

# OUTPUT — impacts to display, in order (space-separated)
: "${ECOLOGITS_METRICS:=gwp wcf energy}"
```

### Input — model

Set `ECOLOGITS_MODEL` to the model you actually use (default `claude-opus-4-6`).
Valid values come from the public endpoint
[`/v1beta/models/anthropic`](https://api.ecologits.ai/v1beta/models/anthropic):

```
claude-opus-4-6    claude-opus-4-5    claude-opus-4-1    claude-opus-4-0
claude-sonnet-4-6  claude-sonnet-4-5  claude-sonnet-4-0
claude-haiku-4-5
```

### Output — metrics

`ECOLOGITS_METRICS` is a space-separated, ordered list. Default
`gwp wcf energy` renders `🔥 … gCO₂eq | 💧 … mL | ⚡️ … Wh`. Available metrics
([API docs](https://api.ecologits.ai/docs#)):

| key      | emoji | impact                            | unit (auto-scaled) |
| -------- | :---: | --------------------------------- | ------------------ |
| `gwp`    |  🔥   | Greenhouse-gas emissions          | mg/g/kg CO₂eq      |
| `wcf`    |  💧   | Fresh water consumed              | mL/L               |
| `energy` |  ⚡️   | Energy consumed by the request    | mWh/Wh/kWh         |
| `adpe`   |  ⛏️   | Mineral & metal resource depletion| µg/mg/g Sbeq       |
| `pe`     |  🛢️   | Total primary energy consumed     | J/kJ/MJ            |

E.g. `ECOLOGITS_METRICS="energy gwp wcf adpe pe"` shows all five.

### Other settings

| Variable          | Default                                          | Description                                   |
| ----------------- | ------------------------------------------------ | --------------------------------------------- |
| `ECOLOGITS_MODEL_LABEL` | _(empty → hidden)_                         | Text prepended before the metrics. Empty by default, so the line starts at the metrics. Set e.g. `🤖 $ECOLOGITS_MODEL` to show the estimated model; a ` \| ` separator is added automatically |
| `ECOLOGITS_ZONE`  | `WOR`                                            | Electricity-mix zone for the server location — where the data center sits (ISO-3166 alpha-3, e.g. `USA`, `FRA`) |
| `ECOLOGITS_API`   | `https://api.ecologits.ai/v1beta/estimations`    | Estimations endpoint (point to your own deployment if you self-host) |

> Every setting can also be supplied as a real exported environment variable,
> which takes precedence over the config file.

## Caveats

- **Estimates, not measurements.** Figures come from EcoLogits' impact model and
  are shown as range midpoints. See the
  [EcoLogits methodology](https://ecologits.ai/latest/methodology/).
- **`claude-opus-4-6` is a deliberate worst-case ceiling** — it's the highest
  Anthropic model the public API serves. If you actually run Sonnet/Haiku, the
  numbers overstate impact. Set `ECOLOGITS_MODEL` to change this.
- **Electricity zone defaults to `WOR`** (world average). The real data-center
  location isn't published; adjust with `ECOLOGITS_ZONE` if you prefer.
- Only **output tokens** drive the estimate (the API models impact from
  generation). Thinking/reasoning tokens are included, since they're generated.

## Uninstall

```bash
./uninstall.sh          # remove the bar + cache, keep your config
./uninstall.sh --purge  # also remove ecologits.config.sh
```

This deletes `~/.claude/ecologits-bar.sh` and the cache directory, then reminds
you to remove the two pasted lines from your own `statusline.sh` (it won't edit
your script for you).

## Credits

Built on [EcoLogits](https://ecologits.ai) by the
[GenAI Impact](https://genai-impact.org/) collective. This project is an
independent status-line integration and is not affiliated with Anthropic.

## License

MIT — see [LICENSE](LICENSE).
