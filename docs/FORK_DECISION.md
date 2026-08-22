# Fork decision

## 結論

不建立一個長期追蹤 RepoBar 全部 upstream 的 full fork；建立一個小型、獨立、MIT-attributed derivative。

## 原因

需求只有一個 repository 與一條固定生命週期：

```text
Issue queue
→ GitHub Actions queue
→ Codex local task
→ PR / PR Fast
→ merge + Issue close
```

Full RepoBar fork 會同時帶入與此目標無關的維護面：

- 多 repository 與多帳號狀態；
- GraphQL schema/code generation；
- SQLite cache 與 archive import；
- local repository scanning、worktrees 與 optional sync；
- OAuth/GitHub App/PAT 多路 authentication；
- updater、release tooling、CLI 與 iOS target；
- 大量 generic menu customization。

這些不是 runtime dependency，但都會成為 merge conflict、build dependency、security review 與升級成本。

## 保留的 RepoBar 思路

- menu-bar-first；
- 一眼看到 CI/Issue/PR 壓力；
- row 點擊後回到 GitHub 作為 detailed source of truth；
- polling + local rendering；
- private repository credentials 留在既有 GitHub tooling。

## 本專案的差異

- 只支援一個 configured repository；
- 使用本機既有 `gh` authentication，不新增 OAuth app；
- 只有 REST GET；
- 不持有 GitHub token；
- 不掃描或修改本機 git checkout；
- 不修改 Moment repository；
- 直接理解 Moments 的 `dev-*` labels 與 dependency marker；
- Completed 以 merged automation PR 且 Issue 已關閉為準，而非 workflow conclusion。

## 未來何時才改回 full fork

只有在需要 RepoBar 的多 repo、多帳號、persistent cache 或 release/update infrastructure 時才重新評估。單純增加 notification、menu filter 或更多 Moments workflow 類型，不足以合理化 full fork。
