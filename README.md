# EcoLogits status line for Claude Code

A [Claude Code](https://claude.com/claude-code) status line that estimates the
**environmental impact of your session** — greenhouse-gas emissions (kgCO₂eq)
and freshwater consumption (L) — from the tokens Claude generates, using the
public [EcoLogits API](https://api.ecologits.ai).

```
[Opus 4.8] 📁 my-project | 🌿 main
🤖 claude-opus-4-6 | 🔥 0.21 kgCO₂eq | 💧 3.1 L
```

The impact grows live as you use Claude Code. Units auto-scale
(mg → g → kg CO₂eq, mL → L water) so the numbers stay readable from the first
token onward.

## How it works

- Sums `output_tokens` across the **current session's** transcript (resets each
  session).
- Sends that total to `POST /v1beta/estimations` on the public EcoLogits API and
  shows the **midpoint** of the returned `gwp` (CO₂eq) and `wcf` (water) ranges.
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

The installer copies the script to `~/.claude/ecologits-statusline.sh` and sets
the `statusLine` entry in `~/.claude/settings.json` (backing up any existing
one). Start a new session — you'll see `🤖 claude-opus-4-6 | …` until the first
response lands, then live numbers.

### Manual install

```bash
cp statusline.sh ~/.claude/ecologits-statusline.sh
chmod +x ~/.claude/ecologits-statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/ecologits-statusline.sh",
    "padding": 2
  }
}
```

> **Note:** Claude Code allows only one status line. Installing this replaces
> your current one. To keep your own layout, copy the `EcoLogits` block from
> `statusline.sh` into your existing script instead.

## Configuration

Set these environment variables (e.g. in your shell profile) to customize:

| Variable          | Default                                          | Description                                   |
| ----------------- | ------------------------------------------------ | --------------------------------------------- |
| `ECOLOGITS_MODEL` | `claude-opus-4-6`                                | Model name sent to the API                    |
| `ECOLOGITS_ZONE`  | `WOR`                                            | Electricity-mix zone (ISO-3166 alpha-3, e.g. `USA`, `FRA`) |
| `ECOLOGITS_API`   | `https://api.ecologits.ai/v1beta/estimations`    | Estimations endpoint (point to your own deployment if you self-host) |

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
rm ~/.claude/ecologits-statusline.sh
rm -rf ~/.claude/ecologits-cache
# then remove the "statusLine" block from ~/.claude/settings.json
```

## Credits

Built on [EcoLogits](https://ecologits.ai) by the
[GenAI Impact](https://genai-impact.org/) collective. This project is an
independent status-line integration and is not affiliated with Anthropic.

## License

MIT — see [LICENSE](LICENSE).
