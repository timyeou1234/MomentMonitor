# Moments state model

| Lane | Source | Exact interpretation |
|---|---|---|
| Ready | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | All direct `moment:depends-on` Issue numbers are closed. Ordering matches the scheduler: ascending Issue number. |
| Waiting | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | At least one direct dependency is open. |
| Runner queue | Relevant workflow run | Status is `queued`, `waiting`, `pending`, or `requested`. |
| Running | Relevant workflow run | Status is `in_progress`; jobs endpoint supplies the current job/step when available. |
| Running (local/inferred) | Open Issue + `dev-running` | Local runner internals are not published to GitHub. The label remains the bounded source of truth and is not reclassified as stale from elapsed time alone. |
| PR / Checks | Open automation PR | No matching active Codex/PR Fast run. Latest PR Fast conclusion is shown when available. |
| Blocked | Open Issue + `dev-blocked` | Automation explicitly stopped this Issue. |
| Completed | Merged automation PR + closed Issue | PR has `merged_at`, body/title resolves the originating Issue, and that Issue is closed. |

## Workflow relevance

目前 trusted controller 在本機執行，不會把內部 step 或 token 資料發布到 GitHub。下列已知 workflow path 只在最近 100 筆 run 中作為向後相容的補充 context；它們不是 viewer 正常工作的依賴：

```text
.github/workflows/codex-scheduler.yml
.github/workflows/codex-task.yml
.github/workflows/security.yml   # PR Fast
```

## Correlation

- Local workflow-dispatch task → Issue: rendered run title ending in the Issue number, with automation branch fallback.
- Local `pull_request_target` review → PR: REST `pull_requests` relation first, rendered run title fallback; the PR then resolves the Issue.
- PR Fast → PR: REST `pull_requests` relation first, rendered run title fallback.
- PR → Issue: exact standalone `Closes|Fixes|Resolves #<Issue>` line, with automation title fallback.

## Important non-equivalences

```text
workflow conclusion == success  ≠ Issue completed
Codex run completed             ≠ PR merged
PR Fast success                 ≠ merged state already visible
app/process disappearance       ≠ cancel
```
