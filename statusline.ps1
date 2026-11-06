# ---------------------------------------------------------------------------
# Claude Code 自訂狀態列 — PowerShell 版（相容 Windows PowerShell 5.1 與 7+）
#   單行六組：
#   🤖 model|effort  🔋 5H%|reset|weekly%  🌿 branch  📊 ctx|%  ⚡ cache當前|總  💰 token|$
# 與 statusline.py / statusline.sh 行為一致。
#
# 效能：transcript 採「增量解析」——快取記住已讀到的位元組位置與各 request 的累計值，
#       每次只讀新增的行；git branch 與解析結果快取 5 秒（以 session_id 為 key）。
# 檔案共用：讀 transcript 時允許 Claude Code 同時寫入，避免出現
#           「Transcript writes are failing (EBUSY)」。
# 注意：本檔必須存成 UTF-8 with BOM，否則 Windows PowerShell 5.1 會把 emoji 讀壞。
# ---------------------------------------------------------------------------
$ErrorActionPreference = 'SilentlyContinue'

# 非 UTF-8 系統（如 cp950/Big5）下，emoji 會被編成 "?"。
# 明確指定 stdin/stdout 為 UTF-8（不帶 BOM），與呼叫端一致。
$utf8 = New-Object System.Text.UTF8Encoding $false
[Console]::OutputEncoding = $utf8
[Console]::InputEncoding  = $utf8

$raw = [Console]::In.ReadToEnd()
if (-not $raw) { exit 0 }
$j = $raw | ConvertFrom-Json
if ($null -eq $j) { exit 0 }

function Val($v, $d) { if ($null -ne $v) { $v } else { $d } }

# ---- 從 stdin JSON 取值 ----
$model = if ($j.model.display_name) { $j.model.display_name } elseif ($j.model.id) { $j.model.id } else { '?' }
$effort = $j.effort.level
$cwd    = if ($j.workspace.current_dir) { $j.workspace.current_dir } elseif ($j.cwd) { $j.cwd } else { '.' }
$gitwt  = $j.workspace.git_worktree
$sid    = if ($j.session_id) { $j.session_id } else { 'nosession' }
$tp     = $j.transcript_path

$ctxTok = [int64](Val $j.context_window.total_input_tokens 0)
$ctxPct = [int][math]::Floor([double](Val $j.context_window.used_percentage 0))

# 當前 cache 命中率
$cu = $j.context_window.current_usage
if ($null -ne $cu) {
    $cuIn = [int64](Val $cu.input_tokens 0)
    $cuCc = [int64](Val $cu.cache_creation_input_tokens 0)
    $cuCr = [int64](Val $cu.cache_read_input_tokens 0)
    $d = $cuIn + $cuCc + $cuCr
    if ($d -gt 0) { $curHit = [int][math]::Floor($cuCr * 100.0 / $d) } else { $curHit = '-' }
} else {
    $curHit = '-'   # current_usage 為 null（首次 API 回應前 / /compact 後）
}

$cost = [double](Val $j.cost.total_cost_usd 0)

# ---- rate limits（即時值，僅 Pro/Max 訂閱且 session 首個回應後才有）----
$r5pct   = $j.rate_limits.five_hour.used_percentage
$r5reset = $j.rate_limits.five_hour.resets_at
$r7pct   = $j.rate_limits.seven_day.used_percentage

# ---- 快取：git branch + transcript 增量累計（5 秒）----
# 快取格式：v2 / offset / transcript 路徑 / branch / 之後每行 key<TAB>i<TAB>cc<TAB>cr<TAB>o
$cacheVer  = 'v2'
$cacheFile = Join-Path ([System.IO.Path]::GetTempPath()) "cc-statusline-$cacheVer-$sid"
$ttl = 5

function Load-State($path) {
    try {
        if (-not (Test-Path -LiteralPath $path)) { return $null }
        $lines = [System.IO.File]::ReadAllText($path, $utf8).Split("`n")
        if ($lines.Count -lt 4 -or $lines[0] -ne $cacheVer) { return $null }
        $g = @{}
        for ($k = 4; $k -lt $lines.Count; $k++) {
            $f = $lines[$k].Split("`t")
            if ($f.Count -ne 5) { continue }
            $g[$f[0]] = [int64[]]@([int64]$f[1], [int64]$f[2], [int64]$f[3], [int64]$f[4])
        }
        return @{ off = [int64]$lines[1]; tp = $lines[2]; branch = $lines[3]; g = $g }
    } catch { return $null }
}

