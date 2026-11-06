# Claude Code 自訂狀態列 — 安裝指引（給 Claude Code 執行）

這是一份**安裝任務**。請你（Claude Code）依下列步驟，把與本檔案同目錄的狀態列 script
安裝到我的 Claude Code 環境。**只做安裝，不要修改 script 內容。**

## 執行原則
- 每個步驟動作前，先用一句話說明你要做什麼。
- 任何需要 `sudo`、或會覆蓋 / 刪除既有檔案的動作，**先停下來問我**，同意後再做。
- 修改 `settings.json` 前一定先備份，且**只更動 `statusLine` 這個 key**，其他設定原封不動。

同目錄應該有兩個 script，依平台擇一安裝：
- `statusline.ps1` — PowerShell 版 → **Windows**（Windows PowerShell 5.1 與 PowerShell 7+ 皆可，免安裝任何東西）
- `statusline.py` — Python 版 → **Linux / macOS / WSL**（只需 Python 3.7+，免安裝其他套件）

---

## 步驟 0：判斷平台，選定 script
判斷我目前執行 Claude Code 的環境：
- **Windows**（包含在 PowerShell、cmd 或 Git Bash 裡執行 Claude Code）→ 使用 `statusline.ps1`
  （Windows 一定內建 PowerShell，不需要另外裝 Python）
- **Linux / macOS / WSL** → 使用 `statusline.py`

判斷方式：`uname -s`（Linux / Darwin；Git Bash 會是 `MINGW*` / `MSYS*`，視為 Windows）、`$OSTYPE`、或系統資訊。
若無法確定平台，直接問我「你是在 Windows，還是 WSL / Linux / macOS 裡執行 Claude Code？」再繼續。
以下用 **<SCRIPT>** 代表你選定的那個檔案。

## 步驟 1：找到 script 檔
依序在下列位置尋找 <SCRIPT>：
1. 與本說明檔（`install-statusline.md`）相同的目錄 ← 最優先
2. 目前工作目錄
3. `~/Downloads`（Windows：`%USERPROFILE%\Downloads`）

找到後印出**前 3 行**確認它確實是狀態列 script。
若怎麼都找不到，停下來告訴我，請我提供檔案位置。

## 步驟 2：安裝到使用者的 .claude 目錄
若目標位置已經有舊版 script，**先問我**是否覆蓋（同意後先備份成 `.bak` 再覆蓋）。
- **Linux / macOS / WSL：**
  - 建立 `~/.claude/`（若不存在）
  - 複製 `statusline.py` 到 `~/.claude/statusline.py`
  - 執行 `chmod +x ~/.claude/statusline.py`
