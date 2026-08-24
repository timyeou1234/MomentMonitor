# Moment Monitor

`Moment Monitor` 是 Moments 自動化的 **唯讀 macOS menu-bar viewer**，並可選擇把同一份狀態透過私人手機 dashboard 顯示。它不加入 Moments repository、不執行任何 workflow，也不成為 scheduler、Codex task、PR Fast、auto-merge 或下一張 Issue dispatch 的依賴。當同一台 Mac 上有新版 trusted controller 時，它也會安全讀取 controller 主動發布的 credential-free local phase telemetry。

本專案參考 RepoBar 的 menu-bar 使用方式，但刻意不攜帶 RepoBar 的多 repository、多帳號、GraphQL、SQLite cache、local git sync、Sparkle updater 與 iOS app。這是一個針對 `timyeou1234/Moment` 的小型獨立 derivative；原因記錄於 [`docs/FORK_DECISION.md`](docs/FORK_DECISION.md)。

## 可以看到什麼

介面依照 Moments 現行自動化生命週期分成：

- **M1 progress**：分母是所有標題以 `[M1]` 開頭的 GitHub Issues，分子是其中 state 為 closed 的 Issues。它不受 automation 是否已排程、lane 是否顯示、Completed 清單上限或 PR 數量影響。
- **Codex capacity**：透過官方 Codex App Server 唯讀取得目前 quota window 的剩餘百分比與重置時間；超過 3 分鐘未成功刷新即降為 Stale 並隱藏舊百分比，不以本機 token 紀錄估算，也不提供額度重置或購買操作。
- **Current automation**：精確顯示 Luna 開發、PR Fast、Sol review/repair、Luna verification、Sol High unblock、PR publication、exact-head verification、merge 與 Issue closure；包含模型角色、回合、Issue/PR identity、階段耗時與五段 lifecycle track。
- **Ready**：owner-authored Issue 具有 `dev-ready` 或 `moment:dev-ready` marker，且直接依賴都已關閉；排序與 scheduler 相同。
- **Waiting on dependencies**：符合 ready 條件，但 `moment:depends-on` 仍有 open Issue。
- **Runner queue**：若 repository 仍有可見的相關 GitHub Actions run，狀態為 `queued`、`waiting`、`pending` 或 `requested`。
- **Running**：優先使用通過 schema、owner、permission、size 與 live-PID 驗證的 local phase telemetry；沒有有效 telemetry 時，才退回 `dev-running` 的粗略 GitHub 狀態。
- **PR / Checks**：locally reviewed automation PR 已開啟，但目前沒有 active run。
- **Blocked / Failed**：`dev-blocked`，或 repository state 與可見 workflow/PR 不一致。
- **Completed**：automation PR 確實 `merged_at != nil`，且對應 Issue 已關閉。Workflow success 本身不會被誤當成完成。

點選任何 row 只會開啟對應的 GitHub Issue、PR 或可見的 Actions run。

## 在 iPhone 查看

