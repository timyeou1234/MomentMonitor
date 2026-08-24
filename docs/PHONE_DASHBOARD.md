# Phone dashboard

Moment Monitor 可以把 Mac 上已經判定完成的唯讀 snapshot 顯示在 iPhone。它不是
另一個 controller，也不會從手機觸發、取消、重跑或合併任何工作。

## Recommended setup: Tailscale Serve

1. 在 Mac 和 iPhone 安裝 Tailscale，登入同一個 tailnet。
2. 開啟 Moment Monitor → **Settings** → **Phone dashboard**。
3. 啟用 dashboard、保留預設 port `48127`，再按 **Apply**。
4. 按 **Open Local Dashboard**。這一步必須先成功；它驗證 app 與頁面本身。
5. 按 **Copy Tailscale Command**，在 Mac Terminal 執行：

   ```bash
   tailscale serve --bg http://127.0.0.1:48127
   ```

6. 執行 `tailscale serve status`，複製它顯示的私人 HTTPS 網址。
7. 確認 iPhone 的 Tailscale 已連線，再用 Safari 開啟該網址。
8. 若希望像 app 一樣開啟，可在 Safari 分享選單選「加入主畫面」。

只使用 **Serve**。不要啟用 **Funnel**；Funnel 的設計目的是把服務公開到網際網路。

## What the phone can see

- M1 closed/total progress；
- Codex quota remaining percentage、window 與 reset time；
- Luna、Sol Fast、Sol High 的目前 phase、role、round 和 repair attempt；
- 由 controller v1/v2/v3 round/repair counters 推導的 Review、PR Fast 與 Final Sol High 策略軌道；已完成、目前、待執行與 halted checkpoint 分開顯示，不推測 review pass 或未知百分比；
- controller v2 發布的 Exec／App Server 即時活動來源、allow-listed 動作、狀態、更新時間、計數與最多四筆最近事件；
- controller v3 發布的 bounded per-Issue Codex controller-active wall-clock time；
- Issue / PR identity、phase elapsed time與五段 lifecycle；
- Ready、Waiting、Running、PR / Checks、Blocked、Completed 等工作清單；
- 對應的 GitHub deep link。

API 不包含 run ID、PID、base/head Git SHA、credentials、prompt、response、finding、
完整命令、命令輸出、token 或 local filesystem path。瀏覽器頁面不會把 snapshot 寫到永久儲存空間。
不過 Issue 標題和工作狀態仍可能是私人資訊；請用 Tailscale ACL 限制 tailnet
中哪些人或裝置能連到這台 Mac。

## Availability and freshness

Mac 必須開機、Moment Monitor 必須執行中，而且 Mac 與 iPhone 都必須連上
Tailscale。頁面在前景每秒更新，切到背景後降為每 10 秒；iOS 可以暫停背景
Safari，所以回到頁面時才會立即重新連線。連線暫時中斷時，頁面只保留目前
記憶體中的最後畫面並顯示 Mac unavailable，不會把舊 snapshot 當成即時資料。

頁首 **Refresh** 可立即重新向 Mac 讀取 snapshot，適合從背景回來或連線恢復後
手動重試；它不會啟動 automation，也不會修改 GitHub、controller status 或 Codex。
`Last update at` 顯示 GitHub snapshot、runtime telemetry 與 Codex usage 中最新的來源
時間；頁尾 `Received …` 只表示手機最近成功收到 Mac 回應的時間。兩者刻意分開，
避免把傳輸成功誤認為資料已改變。

## Stop or reset

暫停 dashboard：在 Moment Monitor Settings 關閉 **Phone dashboard** 並 Apply。
這會停止 localhost server，但不會修改 Tailscale 設定。

完全移除 Tailscale Serve 設定：

```bash
tailscale serve reset
```

## Troubleshooting

### Mac 本機頁面打不開

- 確認 Settings 中 dashboard 已啟用且狀態為 Running。
- port 必須在 `1024...65535`，且不能被其他程式占用。
- 關閉再開啟 dashboard，或重新啟動 Moment Monitor。

### Mac 可以、iPhone 不行

- 確認兩台裝置登入同一個 tailnet 且狀態為 Connected。
- 在 Mac 執行 `tailscale serve status`，使用它列出的 HTTPS 網址，不要使用
  `127.0.0.1`。
- 檢查 tailnet ACL 是否允許 iPhone 使用者/裝置連到 Mac。
- 若 Moment Monitor port 有修改，重新執行對應的新 `tailscale serve --bg` 指令。

### Page says Mac unavailable

這表示頁面暫時收不到新 snapshot。確認 Mac 沒有睡眠、Moment Monitor 仍執行，
以及 Tailscale 連線正常。頁面恢復可見時會立刻重試。