- **Windows：**
  - 建立 `%USERPROFILE%\.claude\`（若不存在）
  - 複製 `statusline.ps1` 到 `%USERPROFILE%\.claude\statusline.ps1`
  - 請用**二進位複製**（`Copy-Item` 或 `cp`）搬檔，**不要**用會重新編碼的方式
    （例如 `Get-Content ... | Set-Content ...`）——那會弄掉檔頭的 UTF-8 BOM，emoji 就壞了（原因見步驟 3）。

## 步驟 3：相依檢查
- **Python 版（statusline.py）**：執行 `python3 --version`，確認是 **3.7 以上**。
  - Linux 與 macOS 通常已內建 python3，**不需要安裝任何東西**。
  - macOS 若跳出「需要安裝命令列開發者工具」，請我按安裝，裝完再繼續。
  - 若沒有 `python3` 但 `python --version` 顯示 3.7 以上，之後的指令與 command 一律改用 `python`。
  - 都沒有就停下來告訴我，請我安裝 Python 3。**不要自己 sudo 安裝。**
- **PowerShell 版（statusline.ps1）**：無需額外相依（用內建 `ConvertFrom-Json`，相容 PowerShell 5.1+）。
  但**編碼有兩個要件**，少任一個，狀態列都會出現、只是 emoji 變成 `?` 或亂碼：
  - **檔案必須保留 UTF-8 BOM。** 腳本裡的 emoji（🤖 🔋 🌿 📊 ⚡ 💰）是輸出字串中的實體字元，
    不是註解。Windows PowerShell 5.1 讀「無 BOM 的 UTF-8」時會當成系統 ANSI 碼頁
    （繁中 Windows 為 cp950）來解析，字元在**剖析階段**就已經壞掉，之後再怎麼設 console 編碼都救不回來。
    附的 `statusline.ps1` 已經是 UTF-8 with BOM，照步驟 2 直接複製即可，不要另存或轉檔。
  - **腳本開頭會自行把 stdin/stdout 設成 UTF-8**（`[Console]::OutputEncoding` / `[Console]::InputEncoding`）。
    這段已內建在 script 裡，你不用動手，但**也不要把它刪掉**——少了它，輸出在 cp950 主控台一樣會被轉成 `?`。

## 步驟 4：測試 script
餵一段測試 JSON 給剛安裝好的 script，確認它輸出「一行」狀態列且不報錯。

**Linux / macOS / WSL：**
```
echo '{"model":{"display_name":"Test"},"effort":{"level":"high"},"workspace":{"current_dir":"'"$PWD"'"},"session_id":"install-test","context_window":{"total_input_tokens":1000,"used_percentage":5}}' | python3 ~/.claude/statusline.py
```

**Windows（PowerShell）：**
```
echo '{"model":{"display_name":"Test"},"effort":{"level":"high"},"workspace":{"current_dir":"C:/tmp"},"session_id":"install-test","context_window":{"total_input_tokens":1000,"used_percentage":5}}' | powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\statusline.ps1"
```

有印出一行帶 icon（🤖 …）的內容就算成功。
**注意（Windows）：測試命令與步驟 5 寫入 settings.json 的 command 必須完全一致（含 `-ExecutionPolicy Bypass`）**，
否則會發生「測試通過、但實際安裝後被系統擋下、狀態列無聲消失」的情況。

## 步驟 5：合併設定到 settings.json
目標檔：`~/.claude/settings.json`（Windows：`%USERPROFILE%\.claude\settings.json`）
1. 若檔案不存在，先建立成 `{}`。
2. 備份成 `settings.json.bak`。
3. 讀進現有 JSON，**只新增 / 覆寫 `statusLine` 這個 key，保留所有其他既有設定**，再寫回。
4. `statusLine` 內容：
   - `type`: `"command"`
   - `command`（依你選定的版本，一律使用**展開後的絕對路徑**，不要留 `~` / `$HOME` / `%USERPROFILE%`）：
     - **Linux / macOS / WSL**：`"python3 /home/使用者/.claude/statusline.py"`（步驟 3 若改用 `python`，這裡也用 `python`）
     - **Windows**：`"powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/使用者/.claude/statusline.ps1"`
       —— 兩個重點：
       (a) **務必帶 `-ExecutionPolicy Bypass`**。Windows 的 ExecutionPolicy 預設為 `Restricted`，
           少了這個 flag，命令會被系統擋下（`running scripts is disabled`），狀態列完全不出現、且無錯誤提示。
           政策本來就允許的機器多帶此 flag 也無害，因此**無條件加上**。
       (b) **路徑務必用正斜線 `/`**，不要用反斜線 `\`（JSON 會把 `\` 當跳脫字元）。
   - `refreshInterval`: `10`（讓 reset 倒數會持續跳動；單位為秒）

最終結果範例（Linux / macOS）：
```json
{
  "statusLine": {
    "type": "command",
    "command": "python3 /home/使用者/.claude/statusline.py",
    "refreshInterval": 10
  }
}
```

最終結果範例（Windows）：
```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/使用者/.claude/statusline.ps1",
    "refreshInterval": 10
  }
}
```

## 步驟 6：回報
印出最終的 `settings.json` 給我確認，並提醒我「送下一則訊息，就會在輸入框下方看到狀態列」。
若狀態列沒出現，請優先依序檢查：
- **command 路徑沒展開**（留了 `~` / `$HOME` / `%USERPROFILE%` 沒展開成絕對路徑）
- **Windows 用了反斜線**（`\` 要改成 `/`）
- **Windows command 缺少 `-ExecutionPolicy Bypass`**：少了它，script 會被系統擋下（`running scripts is disabled`），狀態列無聲消失、且不報錯——請確認寫入 settings.json 的 command 確實含此 flag。
- **Linux / macOS 的 `python3` 不存在或版本太舊**（需 3.7+；見步驟 3）。

若狀態列**有出現、但 emoji 變成 `?` 或亂碼**（常見於繁中 / 日文等非 UTF-8 系統），那不是設定問題，是**檔案編碼**問題，依序檢查：
- **`statusline.ps1` 掉了 UTF-8 BOM**。檢查前三個位元組（此寫法 PowerShell 5.1 與 7+ 皆可用）：
  ```
  ([System.IO.File]::ReadAllBytes("$env:USERPROFILE\.claude\statusline.ps1")[0..2] | ForEach-Object { "{0:X2}" -f $_ }) -join " "
  ```
  應該印出 `EF BB BF`。不是的話，重新從原始檔用 `Copy-Item` 複製一次（見步驟 2、3）。
  （別用 `Format-Hex -Count 3`——`-Count` 是 PowerShell 6+ 才有的參數，5.1 會直接報錯。）
- **腳本開頭設定 console 編碼那幾行被刪掉了**（`$utf8` / `[Console]::OutputEncoding`），補回來即可。

若使用中出現 **`Transcript writes are failing (EBUSY)`**：那是舊版 PowerShell 版讀檔時鎖住 transcript 造成的，
換成本版 `statusline.ps1`（讀檔時允許 Claude Code 同時寫入）即可，`settings.json` 不用改。

---

### 這個狀態列會顯示什麼
單行，六組，由左到右：
1. 🤖 model | effort
2. 🔋 5 小時用量% | reset 倒數 | 週用量%　（僅 Claude.ai Pro/Max 訂閱、且 session 有過至少一次回應後才出現）
3. 🌿 目前 git branch（不在 repo 時自動省略）
4. 📊 context token 數 | 百分比
5. ⚡ cache 當前命中率 | 累計命中率
6. 💰 session 累計 token | 累計花費（USD）

兩個版本（statusline.py / statusline.ps1）顯示內容與行為完全一致。
script 在本機執行，不呼叫 API、不消耗 token；rate limit 為即時值，其餘由 stdin JSON 與本機 git / transcript 計算而來。
transcript 採增量解析（只讀新增部分、單次最多掃 3 秒），且讀檔時不會鎖住檔案。