function Save-State($path, $st) {
    $tmp = "$path.$PID.tmp"
    try {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append("$cacheVer`n$($st.off)`n$($st.tp)`n$($st.branch)`n")
        foreach ($kv in $st.g.GetEnumerator()) {
            $v = $kv.Value
            [void]$sb.Append("$($kv.Key)`t$($v[0])`t$($v[1])`t$($v[2])`t$($v[3])`n")
        }
        [System.IO.File]::WriteAllText($tmp, $sb.ToString(), $utf8)
        # PowerShell 會把 $null 轉成空字串傳給 .NET，要用 [NullString]::Value 才是真的 null
        if (Test-Path -LiteralPath $path) { [System.IO.File]::Replace($tmp, $path, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $path) }
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# 快速路徑：直接用 regex 取 usage 數字（PowerShell 5.1 的 ConvertFrom-Json 解析大行很慢）。
# (?<!\\) 排除字串內被跳脫的引號，避免誤抓訊息內容裡的文字。
$reType = [regex]'(?<!\\)"type":"assistant"'
$reReq  = [regex]'(?<!\\)"requestId":"([^"\\]+)"'
$reIn   = [regex]'(?<!\\)"input_tokens":(\d+)'
$reCc   = [regex]'(?<!\\)"cache_creation_input_tokens":(\d+)'
$reCr   = [regex]'(?<!\\)"cache_read_input_tokens":(\d+)'
$reOut  = [regex]'(?<!\\)"output_tokens":(\d+)'
function NumOf($re, $s) { $m = $re.Match($s); if ($m.Success) { [int64]$m.Groups[1].Value } else { 0L } }

# 從 $st.off 開始只讀新增的完整行，更新 $st.g（以 requestId 分組，各欄取 max）。
# 每次最多掃 $budget 秒就先存進度，下次接著讀，避免大檔讓狀態列卡住。
$budget = 3
function Scan-Transcript($path, $st) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # FileShare.ReadWrite|Delete：讀檔期間 Claude Code 仍可繼續寫入 transcript
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    try {
        $len = $fs.Length
        if ($st.tp -ne $path -or $st.off -gt $len) { $st.tp = $path; $st.off = 0L; $st.g = @{} }  # 換檔或被截短 → 從頭算
        if ($st.off -eq $len) { return }
        $fs.Position = $st.off
        $sr  = New-Object System.IO.StreamReader($fs, $utf8, $false, 65536)
        $pos = [int64]$st.off
        $g   = $st.g
        while ($null -ne ($line = $sr.ReadLine())) {
            $nb = [int64]$utf8.GetByteCount($line) + 1          # +1 = 換行字元
            if ($pos + $nb -gt $len) { break }                  # 最後一行還沒寫完，下次再讀
            $pos += $nb
            # 先用字串篩掉不含 usage 的行（例如夾帶圖片的巨大 user 行），省下解析
            if ($line.IndexOf('"usage"') -ge 0 -and $line.IndexOf('"assistant"') -ge 0) {
                $mReq = $reReq.Match($line)
                if ($mReq.Success) {
                    if (-not $reType.IsMatch($line)) { $key = $null }
                    else {
                        $key = $mReq.Groups[1].Value
                        $v = [int64[]]@((NumOf $reIn $line), (NumOf $reCc $line), (NumOf $reCr $line), (NumOf $reOut $line))
                    }
                } else {
                    # 沒有 requestId 的少見格式：退回完整 JSON 解析
                    $key = $null
                    try { $o = $line | ConvertFrom-Json } catch { $o = $null }
                    if ($null -ne $o -and $o.type -eq 'assistant' -and $null -ne $o.message.usage) {
                        $u = $o.message.usage
                        $key = if ($o.uuid) { "$($o.uuid)" } elseif ($o.message.id) { "$($o.message.id)" } else { '_' }
                        $v = [int64[]]@([int64](Val $u.input_tokens 0), [int64](Val $u.cache_creation_input_tokens 0),
                                        [int64](Val $u.cache_read_input_tokens 0), [int64](Val $u.output_tokens 0))
                    }
                }
                if ($null -ne $key) {
                    if (-not $g.ContainsKey($key)) { $g[$key] = [int64[]]@(0, 0, 0, 0) }
                    $r = $g[$key]
                    for ($q = 0; $q -lt 4; $q++) { if ($v[$q] -gt $r[$q]) { $r[$q] = $v[$q] } }
                }
            }
            if ($sw.Elapsed.TotalSeconds -ge $budget) { break }   # 時間到，下次接著讀
        }
        $st.off = $pos
    } finally { $fs.Dispose() }
}

$st = Load-State $cacheFile
$fresh = $false
if ($null -ne $st) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $cacheFile).LastWriteTime).TotalSeconds
    if ($age -lt $ttl) { $fresh = $true }
}

