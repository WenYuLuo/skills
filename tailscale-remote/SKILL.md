---
name: tailscale-remote
description: Use when interacting with computers over Tailscale, including discovering nodes, resolving Tailscale IPs or MagicDNS names, configuring SSH key access, copying files, and running remote commands.
---

# tailscale-remote

Use this skill for remote computer interaction over Tailscale. Prefer the bundled `ts-remote` CLI instead of hand-writing `tailscale`, `ssh`, `scp`, or `rsync` commands.

## Setup

This skill is intended to be linked into Codex:

```bash
ln -sfn /path/to/tailscale-remote ~/.codex/skills/tailscale-remote
```

Runtime configuration is optional and lives outside the repo:

```text
~/.config/tailscale-remote/config.json
```

Do not store plaintext SSH passwords. If password login is needed, ask for it only for the current SSH/key setup step and prefer installing an SSH key immediately.

## Common workflows

List visible Tailscale nodes:

```bash
tailscale-remote/scripts/ts-remote nodes
```

Resolve a user-provided target:

```bash
tailscale-remote/scripts/ts-remote resolve 100.94.94.65
tailscale-remote/scripts/ts-remote resolve my-host
```

Check SSH access:

```bash
tailscale-remote/scripts/ts-remote check TARGET --user USER
```

Configure SSH key login:

```bash
tailscale-remote/scripts/ts-remote setup-key TARGET --user USER
```

Run a remote command:

```bash
tailscale-remote/scripts/ts-remote run TARGET --user USER -- uname -a
```

Copy local files to a remote node:

```bash
tailscale-remote/scripts/ts-remote upload TARGET ./local/path ~/remote/path --user USER
```

Copy remote files to local:

```bash
tailscale-remote/scripts/ts-remote download TARGET ~/remote/path ./local/path --user USER
```

Run a read-only command across all online nodes:

```bash
tailscale-remote/scripts/ts-remote run --all --user USER -- hostname
```

## Target resolution

Resolve targets in this order:

1. Explicit aliases from `~/.config/tailscale-remote/config.json`.
2. Exact match against `tailscale status --json` node `HostName`.
3. Exact or prefix match against node `DNSName`.
4. Exact match against node `TailscaleIPs`.
5. Fallback to the original user input.

Prefer MagicDNS names when available; use Tailscale IPs as fallback. Do not hardcode temporary Tailscale IPs such as `100.94.94.65` into the skill.

Example config:

```json
{
  "default_user": "lzc",
  "aliases": {
    "main-pc": "host.tailnet.ts.net"
  }
}
```

## Safety rules

- State the resolved target before running SSH, copy, or setup commands.
- Never store plaintext SSH passwords.
- Prefer SSH keys over password authentication.
- Use `rsync -azP` for file copy when available; fallback to `scp`.
- For destructive commands, show the exact target and command and ask for confirmation.
- Do not run destructive commands across multiple nodes.
- For `--all`, only run commands that are clearly read-only unless the user explicitly confirms the node set and command.
