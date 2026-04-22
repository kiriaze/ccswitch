# ccswitch

Lean Claude Code account switcher for macOS. Swaps credentials and restarts Claude in one command.

Works with both the Claude Code CLI and the Claude desktop app.

## Requirements

- macOS
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)

## Install

```bash
# Run from anywhere after cloning
sudo bash ccswitch install
```

Or manually copy to your PATH:

```bash
cp ccswitch ~/.local/bin/ccswitch
chmod +x ~/.local/bin/ccswitch
```

## Usage

```
ccswitch save <name>   # snapshot current account credentials
ccswitch use <name>    # switch to a saved account (kills + restarts Claude)
ccswitch ls            # list saved accounts (* = active)
ccswitch current       # show active account
ccswitch rm <name>     # remove a saved account
```

## Workflow

**First time setup** — do this once per account while logged in:

```bash
# Log in as account A in Claude, then:
ccswitch save personal

# Log out of Claude, log in as account B, then:
ccswitch save work
```

**Switching accounts:**

```bash
ccswitch use work
# Claude desktop quits, credentials swap, Claude relaunches as "work"

ccswitch use personal
# Back to personal account
```

## How it works

Claude Code stores the active session in two files:

| File | What's swapped |
|---|---|
| `~/.claude.json` | `oauthAccount` object |
| `~/Library/Application Support/Claude/config.json` | `oauth:tokenCache` string |

`ccswitch save` extracts and stores both. `ccswitch use` writes them back, kills Claude processes, and relaunches the desktop app.

Account profiles are stored in `~/.claude-accounts/<name>.json` (chmod 600).

## Notes

- The desktop app must quit and relaunch for the switch to take effect — there is no hot-reload
- Claude Code CLI picks up the new credentials immediately after the file swap
- Accounts are stored locally in `~/.claude-accounts/` — no cloud sync, no keychain