if (-not $fresh) {
    if ($null -eq $st) { $st = @{ off = 0L; tp = "$tp"; branch = ''; g = @{} } }

    # --- git branch ---
    $branch = ''
    $null = & git -C "$cwd" rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -eq 0) {
        $branch = (& git -C "$cwd" branch --show-current 2>$null)
        if (-not $branch) { $branch = (& git -C "$cwd" rev-parse --short HEAD 2>$null) }  # detached
    }
    if (-not $branch) { $branch = [string](Val $gitwt '') }
    $st.branch = "$branch".Trim()

    # --- transcript 增量累計 ---
    if ($tp -and (Test-Path -LiteralPath $tp)) {
        try { Scan-Transcript $tp $st } catch { }
    }
    Save-State $cacheFile $st
}

$branch = $st.branch
$tin = 0L; $tcc = 0L; $tcr = 0L; $tout = 0L
foreach ($v in $st.g.Values) { $tin += $v[0]; $tcc += $v[1]; $tcr += $v[2]; $tout += $v[3] }

# ---- 計算 ----
$td = $tin + $tcc + $tcr
if ($td -gt 0) { $totHit = [int][math]::Floor($tcr * 100.0 / $td) } else { $totHit = '-' }
$sessTok = $tin + $tcc + $tcr + $tout

function Human($n) {
    if ($n -ge 1000000) { '{0:0.00}M' -f ($n / 1000000.0) }
    elseif ($n -ge 1000) { '{0:0.0}k' -f ($n / 1000.0) }
    else { "$n" }
}
$ctxH   = Human $ctxTok
$sessH  = Human $sessTok
$costFmt = '${0:0.00}' -f $cost

# ---- 顏色 ----
$e = [char]27
$R = "$e[0m"; $DIM = "$e[2m"
$CYAN = "$e[36m"; $GREEN = "$e[32m"; $YELLOW = "$e[33m"; $RED = "$e[31m"; $MAG = "$e[35m"

if ($ctxPct -ge 90) { $ctxC = $RED } elseif ($ctxPct -ge 70) { $ctxC = $YELLOW } else { $ctxC = $GREEN }

function HitColor($h) {
    if ($h -eq '-') { return $DIM }
    if ($h -ge 80) { $GREEN } elseif ($h -ge 50) { $YELLOW } else { $RED }
}
$curC = HitColor $curHit
$totC = HitColor $totHit

# ---- rate limit：百分比取整、用量配色、reset 倒數 ----
function UsageColor($p) {  # 用量越高越紅
    if ($null -eq $p) { return $DIM }
    if ($p -ge 80) { $RED } elseif ($p -ge 50) { $YELLOW } else { $GREEN }
}
$haveRate = ($null -ne $r5pct)
if ($haveRate) {
    $r5 = [int][math]::Round([double]$r5pct)
    $r7 = if ($null -ne $r7pct) { [int][math]::Round([double]$r7pct) } else { 0 }
    $resetStr = '-'
    if ($null -ne $r5reset) {
        $now  = [int64][math]::Floor(([DateTimeOffset]::UtcNow).ToUnixTimeSeconds())
        $diff = [int64]$r5reset - $now
        if ($diff -lt 0) { $diff = 0 }
        if     ($diff -ge 86400) { $resetStr = "$([math]::Floor($diff/86400))d$([math]::Floor(($diff%86400)/3600))h" }
        elseif ($diff -ge 3600)  { $resetStr = "$([math]::Floor($diff/3600))h$([math]::Floor(($diff%3600)/60))m" }
        else                     { $resetStr = "$([math]::Floor($diff/60))m" }
    }
    $r5c = UsageColor $r5
    $r7c = UsageColor $r7
}

$gap = '  '
$bar = "$DIM|$R"

if ($effort) { $modelSeg = "$CYAN$model$DIM|$R$CYAN$effort$R" } else { $modelSeg = "$CYAN$model$R" }
$gModel = "🤖 $modelSeg"
if ($haveRate) { $gRate = "$gap🔋 $r5c$r5%$R$bar$DIM$resetStr$R$bar$r7c$r7%$R" } else { $gRate = '' }
if ($branch) { $gBranch = "$gap🌿 $GREEN$branch$R" } else { $gBranch = '' }
$gCtx   = "$gap📊 $ctxH$bar$ctxC$ctxPct%$R"
$gCache = "$gap⚡ $curC$curHit%$R$bar$totC$totHit%$R"
$gToken = "$gap💰 $MAG$sessH$R$bar$YELLOW$costFmt$R"

Write-Host "$gModel$gRate$gBranch$gCtx$gCache$gToken"
