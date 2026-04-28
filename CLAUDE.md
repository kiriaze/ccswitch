# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single bash script (`ccswitch`) that swaps Claude Code OAuth credentials between saved accounts on macOS. No build step, no dependencies beyond `jq`.

## Running / testing

```bash
# Run directly without installing
bash ccswitch <command>

# Test save/ls/rm cycle without touching live Claude processes
bash ccswitch save test-account
bash ccswitch ls
bash ccswitch rm test-account

# Install to PATH
sudo bash ccswitch install   # copies to /usr/local/bin/ccswitch
```

There are no automated tests. Manual testing is the verification path (see README.md).

## Menu bar app (menubar/)

```bash
cd menubar && make build    # compile only
cd menubar && make install  # build + copy to /Applications
cd menubar && make clean    # remove build artifacts
```

Requires macOS 13+. No Xcode needed — `xcrun swiftc` only.

### Architecture

Four files in `menubar/Sources/`:
- `main.swift` — entry point, sets `.accessory` activation policy (no Dock icon)
- `AppDelegate.swift` — `NSStatusItem` setup, menu building, action handlers
- `AccountManager.swift` — all file I/O: save/apply/remove accounts, reads `~/.claude-accounts/*.json`
- `ProcessManager.swift` — quits Claude via `NSRunningApplication.terminate()`, kills CLI via `pkill`, relaunches via `NSWorkspace.openApplication`

Claude desktop bundle ID: `com.anthropic.claudefordesktop`.

## CLI script architecture

Everything lives in `ccswitch` — one file, one case-dispatch at the bottom routing to `cmd_*` functions.

**Credential files touched on macOS:**

| File | Key swapped |
|---|---|
| `~/.claude.json` | `.oauthAccount` (JSON object) |
| `~/Library/Application Support/Claude/config.json` | `.["oauth:tokenCache"]` (opaque string) |
| `~/.codex/auth.json` | entire file (Codex only) |

**Account storage:** `~/.claude-accounts/<name>.json` and `~/.codex-accounts/<name>.json` (chmod 600). `.current` and `.switched_at` track the active account and last switch time.

**Switch sequence in `cmd_use`:** warn if active CLI session detected → quit Claude via AppleScript → `pkill -f` CLI processes (broader than `-x` to catch node-spawned claude) → `jq`-merge both credential files → record timestamp → optionally relaunch via `open -a "Claude"`.

**Codex:** `ccswitch codex save/use/ls/rm` — wraps the full `~/.codex/auth.json` under an `auth` key in `~/.codex-accounts/<name>.json`. On `use`, extracts `.auth` back to `~/.codex/auth.json`.

**Important:** `~/.claude.json` is at the home root — not inside `~/.claude/`. Most other account-switcher repos get this wrong and target `~/.claude/.claude.json`.
