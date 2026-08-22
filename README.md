# Moment Monitor

`Moment Monitor` 是 Moments 自動化的 **唯讀 macOS menu-bar viewer**。它不加入 Moments repository、不執行任何 workflow，也不成為 scheduler、Codex task、PR Fast、auto-merge 或下一張 Issue dispatch 的依賴。

本專案參考 RepoBar 的 menu-bar 使用方式，但刻意不攜帶 RepoBar 的多 repository、多帳號、GraphQL、SQLite cache、local git sync、Sparkle updater 與 iOS app。這是一個針對 `timyeou1234/Moment` 的小型獨立 derivative；原因記錄於 [`docs/FORK_DECISION.md`](docs/FORK_DECISION.md)。

## 可以看到什麼

介面依照 Moments 現行自動化生命週期分成：

- **Ready**：owner-authored Issue 具有 `dev-ready` 或 `moment:dev-ready` marker，且直接依賴都已關閉；排序與 scheduler 相同。
- **Waiting on dependencies**：符合 ready 條件，但 `moment:depends-on` 仍有 open Issue。
- **Runner queue**：若 repository 仍有可見的相關 GitHub Actions run，狀態為 `queued`、`waiting`、`pending` 或 `requested`。
- **Running**：`dev-running` 表示本機 trusted task 正在執行；本機 runner 細節不會假裝成 GitHub 可觀測資料。若相關 workflow run 可見，才會補充目前 step。
- **PR / Checks**：locally reviewed automation PR 已開啟，但目前沒有 active run。
- **Blocked / Failed**：`dev-blocked`，或 repository state 與可見 workflow/PR 不一致。
- **Completed**：automation PR 確實 `merged_at != nil`，且對應 Issue 已關閉。Workflow success 本身不會被誤當成完成。

點選任何 row 只會開啟對應的 GitHub Issue、PR 或可見的 Actions run。

## 唯讀邊界

程式只允許兩種 GitHub CLI 呼叫：

```text
gh auth status
gh api <endpoint> --method GET
```

沒有下列能力：

```text
dispatch / rerun / cancel
label mutation / issue comment
merge / close / reopen
branch or local checkout changes
repository sync
```

詳細 contract 見 [`docs/READ_ONLY_BOUNDARY.md`](docs/READ_ONLY_BOUNDARY.md)。

## 系統需求

- macOS 14 或更新版本
- Swift 6 toolchain / Xcode
- GitHub CLI：`brew install gh`
- 已登入且可讀 private Moment repository：`gh auth login`

GUI app 從 Finder 啟動時 PATH 通常較短，因此程式會依序尋找：

```text
MOMENT_MONITOR_GH_PATH
/opt/homebrew/bin/gh
/usr/local/bin/gh
/usr/bin/gh
/opt/local/bin/gh
PATH 中的 gh
```

Issue 與 PR 會完整分頁；workflow history 只讀最新 100 筆，避免已淘汰或長期累積的歷史 run 超過 refresh timeout 而讓整個 viewer 無法更新。

## 建置與安裝

在 macOS 執行：

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

## 第一版限制

- 使用 polling，預設每 30 秒更新；沒有 webhook 或背景 server。
- 不讀 runner 上的 Codex JSONL，因此不顯示模型正在修改哪個檔案、執行哪個 shell command 或 Token 消耗。
- 不發送 native notification；先確認狀態判定在實際 Moments repo 上正確，再決定是否加入。
- 目前已在 Apple Silicon macOS 以 Swift 6.3.3 / Xcode 26.6 完成 `.app` build、ad-hoc signing、zip 解包與 bounded launch smoke；尚未做 Developer ID notarization 或長時間 polling soak。

## License 與 attribution

Moment Monitor 使用 MIT License。RepoBar 的參考與原始 MIT notice 保留於 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
