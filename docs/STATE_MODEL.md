# Moments state model

| Lane | Source | Exact interpretation |
|---|---|---|
| Ready | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | All direct `moment:depends-on` Issue numbers are closed. Ordering matches the scheduler: ascending Issue number. |
| Waiting | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | At least one direct dependency is open. |
| Runner queue | Relevant workflow run | Status is `queued`, `waiting`, `pending`, or `requested`. |
| Running | Relevant workflow run | Status is `in_progress`; jobs endpoint supplies the current job/step when available. |
| Running (local/exact) | Valid `moment.automation-runtime.v1` + live runner PID + matching repository/Issue | Exact controller phase, model role, round, phase duration, and optional PR identity. The local record replaces a duplicate broad workflow/label row. |
| Running (local/fallback) | Open Issue + `dev-running` | Used only when no valid exact telemetry is available. The label remains active and is not reclassified as stale from elapsed time alone. |
| PR / Checks | Open automation PR | No matching active Codex/PR Fast run. Latest PR Fast conclusion is shown when available. |
| Blocked | Open Issue + `dev-blocked` | Automation explicitly stopped this Issue. |
| Completed | Merged automation PR + closed Issue | PR has `merged_at`, body/title resolves the originating Issue, and that Issue is closed. |

## Project progress

`Project progress` 的分母是目前各 lane 能解析到 Issue number 的工作，加上完整歷史中符合 Completed 定義的 Issue number；分子只包含 Completed，兩者都以 Issue number 去重。

這個數字刻意不包含沒有 Issue 關聯的 scheduler run，也不會把 workflow success、open PR 或畫面上受設定截斷的 Completed rows 誤當成完成。它描述 tracked automation scope，不代表未進入 automation lifecycle 的整個產品 roadmap。

## Local runtime phase

`runtime/current.json` 是 optional controller output，不是 automation input。
Known active phases cover workspace preparation, Luna implementation, candidate
commit, PR Fast, Sol deterministic repair, Sol review/repair, Luna verification,
Sol High unblock, branch/PR publication, exact-head verification, merge and Issue
closure. Terminal records preserve the last active phase so failure does not lose
where it happened.

Active record 只有在 runner PID 仍存活時標成 `LIVE`；dead PID 是 `STALE`。
Unknown schema/field/phase、unsafe permission、symlink、oversize或矛盾的
phase/model/role/outcome 都是 `INVALID`。Terminal `completed` 仍須 GitHub 同時證明
merged automation PR + closed originating Issue，否則明示 awaiting confirmation。

## Workflow relevance

目前 trusted controller 在本機執行，只把 bounded phase metadata 寫入本機 Application Support；不發布 step transcript 或 token 資料到 GitHub。下列已知 workflow path 只在最近 100 筆 run 中作為向後相容的補充 context；它們不是 viewer 正常工作的依賴：

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
