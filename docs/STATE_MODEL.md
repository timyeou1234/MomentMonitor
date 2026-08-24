# Moments state model

| Lane | Source | Exact interpretation |
|---|---|---|
| Ready | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | All direct `moment:depends-on` Issue numbers are closed. Ordering matches the scheduler: ascending Issue number. |
| Waiting | Open owner-authored Issue + `dev-ready` or `moment:dev-ready` marker | At least one direct dependency is open. |
| Runner queue | Relevant workflow run | Status is `queued`, `waiting`, `pending`, or `requested`. |
| Running | Relevant workflow run | Status is `in_progress`; jobs endpoint supplies the current job/step when available. |
| Running (local/exact) | Valid `moment.automation-runtime.v1`/`v2`/`v3` + live runner PID + matching repository/Issue | Exact controller phase, model role, round, phase duration, optional PR identity, and v3 controller-active Issue time. The local record replaces a duplicate broad workflow/label row. |
| Running (local/fallback) | Open Issue + `dev-running` | Used only when no valid exact telemetry is available. The label remains active and is not reclassified as stale from elapsed time alone. |
| PR / Checks | Open automation PR | No matching active Codex/PR Fast run. Latest PR Fast conclusion is shown when available. |
| Blocked | Open Issue + `dev-blocked` | Automation explicitly stopped this Issue. |
| Completed | Merged automation PR + closed Issue | PR has `merged_at`, body/title resolves the originating Issue, and that Issue is closed. |

## M1 progress

`M1 progress` 的 scope contract 是 GitHub Issue title 以 `[M1]` 開頭（大小寫不敏感）。分母是完整分頁結果中所有符合這個 marker 的非-PR Issues；分子是其中 GitHub state 為 `closed` 的 Issues。

這個數字刻意不使用 GitHub milestone assignment，因為現有 M1 scope 由 Issue title marker 管理，而 milestone 欄位並未完整套用。它也不依賴 automation lane、workflow、PR 數量或畫面上受設定截斷的 Completed rows。`closed` 包含 GitHub 記錄的所有 closed reasons；這是 repository 的 Issue closure 進度，不宣稱產品或 release 已完成。

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

### Multi-round strategy track

Review 與 PR Fast 的巢狀策略軌道只從已驗證 v1/v2/v3 record 的
`phase`、`round_number`、`total_rounds`、`repair_attempt` 推導。`R1/C1/R2`
分別代表 review 1、correction 1、review 2；PR Fast 使用 `V1/C1/V2`。
已經越過的 checkpoint 只表示該 exchange 已完成，不宣稱 review pass。當前
runner 不再 live 時，當前 checkpoint 顯示 halted；Final Sol High 顯示
`until pass or a terminal boundary`，不換算成有限百分比。

沒有完整 counters、phase 不屬於這些 loop，或 status 無效時不顯示策略軌道。
Viewer 不從 GitHub label、elapsed time 或歷史文字補猜缺失的 round。

## Codex capacity

`Codex capacity` 只接受官方 Codex App Server `account/rateLimits/read` 的 canonical `rateLimits` bucket。畫面以 `100 - usedPercent` 顯示 remaining percentage，並保留 server 提供的 quota window duration 與 reset timestamp；primary 和 secondary window 不會互相相加。

成功 observation 只在 `fetchedAt` 後 3 分鐘內標為 Live。超過門檻、遺失時間或時間明顯位於未來時，Mac 與手機都改顯示 Stale 並移除百分比與 progress bar，避免 App Server 輪詢中斷後把舊值當成目前容量。App Server process 在 request timeout 後先終止、再於 250 ms bounded grace 後強制停止，讓下一次 60 秒 polling 可以恢復。

CLI 不存在、目前 authentication mode 不支援、逾時、欄位缺失或百分比超出 0...100 時會顯示 Unavailable，不沿用舊數值或從本機 token/log 猜測。這份資料不代表帳單餘額，也不授權 viewer 啟動 agent、購買 credits 或消耗 reset credit。

Optional phone dashboard 會把同一份 reconciled state 轉成 versioned、sanitized
的 `schemaVersion: 4` snapshot。它不另外推算 phase 或 completion：精確的 local
phase 仍來自通過驗證的 controller record，merged/closed completion 仍由 GitHub 證明。

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
