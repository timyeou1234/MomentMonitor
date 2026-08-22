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

## Enforcement

- API argument builder hardcodes GET。
- `ReadOnlyContractTests` checks that mutation verbs cannot appear in generated API commands。
- `Scripts/check_read_only.sh` scans production sources for forbidden command construction and then runs tests。
- UI exposes only refresh, open URL, settings and quit。
- Temporary GitHub response files use a random `0700` directory and `0600` files, then are removed immediately after each command。
