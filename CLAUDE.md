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

| Location | What's stored | Who uses it |
|---|---|---|
| `~/.claude.json` `.oauthAccount` | Account metadata (email, UUID, billing plan) | CLI display only — NOT auth |
| `~/Library/Application Support/Claude/config.json` `["oauth:tokenCache"]` | Chromium-encrypted OAuth tokens (`v10...` prefix) | Claude desktop app |
| Keychain `"Claude Code-credentials"` | Raw JSON `{claudeAiOauth: {accessToken, refreshToken, ...}}` | Claude Code CLI — the actual Bearer token for API calls and billing |
| `~/.codex/auth.json` | Codex CLI auth | Codex only |

**The Keychain entry is the billing-critical piece.** The `oauthAccount` in `~/.claude.json` is purely display metadata — the CLI reads the Keychain to get the actual access token it sends with every API request. Not swapping the Keychain is why earlier versions of ccswitch billed the wrong account.

**Account storage:** `~/.claude-accounts/<name>.json` and `~/.codex-accounts/<name>.json` (chmod 600). `.current` and `.switched_at` track the active account and last switch time.

Account profile format: `{name, email, oauthAccount, tokenCache, keychainCredentials}`. The `keychainCredentials` field was added in v1.2.0.

**Switch sequence in `cmd_use`:** warn if active CLI session detected → quit Claude via AppleScript → `pkill -f` CLI processes (broader than `-x` to catch node-spawned claude) → `jq`-merge credential files → `security add-generic-password -U` to update Keychain → record timestamp → optionally relaunch via `open -a "Claude"`.

**Codex:** `ccswitch codex save/use/ls/rm` — wraps the full `~/.codex/auth.json` under an `auth` key in `~/.codex-accounts/<name>.json`. On `use`, extracts `.auth` back to `~/.codex/auth.json`.

**Important:** `~/.claude.json` is at the home root — not inside `~/.claude/`. Most other account-switcher repos get this wrong and target `~/.claude/.claude.json`.
