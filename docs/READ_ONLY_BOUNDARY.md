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

Codex capacity 只短暫啟動本機官方 `codex app-server`，並依序送出：

```text
initialize
initialized
account/rateLimits/read
```

每次讀取有 bounded timeout；無回應的 child process 會在短暫 grace period 後停止，
避免一次卡住永久凍結後續唯讀輪詢。超過 3 分鐘的舊 observation 不再標成 Live。

不呼叫 `account/usage/read`、thread/turn API、reset-credit consumption 或通知／購買操作。CLI 無法定位、未登入、逾時或 response 不符合 bounded schema 時只回報 Unavailable。

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

## Optional mobile dashboard output

手機 dashboard 預設關閉，啟用後只綁定 `127.0.0.1`。內建 server 只接受
`GET` 與 `HEAD`，有 8 KiB request、16 connections 與 5 秒 timeout 上限，且只提供：

```text
GET /health
GET /api/v1/snapshot
GET /, /index.html, /app.css, /app.js
```

Host 只允許 loopback 名稱/位址及 Tailscale Serve 的 `.ts.net` 名稱；其他 Host
會被拒絕，避免 DNS rebinding。Response 強制 `no-store`、same-origin CSP/CORP、
`DENY` frame policy、`nosniff` 與 no-referrer，沒有 CORS。網頁沒有外部 asset、
service worker、`localStorage` 或持久化 private snapshot。

Mobile snapshot 是明確 allow-list：repository、時間、health、project progress、
Codex quota remaining percentage/window/reset time、sanitized runtime phase 與各 lane item。它刻意不輸出 controller run ID、PID、
base/head SHA、account identity、credential、prompt、response、finding 或 raw token activity。Issue 標題和工作
狀態本身仍是私人資料；遠端存取只能使用 Tailscale Serve 和適當 ACL，不得使用
Tailscale Funnel、public tunnel 或公開 hosting。

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
- reading prompt、response、finding、JSONL、credential、raw token activity或 private reasoning。
- starting a Codex thread/turn、reading account usage history、consuming a reset credit或發送 account notification；
- binding the mobile dashboard to `0.0.0.0`、LAN interfaces or a public tunnel；
- exposing raw controller identity、process identity or Git SHA through the mobile API。

## Enforcement

- API argument builder hardcodes GET。
- `ReadOnlyContractTests` checks that mutation verbs cannot appear in generated API commands。
- `Scripts/check_read_only.sh` scans production sources for forbidden command construction and then runs tests。
- UI exposes only refresh, open URL, copy a Tailscale Serve command, settings and quit。
- Temporary GitHub response files use a random `0700` directory and `0600` files, then are removed immediately after each command。
- Codex App Server request construction is tested as an exact three-message allow-list；temporary stdio files use the same `0700`/`0600` pattern and are removed immediately。
- `MobileDashboardTests` exercise the real loopback listener, security headers, method allow-list, untrusted Host rejection and sanitized schema；source scans reject public binding, CORS and browser persistence。
