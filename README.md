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
ccswitch save <name>       snapshot current Claude account credentials
ccswitch use <name>        switch to a saved Claude account
ccswitch ls                list saved accounts (* = active)
ccswitch status            list accounts + last switch time
ccswitch rm <name>         remove a saved account

ccswitch codex save <name> snapshot current Codex account
ccswitch codex use <name>  switch to a saved Codex account
ccswitch codex ls          list saved Codex accounts
ccswitch codex rm <name>   remove a saved Codex account
```

## Workflow

**First time setup** — do this once per account while logged in:

```bash
# Log in as account A in Claude, then:
ccswitch save personal

# Log out of Claude, log in as account B, then:
ccswitch save work
```

**Knowing when to switch:** ccswitch has no visibility into token usage or reset times. Before switching, run `/status` inside your active Claude Code session to see how close you are to limits. Switch when you're near the ceiling, not after hitting it.

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
- If a CLI session is actively running, `ccswitch use` will warn before swapping credentials underneath it
- Accounts are stored locally in `~/.claude-accounts/` and `~/.codex-accounts/` — no cloud sync, no keychain

---

## Menu bar app (v2)

A native macOS menu bar app lives in `menubar/`. Requires macOS 13+, no Xcode needed — builds from the command line.

### Install from release

Download `ccswitch.app.zip` from the [latest release](https://github.com/kiriaze/ccswitch/releases/latest), unzip, and drag `ccswitch.app` to `/Applications`.

**First launch:** macOS will block it since it isn't notarized. Right-click `ccswitch.app` → **Open** → **Open** to allow it once. After that it opens normally.

Then add **ccswitch** to **System Settings → General → Login Items** so it launches at startup.

### Build from source

```bash
cd menubar
make install        # builds ccswitch.app and copies to /Applications
```

### Usage

Click the `person.2.circle` icon in the menu bar:

- Accounts are listed with a checkmark on the active one
- Click any account to switch — Claude quits, credentials swap, Claude relaunches automatically
- **Save Current Account…** — saves whoever is currently logged in (prompts for a name)
- **Remove Account…** — removes a saved account

### Updating

Re-run `make install` after pulling new changes. The `.app` in `/Applications` is replaced in-place.

---

## Roadmap

### Considered but unlikely

- **Hotkeys** — unnecessary with the menu bar one click away
- **Plan usage / context window metrics** — no public Anthropic API; scraping the web session would be fragile
