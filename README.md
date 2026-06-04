# EcoLogits status line for Claude Code

A [Claude Code](https://claude.com/claude-code) status line add-on that estimates
the **environmental impact of your session** — energy use (kWh), greenhouse-gas
emissions (kgCO₂eq) and freshwater consumption (L) — from the tokens Claude
generates, using the public [EcoLogits API](https://api.ecologits.ai).

It's **additive**: it keeps your existing status line and adds one line below it.

```
your existing status line, unchanged…
🤖 claude-opus-4-6 | ⚡ 0.4 kWh | 🔥 0.21 kgCO₂eq | 💧 3.1 L   ← added by EcoLogits
```

The impact grows live as you use Claude Code. Units auto-scale
(mWh → Wh → kWh energy, mg → g → kg CO₂eq, mL → L water) so the numbers stay
readable from the first token onward.

## How it works

- **Wraps, doesn't replace.** Claude Code allows only one status line, so the
  installer saves your current `statusLine.command` to `~/.claude/ecologits-base.cmd`
  and points Claude Code at the EcoLogits wrapper. On each render the wrapper runs
  your original status line (same JSON on stdin), prints it unchanged, then adds
  the eco line below. If you had no status line, the eco line shows on its own.
- Sums `output_tokens` across the **current session's** transcript (resets each
  session).
- Sends that total to `POST /v1beta/estimations` on the public EcoLogits API and
  shows the **midpoint** of the returned `energy` (kWh), `gwp` (CO₂eq) and `wcf`
  (water) ranges.
- **Never blocks your terminal:** each render prints instantly from a small
  cache in `~/.claude/ecologits-cache/`. A refresh runs in the background **only
  when your token count grows** — idle sessions make zero API calls. If a
  refresh fails (offline, etc.) the last-known value is kept, never blanked.

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

The installer copies the wrapper to `~/.claude/ecologits-statusline.sh`, saves
your current status line command to `~/.claude/ecologits-base.cmd`, and points
the `statusLine` entry in `~/.claude/settings.json` at the wrapper (backing up
the file first). Start a new session — your existing status line stays, with
`🤖 claude-opus-4-6 | …` added below until the first response lands.

Re-running the installer is safe: it detects it's already installed and won't
double-wrap.

### Manual install

```bash
cp statusline.sh ~/.claude/ecologits-statusline.sh
chmod +x ~/.claude/ecologits-statusline.sh
# Save your existing status line command so the wrapper can run it (skip if none):
jq -r '.statusLine.command' ~/.claude/settings.json > ~/.claude/ecologits-base.cmd
```

Then point `statusLine` at the wrapper in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/ecologits-statusline.sh",
    "padding": 2
  }
}
```

> **Note:** Only `type: "command"` base status lines can be wrapped. If you'd
> rather not wrap, set `ECOLOGITS_BASE_CMD` to your base command, or just call
> the `EcoLogits` block from your own script.

## Configuration

Set these environment variables (e.g. in your shell profile) to customize:

| Variable          | Default                                          | Description                                   |
| ----------------- | ------------------------------------------------ | --------------------------------------------- |
| `ECOLOGITS_MODEL` | `claude-opus-4-6`                                | Model name sent to the API                    |
| `ECOLOGITS_ZONE`  | `WOR`                                            | Electricity-mix zone (ISO-3166 alpha-3, e.g. `USA`, `FRA`) |
| `ECOLOGITS_API`   | `https://api.ecologits.ai/v1beta/estimations`    | Estimations endpoint (point to your own deployment if you self-host) |
| `ECOLOGITS_BASE_CMD` | _(contents of `~/.claude/ecologits-base.cmd`)_ | Base status-line command to run before the eco line; overrides the saved file |

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

Restore your original status line, then remove the files:

```bash
# Put your saved base command back as the status line (if you had one):
BASE=$(cat ~/.claude/ecologits-base.cmd 2>/dev/null)
if [ -n "$BASE" ]; then
  jq --arg c "$BASE" '.statusLine = {type:"command", command:$c, padding:2}' \
     ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
else
  jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
fi
rm -f ~/.claude/ecologits-statusline.sh ~/.claude/ecologits-base.cmd
rm -rf ~/.claude/ecologits-cache
```

## Credits

Built on [EcoLogits](https://ecologits.ai) by the
[GenAI Impact](https://genai-impact.org/) collective. This project is an
independent status-line integration and is not affiliated with Anthropic.

## License

MIT — see [LICENSE](LICENSE).
