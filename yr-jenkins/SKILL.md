---
name: yr-jenkins
description: Use when working with YuanRong Jenkins jobs, release pipelines, compile jobs, Jenkins API or consoleText logs, including checking build status, monitoring openyuanrong release jobs, following downstream x86_64/aarch64 jobs, extracting branches and commits used by a build, finding the first actionable failure, or creating heartbeat monitors for Jenkins builds.
---

# YR Jenkins

## Overview

Use Jenkins' JSON API and `consoleText` as the source of truth. Prefer read-only API calls first, then map downstream jobs and extract the first actionable error from raw logs.

Never print or hard-code Jenkins credentials or tokens. Use `JENKINS_TOKEN` when it exists; otherwise the helper reads macOS Keychain service `openyuanrong-jenkins` for account `songminhui`, then falls back to reading the token from stdin. The known username is `songminhui`.

## Helper Script

Use `scripts/jenkins_api.sh` for routine reads. It avoids putting the token in process arguments and can reuse the token from macOS Keychain.
Prefer the helper over ad hoc curl/Python for Jenkins status, job history, console, scans, parameters, triggering parameterized jobs, queue resolution, and OBS link extraction.

```bash
export JENKINS_TOKEN='<token>'  # optional; otherwise the script tries macOS Keychain, then prompts on stdin

# Build status JSON from a full Jenkins build URL.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh status \
  'http://jenkins.openyuanrong.com/job/openyuanrong/view/openeuler/job/openyuarpng_release/53/'

# Pipeline stage and parallel-branch durations.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh stages \
  'http://1.95.91.104/job/openyuanrong/view/openeuler/job/openeuler_compile_x86_64/54/'

# Console text with secret-like environment assignments redacted.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh console \
  'http://jenkins.openyuanrong.com/job/openyuanrong/view/openeuler/job/openeuler_compile_x86_64/54/'

# Extract important log lines.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh scan \
  'http://jenkins.openyuanrong.com/job/openyuanrong/view/openeuler/job/openeuler_compile_x86_64/54/'

# Recent builds from a Jenkins job URL.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh job \
  'http://1.95.91.104/job/openyuanrong/view/yr_pr_check/job/yr-pr-compile/' 30

# Job availability, including whether Jenkins has disabled the job.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh info \
  'http://1.95.91.104/job/openyuanrong/job/openeuler_compile_x86_64/'

# Build parameters as name=value lines.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh params \
  'http://1.95.91.104/job/openyuanrong/view/openeuler/job/openyuarpng_release/53/'

# Trigger a parameterized job. Output includes queue_url.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh trigger \
  'http://1.95.91.104/job/openyuanrong/view/openeuler/job/obs_upload/' \
  build_type=daily build_version=9.9.9 current_time=202607071331

# Resolve a queue item to the build number and URL.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh queue \
  'http://1.95.91.104/queue/item/10247/'

# Cancel a queued item before Jenkins assigns a build number.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh cancel-queue \
  'http://1.95.91.104/queue/item/10247/'

# Stop a running build after Jenkins assigns a build number.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh stop \
  'http://1.95.91.104/job/openyuanrong/view/person/job/peron_compile_release/26/'

# Extract OBS index/tar URLs from an obs_upload build console.
$HOME/.codex/skills/yr-jenkins/scripts/jenkins_api.sh obs-links \
  'http://1.95.91.104/job/openyuanrong/view/openeuler/job/obs_upload/121/'
```

If the helper is not available, use the same pattern manually:

```bash
read -r -s J_TOKEN
auth=$(printf 'songminhui:%s' "$J_TOKEN" | base64 | tr -d '\n')
curl -g -L --compressed -sS -H "Authorization: Basic ${auth}" \
  'http://jenkins.openyuanrong.com/job/openyuanrong/view/openeuler/job/<job>/<build>/api/json?tree=building,result,duration,fullDisplayName,actions[parameters[name,value]]'
```

## Workflow

1. Read job history or build status:
   - For a job that fails before allocating a build number, use `info <job-url>` and check `buildable`; a job can exist but be disabled.
   - For a job URL, use `job <job-url> [count]` to list recent result history before picking representative failures.
   - For a build URL, use `status <build-url>`.
   - `building`
   - `result`
   - parameters such as `build_version`, `current_time`, `ci_pipelines_repo`, `ci_pipelines_branch`, `job_name`
   - For Pipeline wall-clock breakdowns, use `stages <build-url>` and treat parallel branches by their maximum duration rather than summing them.

2. Fetch `consoleText` for the build. Do not rely on the HTML console page.

