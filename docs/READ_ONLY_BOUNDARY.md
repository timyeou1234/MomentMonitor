# Read-only boundary

## Trust statement

Moment Monitor 是 observer，不是 controller。Viewer 消失、crash、沒有登入或讀不到 GitHub 時，Moments 自動化必須完全不受影響。

## Allowed commands

`GitHubCLIClient` 只能從程式內部組合：

```text
gh auth status --hostname github.com
gh api <known REST endpoint> --method GET
```

所有 API request 都附帶：

```text
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

`gh api` 若帶 field 可能自動切換成 POST，因此本專案不使用 `--field`、`--raw-field` 或 request body，並明確指定 `--method GET`。

## Allowed endpoints

```text
GET /repos/{owner}/{repo}/issues
GET /repos/{owner}/{repo}/pulls
GET /repos/{owner}/{repo}/actions/runs
GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs
```

## Optional local phase input

App 可以唯讀開啟 controller-owned：

```text
~/Library/Application Support/MomentAutomation/runtime/current.json
```

Reader 使用 `O_NOFOLLOW`、regular-file、current-user owner、group/other mode
bits 為零、16 KiB size bound、exact field allow-list、known schema/enum、
timestamp/counter/SHA consistency 與 live PID 檢查。任何不符合都 fail closed；
repository 不相符則視為與目前 viewer 無關。

這份資料只證明本機 controller 回報的執行 phase，不證明 PR、check、merge 或
Issue completion。Viewer 不寫入此檔、不讀 checkout，也不把 telemetry 上傳。

## Forbidden behavior

- 非 GET HTTP method；
- `gh workflow run`；
- `gh run rerun` / `gh run cancel`；
- `gh issue edit/comment/close/reopen`；
- `gh pr merge/close/reopen/edit`；
- label、branch、secret、variable、environment 或 repository setting mutation；
- shelling out to `git`；
- writing files into a Moment checkout；
- uploading observer state back to GitHub。
- writing、renaming、deleting或修復 local controller status；
- reading prompt、response、finding、JSONL、credential或 private reasoning。

## Enforcement

- API argument builder hardcodes GET。
- `ReadOnlyContractTests` checks that mutation verbs cannot appear in generated API commands。
- `Scripts/check_read_only.sh` scans production sources for forbidden command construction and then runs tests。
- UI exposes only refresh, open URL, settings and quit。
- Temporary GitHub response files use a random `0700` directory and `0600` files, then are removed immediately after each command。
