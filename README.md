# Claude Code 自訂狀態列

在 Claude Code 輸入框下方顯示一行狀態列，單行六組：

```
🤖 Opus 4.8|high  🔋 24%|4h30m|81%  🌿 main  📊 142.6k|71%  ⚡ 98%|76%  💰 142.9k|$3.46
```

| 組 | 內容 |
|----|------|
| 🤖 | model \| effort |
| 🔋 | 5 小時用量% \| reset 倒數 \| 週用量%（僅 Claude.ai Pro/Max 訂閱、且 session 有過回應後才出現） |
| 🌿 | 目前 git branch（不在 repo 時自動省略） |
| 📊 | context token 數 \| 百分比 |
| ⚡ | cache 當前命中率 \| 累計命中率 |
| 💰 | session 累計 token \| 累計花費（USD） |

顏色會依用量變化（context / 用量越高越紅、cache 命中率越高越綠）。

## 包內容
| 檔案 | 用途 |
|------|------|
| `install-statusline.md` | **給 Claude Code 讀的安裝指引**（自動判斷平台、找檔、備份設定後安裝） |
| `statusline.py` | Python 版 → **Linux / macOS / WSL**（只需 Python 3.7+，不用裝其他套件） |
| `statusline.ps1` | PowerShell 版 → **原生 Windows**（Windows PowerShell 5.1 與 PowerShell 7+ 皆可，不用裝任何東西） |
| `LICENSE` | MIT 授權條款 |

兩個版本顯示內容與行為完全一致，依平台擇一安裝即可。

## 快速安裝（推薦）
1. 把整包解壓到**同一個資料夾**。
2. 在該資料夾開 Claude Code，對它說：
   > 請照這個資料夾裡的 install-statusline.md 幫我安裝狀態列，並自動找到對應的 script 檔。

它會自動：判斷平台、選對 script、裝到 `~/.claude/`、測試、**先備份再只改 settings.json 的 `statusLine` key**（不動你其他設定），遇到要覆蓋檔案時會先問你。

## 手動安裝
把對應 script 放到 `~/.claude/`（Windows：`%USERPROFILE%\.claude\`），
在 `~/.claude/settings.json` 加入 `statusLine`（`command` 一律用**絕對路徑**）：

- **Linux / macOS / WSL**：`"python3 /home/使用者/.claude/statusline.py"`
- **Windows**：`"powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/使用者/.claude/statusline.ps1"`（路徑用正斜線）

並加上 `"refreshInterval": 10`（讓 🔋 的 reset 倒數持續跳動）。範例：

```json
{
  "statusLine": {
    "type": "command",
    "command": "python3 /home/使用者/.claude/statusline.py",
    "refreshInterval": 10
  }
}
```

## 注意事項
- **不耗 token**：script 在本機執行，不呼叫 API。
- **🔋 那組**需 Claude.ai Pro/Max 訂閱、且 session 有過至少一次回應才會出現；條件不符時整組自動省略，其餘五組照常。
- **Windows** command 一定要帶 `-ExecutionPolicy Bypass`，否則預設 Restricted 政策會擋下 script、狀態列無聲消失。
- **`statusline.ps1` 必須保留 UTF-8 BOM**（直接複製檔案即可，不要另存或轉檔），否則 emoji 會變 `?`。
- 官方文件：https://code.claude.com/docs/en/statusline （也可用內建 `/statusline` 指令讓 Claude Code 幫你改）。

## 效能與檔案共用
- **增量解析**：累計 token 要讀 session 的 transcript（JSONL），長對話可達數百 MB。
  script 會在暫存資料夾記住已讀到的位置，之後每次只讀新增的部分；
  單次最多掃 3 秒，沒讀完的下次接著讀，不會讓狀態列卡住。
- **不鎖檔**：讀 transcript 時允許 Claude Code 同時寫入。
  舊版 PowerShell 版讀檔會擋住寫入，可能出現
  `Transcript writes are failing (EBUSY) · recent messages may not be saved for resume`，本版已修正。

## 授權
[MIT License](LICENSE)：可自由使用、修改、再發佈（包含商業用途），只需保留版權與授權聲明。

## 更新紀錄
- **2026-11**
  - 修正：PowerShell 版讀 transcript 時鎖住檔案，造成 Claude Code 出現 EBUSY 警告。
  - 修正：Python 版在 Windows（cp950 等非 UTF-8 系統）輸出 emoji 時當掉、中文路徑讀成亂碼。
  - 改進：transcript 改為增量解析並限制單次掃描時間，大型 session 不再拖慢狀態列。
  - 移除 bash 版（需要額外安裝 jq）；Linux / macOS 統一使用不需相依套件的 Python 版。
