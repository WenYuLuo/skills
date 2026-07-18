---
name: yuanrong-toolkit
description: Route openYuanRong development, CI, review, deployment, smoke-test, architecture-diagram, and Tailscale tasks to the specialized skills maintained together in this repository.
---

# YuanRong Toolkit

This repository is a toolkit of focused skills. Select the best matching child skill below, then
read and follow that child's `SKILL.md`. Resolve all relative paths from the child skill directory.

| Task | Child skill |
|---|---|
| General openYuanRong development, builds, commits, and GitCode MR workflow | `yr-dev/SKILL.md` |
| Buildkite CI, logs, artifacts, and compile images | `yr-buildkite/SKILL.md` |
| Jenkins jobs, release pipelines, build status, and console logs | `yr-jenkins/SKILL.md` |
| GitCode pull-request review | `yuanrong-review/SKILL.md` |
| Local reusable three-VM process-mode cluster | `yr-local-3vm/SKILL.md` |
| Remote process-mode actor smoke tests | `yr-process-smoke/SKILL.md` |
| Dedicated ECS cluster creation or smoke tests | `building-yr-smoke-ecs/SKILL.md` or `yr-dedicated-cluster-smoke/SKILL.md` |
| Local single-container AIO SDK/FaaS/sandbox validation | `yuanrong-aio/SKILL.md` |
| Local multi-node AIO actor smoke | `yr-smoke-aio/SKILL.md` |
| Editable architecture PowerPoint diagrams | `editable-arch-ppt/SKILL.md` |
| Remote access over Tailscale | `tailscale-remote/SKILL.md` |

Do not load every child skill. Read only the most relevant one first, and add another only when the
task crosses a responsibility boundary. Child-skill instructions take precedence over this routing
table for their specialized workflow.
