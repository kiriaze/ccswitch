# ccswitch

Lean Claude Code account switcher for macOS. Swaps credentials and restarts Claude in one command.

Works with both the Claude Code CLI and the Claude desktop app.

## Requirements

- macOS
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)

## Install

Clone anywhere, install, then delete the repo — the script is self-contained once copied to your PATH.

```bash
git clone https://github.com/kiriaze/ccswitch.git /tmp/ccswitch
sudo bash /tmp/ccswitch/ccswitch install
rm -rf /tmp/ccswitch
```

Or one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/kiriaze/ccswitch/main/ccswitch -o /tmp/ccswitch && sudo install /tmp/ccswitch /usr/local/bin/ccswitch && rm /tmp/ccswitch
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

## Roadmap

### v2 — macOS menu bar app

A native Swift menu bar app (`NSStatusItem`) that replaces the CLI for desktop users:

- Lives in the macOS menu bar, launches at login
- Dropdown shows all saved accounts; clicking one switches immediately and relaunches Claude
- Add/remove accounts from within the app (no terminal required)
- Active account marked, email displayed

The credential swap logic stays identical — the menu bar app is just a GUI shell around the same file operations. Target: ~200 lines of Swift, zero external dependencies.

### Considered but unlikely

- **Hotkeys** — probably unnecessary once the menu bar is one click away
- **Plan usage / context window metrics** — no public Anthropic API for this; scraping the web session would be fragile