手機 dashboard 預設關閉；開啟後也只監聽 `127.0.0.1`，不會直接暴露在區域網路或公網。建議用 [Tailscale](https://tailscale.com/) 的私人網路連回 Mac：

1. 在 Mac 與 iPhone 安裝 Tailscale，登入同一個 tailnet。
2. 在 Moment Monitor 的 **Settings → Phone dashboard** 開啟服務並套用。
3. 先按 **Open Local Dashboard**，確認 Mac 本機可以看到頁面。
4. 按 **Copy Tailscale Command**，在 Mac Terminal 執行複製的 `tailscale serve` 指令。
5. 執行 `tailscale serve status` 取得私人的 `https://…ts.net` 網址，在 iPhone Safari 開啟；需要時可用 Safari 的「加入主畫面」。

請使用 **Tailscale Serve**，不要使用 Funnel。Serve 只讓 tailnet 中符合 ACL 規則的裝置存取；Funnel 會把服務公開到網際網路。Mac 必須開機、Moment Monitor 必須執行中，而且兩台裝置都要連上 Tailscale。完整安裝、停止方式與故障排除見 [`docs/PHONE_DASHBOARD.md`](docs/PHONE_DASHBOARD.md)。

## 唯讀邊界

程式只允許兩種 GitHub CLI 呼叫：

```text
gh auth status
gh api <endpoint> --method GET
```

Codex 用量只允許短暫啟動本機 `codex app-server`，完成初始化後呼叫：

```text
account/rateLimits/read
```

不會啟動 Codex thread/turn、讀取 token activity、消耗 reset credit 或變更帳號。

沒有下列能力：

```text
dispatch / rerun / cancel
label mutation / issue comment
merge / close / reopen
branch or local checkout changes
repository sync
```

此外只會讀取本機：

```text
~/Library/Application Support/MomentAutomation/runtime/current.json
```

它不讀 Moment checkout、不掃 Codex JSONL，也不讀 prompt、response、finding、raw token count 或 credential。Viewer 不存在、無法讀取或刪除該檔案時，Moment automation 必須完全不受影響。

手機 snapshot 不包含 controller run ID、PID、Git SHA、credential、prompt 或 response；也沒有 CORS、外部 script、持久化 browser cache 或 public hosting。tailnet 中獲准存取的裝置仍可看到 Issue 標題與目前工作狀態，因此應使用 Tailscale ACL 控制成員。詳細 contract 見 [`docs/READ_ONLY_BOUNDARY.md`](docs/READ_ONLY_BOUNDARY.md)。

## 系統需求

- macOS 14 或更新版本
- Swift 6 toolchain / Xcode
- GitHub CLI：`brew install gh`
- 已登入且可讀 private Moment repository：`gh auth login`
- 選用的 Codex capacity 需要已登入 ChatGPT/Codex 的 Codex CLI；找不到或無法驗證時只顯示 Unavailable，不影響其他監控。

GUI app 從 Finder 啟動時 PATH 通常較短，因此程式會依序尋找：

```text
MOMENT_MONITOR_GH_PATH
/opt/homebrew/bin/gh
/usr/local/bin/gh
/usr/bin/gh
/opt/local/bin/gh
PATH 中的 gh
```

Codex CLI 會依序尋找 `MOMENT_MONITOR_CODEX_PATH`、ChatGPT app 內建路徑、常見 Homebrew／系統路徑及 `PATH`。

Issue 與 PR 會完整分頁；workflow history 只讀最新 100 筆，避免已淘汰或長期累積的歷史 run 超過 refresh timeout 而讓整個 viewer 無法更新。

## 建置與安裝

在 macOS 執行一鍵安裝：

```bash
./Scripts/install_app.sh
```

它會先跑測試與 release build，驗證 ad-hoc signature，再安全更新並啟動：

```text
~/Applications/Moment Monitor.app
```

若要安裝到其他位置，可指定絕對目錄：

```bash
MOMENT_MONITOR_INSTALL_DIR=/Applications ./Scripts/install_app.sh
```

只建置、不安裝：

```bash
swift test
./Scripts/package_app.sh
open "dist/Moment Monitor.app"
```

打包 script 會建立 ad-hoc signed app 與 zip：

```text
dist/Moment Monitor.app
dist/MomentMonitor.zip
```

這是 menu-bar-only app，`LSUIElement` 已開啟，不會常駐 Dock。

## 開發

```bash
swift build --target MomentMonitorCore
swift test
./Scripts/check_read_only.sh
```

核心 model、GitHub decoding、依賴 parser、run correlation 與 state builder 可跨平台測試；SwiftUI menu-bar UI 僅在 macOS 編譯。最新驗證範圍見 [`docs/VALIDATION.md`](docs/VALIDATION.md)。

## 維護方式

- `main` 必須維持可建置、可安裝；功能與修正使用短期 branch 和 pull request。
- 每次 push 到 `main` 及每個 pull request 都會在 GitHub-hosted macOS runner 執行 warnings-as-errors、65 項 deterministic tests、唯讀契約、app 打包與簽章驗證。
- CI 只使用 synthetic fixtures，不配置 Moment repository credential，也不執行 live refresh。
- 發布版本使用 semantic version tag（例如 `v0.3.0`）；source 保持公開，但 Developer ID 與 notarization 完成前仍以本機 installer 安裝，不把 ad-hoc signed CI artifact 描述為可公開散佈的正式版本。
- Moment repository 不保存此 app 的 source copy，也不把它設為 automation dependency。

## 第一版限制

- GitHub 使用 polling，預設每 30 秒更新；沒有 webhook。手機頁面在前景每秒讀取 Mac 的記憶體 snapshot，背景時降為每 10 秒；頁首 **Refresh** 可立即重試這個唯讀讀取。`Last update at` 取 GitHub snapshot、runtime telemetry 與 Codex usage 中最新的來源時間，不以 HTTP 回應時間冒充資料更新。iOS 仍可能暫停背景 Safari。
- 不讀 runner 上的 Codex JSONL，因此不顯示模型正在修改哪個檔案、執行哪個 shell command、prompt/response 或 raw token activity；Codex capacity 只顯示官方 rate-limit percentage、window 與 reset time。
- 不發送 native notification；先確認狀態判定在實際 Moments repo 上正確，再決定是否加入。
- 目前已在 Apple Silicon macOS 以 Swift 6.3.3 / Xcode 26.6 完成 `.app` build、ad-hoc signing、zip 解包與 bounded launch smoke；尚未做 Developer ID notarization 或長時間 polling soak。

## License 與 attribution

Moment Monitor 使用 MIT License。RepoBar 的參考與原始 MIT notice 保留於 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
