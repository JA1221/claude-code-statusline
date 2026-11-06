#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# Claude Code 自訂狀態列 — Python 版（免相依，用內建 json；免 jq）
#   單行六組：
#   🤖 model|effort  🔋 5H%|reset|weekly%  🌿 branch  📊 ctx|%  ⚡ cache當前|總  💰 token|$
# 與 statusline.sh / statusline.ps1 行為一致。
#
# 效能：transcript 採「增量解析」——快取記住已讀到的位元組位置與各 request 的累計值，
#       每次只讀新增的行；git branch 與解析結果快取 5 秒（以 session_id 為 key）。
# ---------------------------------------------------------------------------
import sys, os, json, time, tempfile, subprocess

CACHE_VER = "v2"
TTL = 5
BUDGET = 3.0   # 每次最多掃幾秒；沒掃完的部分下次接著讀，避免大檔讓狀態列卡住


def human(n):
    if n >= 1_000_000:
        return "%.2fM" % (n / 1_000_000)
    if n >= 1_000:
        return "%.1fk" % (n / 1_000)
    return str(n)


def git_branch(cwd, gitwt):
    branch = ""
    try:
        if subprocess.run(["git", "-C", cwd, "rev-parse", "--git-dir"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            branch = subprocess.run(["git", "-C", cwd, "branch", "--show-current"],
                                    capture_output=True, text=True).stdout.strip()
            if not branch:  # detached HEAD
                branch = subprocess.run(["git", "-C", cwd, "rev-parse", "--short", "HEAD"],
                                        capture_output=True, text=True).stdout.strip()
    except Exception:
        branch = ""
    return branch or gitwt


def load_state(path):
    """快取格式：v2 / offset / transcript 路徑 / branch / 之後每行 key\\ti\\tcc\\tcr\\to"""
    try:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.read().split("\n")
        if lines[0] != CACHE_VER:
            return None
        groups = {}
        for ln in lines[4:]:
            if not ln:
                continue
            k, i, cc, cr, o = ln.split("\t")
            groups[k] = [int(i), int(cc), int(cr), int(o)]
        return {"off": int(lines[1]), "tp": lines[2], "branch": lines[3], "g": groups}
    except Exception:
        return None


def save_state(path, st):
    try:
        tmp = "%s.%d.tmp" % (path, os.getpid())
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join([CACHE_VER, str(st["off"]), st["tp"] or "", st["branch"]]) + "\n")
            for k, v in st["g"].items():
                f.write("%s\t%d\t%d\t%d\t%d\n" % (k, v[0], v[1], v[2], v[3]))
        os.replace(tmp, path)
    except Exception:
        pass


def scan_transcript(tp, st):
    """從 st['off'] 開始只讀新增的完整行，更新 st['g']（各 request 各欄取 max）。"""
    try:
        size = os.path.getsize(tp)
    except OSError:
        return
    if st["tp"] != tp or st["off"] > size:   # 換了檔案或檔案被截短 → 從頭算
        st["tp"], st["off"], st["g"] = tp, 0, {}
    if st["off"] == size:
        return
    groups = st["g"]
    off = st["off"]
    t0 = time.monotonic()
    # Python 在 Windows 上開檔預設允許其他程式同時寫入，不會鎖住 transcript
    with open(tp, "rb") as f:
        f.seek(off)
        for raw in f:
            if not raw.endswith(b"\n"):          # 最後一行還沒寫完，下次再讀
                break
            if time.monotonic() - t0 > BUDGET:   # 時間到：這行不算已讀，下次從這裡接著讀
                break
            off += len(raw)
            # 先用字串篩掉不含 usage 的行（例如夾帶圖片的巨大 user 行），省下 JSON 解析
            if b'"usage"' not in raw or b'"assistant"' not in raw:
                continue
            try:
                o = json.loads(raw)
            except Exception:
                continue
            if o.get("type") != "assistant":
                continue
            msg = o.get("message") or {}
            u = msg.get("usage")
            if not u:
                continue
            key = str(o.get("requestId") or o.get("uuid") or msg.get("id") or "_")
            r = groups.setdefault(key, [0, 0, 0, 0])
            r[0] = max(r[0], int(u.get("input_tokens") or 0))
            r[1] = max(r[1], int(u.get("cache_creation_input_tokens") or 0))
            r[2] = max(r[2], int(u.get("cache_read_input_tokens") or 0))
            r[3] = max(r[3], int(u.get("output_tokens") or 0))
    st["off"] = off


def main():
    # Windows（cp950 等非 UTF-8 系統）下，stdin/stdout 預設不是 UTF-8：
    # 輸出 emoji 會丟 UnicodeEncodeError，含中文的路徑也會讀成亂碼 → 一律改用 UTF-8
    for s in (sys.stdin, sys.stdout):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    raw = sys.stdin.read()
    if not raw.strip():
        return
    try:
        j = json.loads(raw)
    except Exception:
        return

    # ---- 從 stdin JSON 取值 ----
    model  = (j.get("model") or {}).get("display_name") or (j.get("model") or {}).get("id") or "?"
    effort = (j.get("effort") or {}).get("level")
    ws     = j.get("workspace") or {}
    cwd    = ws.get("current_dir") or j.get("cwd") or "."
    gitwt  = ws.get("git_worktree") or ""
    sid    = j.get("session_id") or "nosession"
    tp     = j.get("transcript_path")

    cw = j.get("context_window") or {}
    ctx_tok = int(cw.get("total_input_tokens") or 0)
    up = cw.get("used_percentage")
    try:
        ctx_pct = int(float(up)) if up is not None else 0
    except (TypeError, ValueError):
        ctx_pct = 0

    # 當前 cache 命中率 = cache_read / (input + cache_creation + cache_read)
    cu = cw.get("current_usage")
    if cu:
        cin = int(cu.get("input_tokens") or 0)
        ccc = int(cu.get("cache_creation_input_tokens") or 0)
        ccr = int(cu.get("cache_read_input_tokens") or 0)
        d = cin + ccc + ccr
        cur_hit = ccr * 100 // d if d > 0 else "-"
    else:
        cur_hit = "-"   # current_usage 為 null（首次 API 回應前 / /compact 後）

    cost = float((j.get("cost") or {}).get("total_cost_usd") or 0)

    # ---- rate limits（即時值，僅 Pro/Max 訂閱且 session 首個回應後才有）----
    rl = j.get("rate_limits") or {}
    r5 = rl.get("five_hour") or {}
    r5pct   = r5.get("used_percentage")
    r5reset = r5.get("resets_at")
    r7pct   = (rl.get("seven_day") or {}).get("used_percentage")

    # ---- 快取：git branch + transcript 增量累計（5 秒）----
    cache_file = os.path.join(tempfile.gettempdir(), "cc-statusline-%s-%s" % (CACHE_VER, sid))
    st = load_state(cache_file)
    fresh = st is not None and (time.time() - os.path.getmtime(cache_file)) < TTL
    if not fresh:
        if st is None:
            st = {"off": 0, "tp": tp or "", "branch": "", "g": {}}
        st["branch"] = git_branch(cwd, gitwt)
        if tp and os.path.exists(tp):
            try:
                scan_transcript(tp, st)
            except Exception:
                pass
        save_state(cache_file, st)

    branch = st["branch"]
    tin = sum(v[0] for v in st["g"].values())
    tcc = sum(v[1] for v in st["g"].values())
    tcr = sum(v[2] for v in st["g"].values())
    tout = sum(v[3] for v in st["g"].values())

    # ---- 計算 ----
    td = tin + tcc + tcr
    tot_hit = tcr * 100 // td if td > 0 else "-"
    sess_tok = tin + tcc + tcr + tout

    ctx_h  = human(ctx_tok)
    sess_h = human(sess_tok)
    cost_fmt = "$%.2f" % cost

    # ---- 顏色 ----
    R = "\033[0m"; DIM = "\033[2m"
    CYAN = "\033[36m"; GREEN = "\033[32m"; YELLOW = "\033[33m"; RED = "\033[31m"; MAG = "\033[35m"

    ctx_c = RED if ctx_pct >= 90 else YELLOW if ctx_pct >= 70 else GREEN

    def hit_color(h):   # 命中率越高越綠
        if not isinstance(h, int):
            return DIM
        return GREEN if h >= 80 else YELLOW if h >= 50 else RED

    def usage_color(p):  # 用量越高越紅
        return RED if p >= 80 else YELLOW if p >= 50 else GREEN

    cur_c = hit_color(cur_hit)
    tot_c = hit_color(tot_hit)

    # ---- rate limit：百分比取整、reset 倒數 ----
    have_rate = r5pct is not None
    g_rate = ""
    if have_rate:
        r5v = round(float(r5pct))
        r7v = round(float(r7pct)) if r7pct is not None else 0
        reset_str = "-"
        if r5reset is not None:
            diff = int(r5reset) - int(time.time())
            if diff < 0:
                diff = 0
            if diff >= 86400:
                reset_str = "%dd%dh" % (diff // 86400, (diff % 86400) // 3600)
            elif diff >= 3600:
                reset_str = "%dh%dm" % (diff // 3600, (diff % 3600) // 60)
            else:
                reset_str = "%dm" % (diff // 60)
        r5c = usage_color(r5v); r7c = usage_color(r7v)

    # ---- 組裝輸出 ----
    GAP = "  "
    BAR = DIM + "|" + R

    model_seg = (CYAN + model + DIM + "|" + R + CYAN + effort + R) if effort else (CYAN + model + R)
    g_model = "🤖 " + model_seg
    if have_rate:
        g_rate = (GAP + "🔋 " + r5c + str(r5v) + "%" + R + BAR + DIM + reset_str + R
                  + BAR + r7c + str(r7v) + "%" + R)
    g_branch = (GAP + "🌿 " + GREEN + branch + R) if branch else ""
    g_ctx   = GAP + "📊 " + ctx_h + BAR + ctx_c + str(ctx_pct) + "%" + R
    g_cache = GAP + "⚡ " + cur_c + str(cur_hit) + "%" + R + BAR + tot_c + str(tot_hit) + "%" + R
    g_token = GAP + "💰 " + MAG + sess_h + R + BAR + YELLOW + cost_fmt + R

    print(g_model + g_rate + g_branch + g_ctx + g_cache + g_token)


if __name__ == "__main__":
    main()
