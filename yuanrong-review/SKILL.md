---
name: yuanrong-review
description: Review openYuanrong GitCode PRs across multiple repos using the local yuanrong-review tool.
---

# yuanrong-review

Use this skill when the user wants to inspect, list, or review openYuanrong pull requests on GitCode.

## What this skill provides

- Repository alias mapping for openYuanrong repos
- A local Python CLI under `src/cli.py`
- Review workflows for listing PRs, showing PR details, and drafting or submitting review comments

## Prerequisites

- Run `install.sh` once, or set `YUANRONG_PAT`.
- GitHub only carries `config/config.yaml.template`; real configs are `config/config.yaml.local` and `~/.config/yuanrong-review/config.yaml`.

## Usage in Codex

Run the local CLI from this directory or by absolute path.

Examples:

```bash
python3 yuanrong-review/src/cli.py list frontend --limit 5
python3 yuanrong-review/src/cli.py show yuanrong/448
python3 yuanrong-review/src/cli.py review fs/23 --style normal --dry-run
```

## Notes

- Prefer `--dry-run` first when the user asks for a review draft.
- Do not submit review comments externally unless the user explicitly asks.
- Repository aliases and config details are defined in `skill.yaml` and `README.md`.
