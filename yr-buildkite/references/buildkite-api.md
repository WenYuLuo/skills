# Buildkite API Notes

Base URL:

```text
https://api.buildkite.com/v2
```

Authentication:

```text
Authorization: Bearer $BUILDKITE_API_TOKEN
```

Key endpoints used by `yr-bk`:

```text
GET  /organizations/{org}/pipelines/{pipeline}
PATCH /organizations/{org}/pipelines/{pipeline}
POST /organizations/{org}/pipelines/{pipeline}/builds
GET  /organizations/{org}/pipelines/{pipeline}/builds/{number}
GET  /organizations/{org}/pipelines/{pipeline}/builds/{number}/jobs/{job_id}/log.txt
GET  /organizations/{org}/pipelines/{pipeline}/builds/{number}/artifacts
```

State handling:

```text
active: creating, scheduled, running, failing, canceling
terminal: passed, failed, canceled, blocked, skipped, not_run
```

`failing` means at least one job has failed while other jobs may still be running. Do not restore temporary pipeline repo or stop watching on `failing`.
