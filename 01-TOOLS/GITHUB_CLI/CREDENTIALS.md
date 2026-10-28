# Credentials — GitHub CLI

## Provider documentation

- Official CLI manual: https://cli.github.com/manual/ (checked 2026-10-28).
- Official authentication command: https://cli.github.com/manual/gh_auth_login (checked 2026-10-28).

## Credential storage

The repository owner completes `gh auth login` personally in the terminal/browser. GitHub CLI stores its OAuth credential in macOS Keychain when available. Never display, copy, or commit the token. The chosen GitHub account and granted scopes must be confirmed with `gh auth status` after login.

## Rotation or removal

Run `gh auth logout --hostname github.com` to remove the local CLI authentication, or revoke the CLI authorization from GitHub account settings. Then repeat the interactive login if needed.
