# YuanRong Skills

Portable local skills for openYuanRong development, Buildkite CI, and GitCode PR review.

## Included Skills

- `yr-dev` — openYuanRong repository map, GitCode helpers, commit/MR workflow, build order, install/deploy notes, and local asset hints.
- `yr-buildkite` — Buildkite status/log/artifact tooling, Rust FunctionSystem E2E trigger, compile image workflow, SWR/image checks, C++ baseline, and A/B ST validation references.
- `yuanrong-review` — GitCode PR list/show/review helper across openYuanRong repos.

## Configuration Model

Tracked files are templates only:

- `yr-dev/config/gitcode.env.example`
- `yr-buildkite/config/config.env.example`
- `yuanrong-review/config/config.yaml.template`

Init scripts generate ignored local migration files under each skill's `config/` directory and runtime configs under `~/.config/...`.

```bash
yr-dev/scripts/init-config.sh
yr-buildkite/install.sh
yr-bk init
yuanrong-review/install.sh
```

Never commit real GitCode, Buildkite, SWR, kubeconfig, or WireGuard secrets. To migrate to another private machine, copy the ignored `config/*.local` files or the corresponding `~/.config/...` files out of band.

## Install Shape

For Codex, copy or symlink these three skill directories into `~/.codex/skills/`.

```bash
mkdir -p ~/.codex/skills
cp -a yr-dev yr-buildkite yuanrong-review ~/.codex/skills/
```

`yr-buildkite/install.sh` also installs the `yr-bk` command into `~/.local/bin`.
