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

## Optional loopback development diagnosis

Development observer 的 classification 與 recommendation 完全由 app 內 deterministic
rules 決定。若 Settings 開啟 Local Qwen summary，App 只允許：

```text
POST http://127.0.0.1:11434/api/chat
```

等價的 `localhost`／`::1` endpoint 只供測試與明確 local configuration；HTTPS、LAN、
credential-bearing URL、query、fragment 與其他 API path 都被拒絕。Request 強制
`stream=false`、`think=false`、`keep_alive=0s`、bounded context/output；response 有
64 KiB 外層與 2 KiB model JSON 上限。

模型輸入是獨立 allow-list：repository identity、runtime availability/phase/outcome/model/role、
bounded round counters，以及最多 64 個 Issue/PR number＋closed presentation state/severity。
不包含 Issue/PR title、body、comment、URL、timestamp、raw detail、log、activity text、command、
path、prompt、response、credential、Git SHA 或 checkpoint。模型必須原樣回傳 deterministic
classification/recommendation，只能提供一行 bounded summary；不一致或多餘欄位會退回
rules-only。相同 observation fingerprint 不重複 inference，失敗後最多每五分鐘重試。

這個 localhost POST 是唯讀 inference，不是 GitHub/controller mutation。它不能啟動 Codex、
dispatch/retry automation、寫入 checkpoint，或成為 controller input。

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

以及 optional Ox audit producer-owned：

```text
~/Library/Application Support/MomentAutomation/runtime/ox-current.json
```

Reader 使用 `O_NOFOLLOW`、regular-file、current-user owner、group/other mode
bits 為零、16 KiB size bound、exact field allow-list、known schema/enum、
timestamp/counter/SHA consistency 與 live PID 檢查。任何不符合都 fail closed；
repository 不相符則視為與目前 viewer 無關。

Reader 同時接受 strict v1 phase、strict v2 phase＋activity，以及 strict v3
phase＋activity＋Issue duration record。Activity
只包含 Exec／App Server 來源、allow-listed kind/state/action、時間、計數與最多六筆
recent event；不包含來源事件文字。這份資料只證明本機 controller 回報的執行
phase 與最近觀察到的泛化活動，不證明 PR、check、merge 或 Issue completion。
Issue duration 只包含 controller 在相鄰、單調 runtime publication 之間觀察到的
active wall-clock milliseconds；不使用 GitHub Issue age、token 或推估值，dead-run
空窗不累計，最多保留 192 個最近觀察的 Issue。
Viewer 不寫入此檔、不讀 checkout，也不把 telemetry 上傳。

Ox reader 另以 `O_NOFOLLOW`、regular-file、current-user owner、mode 0600、4 KiB
上限與 exact-field schema 驗證 `ox-current.json`。它只接受模型顯示身分、
availability state、目前 Issue、完成／總數、最後 HTTP 狀態、更新與下次重試時間；
不接受 token、prompt、response、classification finding、route credential、PID 或路徑。
超過 45 分鐘未更新的非終止狀態標成 Stale。Monitor 不會啟動、停止或喚醒 Ox。

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
Codex quota remaining percentage/window/reset time、sanitized runtime phase、allow-listed runtime activity、bounded Issue duration 與各 lane item。它刻意不輸出 controller run ID、PID、
base/head SHA、account identity、credential、prompt、response、finding、完整命令／輸出或 raw token activity。Issue 標題和工作
狀態本身仍是私人資料；遠端存取只能使用 Tailscale Serve 和適當 ACL，不得使用
Tailscale Funnel、public tunnel 或公開 hosting。

同一 snapshot 可包含上述 bounded Ox audit summary；它不包含模型 usage 或分類內容。

## Forbidden behavior

- 對 GitHub 或 mobile dashboard 使用非 GET/HEAD HTTP method；
- 對 loopback Ollama `/api/chat` 以外的 inference 或 management endpoint 發 request；
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
- Ollama request construction tests enforce loopback-only URL、closed payload、thinking/session disable、strict response keys/bounds，以及 model 不得改變 deterministic recommendation。
- `MobileDashboardTests` exercise the real loopback listener, security headers, method allow-list, untrusted Host rejection and sanitized schema；source scans reject public binding, CORS and browser persistence。
