# Moments state model

| Lane | Source | Exact interpretation |
|---|---|---|
| Ready | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | All direct `moment:depends-on` Issue numbers are closed. Ordering is high, medium, default, then Issue number. |
| Waiting | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | At least one direct dependency is open. |
| Runner queue | Relevant workflow run | Status is `queued`, `waiting`, `pending`, or `requested`. |
| Running | Relevant workflow run | Status is `in_progress`; jobs endpoint supplies the current job/step when available. |
| Running (inferred) | Open Issue + `dev-running` | No matching active run is visible yet. It becomes a warning after ten minutes. |
| PR / Checks | Open automation PR | No matching active Codex/PR Fast run. Latest PR Fast conclusion is shown when available. |
| Blocked | Open Issue + `dev-blocked` | Automation explicitly stopped this Issue. |
| Completed | Merged automation PR + closed Issue | PR has `merged_at`, body/title resolves the originating Issue, and that Issue is closed. |

## Workflow relevance

```text
.github/workflows/codex-scheduler.yml
.github/workflows/codex-task.yml
.github/workflows/security.yml   # PR Fast
```

## Correlation

- Local workflow-dispatch task → Issue: rendered run title ending in the Issue number, with automation branch fallback.
- Local `pull_request_target` review → PR: rendered run title ending in the PR number; the PR then resolves the Issue.
- PR Fast → PR: rendered run title containing `#<PR>`.
- PR → Issue: exact standalone `Closes|Fixes|Resolves #<Issue>` line, with automation title fallback.

## Important non-equivalences

```text
workflow conclusion == success  ≠ Issue completed
Codex run completed             ≠ PR merged
PR Fast success                 ≠ merged state already visible
app/process disappearance       ≠ cancel
```