3. For release jobs, find downstream jobs in `consoleText`:

```text
Scheduling project: openyuanrong >> openeuler_compile_x86_64
Starting building: openyuanrong >> openeuler_compile_x86_64 #54
```

Then query each downstream job directly.

4. For parameterized builds, use the helper:
   - `params <build-url>` to print the parameters.
   - `trigger <job-url> key=value ...` to start a build without hand-written curl.
   - `queue <queue-url-or-id>` to resolve the queued item into a concrete build number.
   - `cancel-queue <queue-url-or-id>` to cancel a pending item through its `cancelQueue` endpoint.
   - `stop <build-url>` to stop a running build through its `stop` endpoint after a build number is assigned.
   - `obs-links <obs-upload-build-url>` to turn upload logs into OBS download URLs.

5. Extract branch and commit evidence from downstream logs:

```text
[INFO] 仓库: https://gitcode.com/...
[INFO] 分支: master
[CMD] git clone --no-recurse-submodules -b master ...
[INFO] 当前 Commit: 25f229dd317f
[INFO] 写入 commit.txt: ...
```

When asked "used which branch/code", report both the configured plan and what the console has actually reached. If later components have not started yet, say that clearly.

6. Extract the first actionable failure:
   - Prefer the earliest `ERROR:`, `FAILED:`, `script returned exit code`, compiler/linker error, missing artifact, or explicit `[ERROR]`.
   - Ignore warnings, progress logs, cache checksum retries, and later cascading errors unless they are the first real failure.
   - Include nearby context and the job/build number.

7. If the build is still running:
   - Summarize the current stage and last completed component.
   - Do not speculate about success.
   - If the user asks to keep monitoring, create a heartbeat automation rather than polling tightly.

8. If the build finished:
   - If `SUCCESS`, report result, commit(s), artifacts, and stop any heartbeat for that build.
   - If failed, map the first actionable error to the relevant repo/file and continue debugging.

## YuanRong Release Notes

For `openyuarpng_release`, the top-level job usually triggers:

- `openeuler_compile_x86_64`
- `openeuler_compile_aarch64`

Typical parameters:

- `build_version`
- `config_file`
- `ci_pipelines_repo`
- `ci_pipelines_branch`
- `ci_os_type`
- downstream `current_time`, used as `build_cache_dir/<current_time>`

For `ci-pipelines` config-driven builds, `configs/config_compile.yaml` is authoritative for planned component repos and branches. Console logs are authoritative for commits actually built.

## Network Access Notes

If `http://jenkins.openyuanrong.com/...` returns an ADM/WAF page such as `非法阻断`, access Jenkins by its public IP instead:

```bash
JENKINS_BASE=http://1.95.91.104
curl --noproxy '*' -g -L --compressed \
  -H "Authorization: Basic ${auth}" \
  "$JENKINS_BASE/job/openyuanrong/view/openeuler/job/openyuarpng_release/api/json"
```

Do not add `Host: jenkins.openyuanrong.com` when using the IP; that can route back through the blocked virtual host path. Jenkins API responses may still contain URLs with the domain, so replace the host with `1.95.91.104` for follow-up API calls if the domain is blocked.

The helper normalizes `jenkins.openyuanrong.com` URLs to `JENKINS_BASE` and uses `--noproxy '*'` by default. Set `JENKINS_BASE` only when the reachable Jenkins address changes.

## Common Pitfalls

- Avoid `tty=true` for Jenkins console scraping; PTY wrapping can inject backspaces and folded lines that make parsing noisy.
- If `JENKINS_TOKEN` is not set, the helper prompts on stdin. For non-interactive runs, set it only in the current shell/session and unset or close the session afterward.
- Do not hand-roll queue polling after `buildWithParameters`; use `queue` so the queued item is tied back to a concrete build number.
- Jenkins may discard a completed queue record before a later lookup. In that case `queue` reports `queue_item_unavailable=true`; use `job <job-url>` and `params <build-url>` to match the intended parameters or cache key to the real build.
- OBS upload logs often contain the durable evidence; run `obs-links` after `obs_upload` succeeds to collect index and tar URLs.

## Heartbeat Monitoring

Use `automation_update` heartbeat for ongoing Jenkins watches. Include:

- release/build URL
- downstream job numbers if known
- expected branch/commit if relevant
- instruction to use Jenkins API and not echo credentials
- stop condition: delete the automation when the build is done or no longer worth watching

Recommended interval: 5 minutes for active YuanRong release/compile jobs; 30-45 minutes for long gates where rapid feedback is not needed.
