# GitHub CLI (`gh`)

GitHub's official command-line tool. Used to authenticate Git over HTTPS and publish commits, tags, and release assets to `martitc/diktafon-pro` after the owner approves them.

## Install and authenticate

- Official install instructions: https://cli.github.com/manual/installation (checked 2026-10-28).
- This Mac is Apple Silicon. GitHub CLI 2.102.0 was downloaded from the official `cli/cli` release and verified against its published SHA-256 manifest before installation to `~/.local/bin/gh`.
- Authenticate interactively in Terminal with `~/.local/bin/gh auth login --hostname github.com --git-protocol https`. Choose the browser flow; keep any one-time code inside the terminal/browser flow.
- Enable Git credential integration with `~/.local/bin/gh auth setup-git`.
- Check the signed-in account with `~/.local/bin/gh auth status --hostname github.com`.

## Credentials and permissions

`gh` keeps the OAuth credential in macOS Keychain when available. Do not copy it to `.env`, the repository, logs, or chat. Authentication authorizes actions as the account selected during login; only request scopes needed for the owner-approved repo work.

## Connection test

Run `./test_connection.sh`. It performs a read-only `GET /user` and prints the authenticated GitHub login. It does not create or modify repository content.
