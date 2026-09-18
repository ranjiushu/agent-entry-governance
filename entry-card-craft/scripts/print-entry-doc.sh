#!/usr/bin/env bash
# print-entry-doc.sh —— 把入口文档真排成 A4 PDF：页面终审的判决依据（不阻断流程）
#
# 定位
#   技能核心（measure.py / guard.py）是纯标准库、不依赖外部程序。
#   本脚本是**判决层**：终审读的是它排出来的页面——token 与字节人感觉不到，页数能。
#   它不进任何阻断路径（渲染要 1–2 秒、依赖无头浏览器），但绝不因此次要：
#   缺依赖时明说「这次没看到页面」，交付据此标注「未经页面终审」；静默跳过才是错的。
#   两个用途：
#     1) 给人一个能感觉到的刻度（几页纸）；
#     2) 把「排版开销」量出来：实排页数 − 算术页数 = 短行、表格、项目符号造成的行尾留白。
#
# 用法
#   print-entry-doc.sh                          # 自动发现 AGENTS.md / AGENT.md
#   print-entry-doc.sh SKILL.md docs/RULES.md   # 指定文件（可多个：入口文档不止一份时）
#   print-entry-doc.sh --staged                 # 排 git 暂存版（即将提交的那份）
#   print-entry-doc.sh --out DIR                # 输出目录（默认 <仓库>/.git/entry-doc-pdf）
#   print-entry-doc.sh --archive DIR            # 归档目录：同一文档名只留最新一份，旧的移到这里
#                                               #   不给 --archive 时退化为「保留最近 KEEP 份」
#   print-entry-doc.sh --quiet                  # 只报结果行（适合挂进钩子）
#
# 排版档（两档，页数以标准档为准）
#   std（默认）：标准排版；一切页数按它计，页数间可比。
#   fit（末页合并）：自动启用，不需要手动指定。标准排版下末页只剩一点点时，
#       用 fit 档（收紧边距/字号/行距，多容纳约三成）再排一次，**真少一页**才采用。
#       专治「第二页只有一行」——简历不给人留一行空白页。产出行的档位标注为「末页合并」。
#
# 退出码
#   0 = 完成。**包括「没排成」的所有情况**（缺浏览器 / 超时 / 渲染失败）——
#       这类情况只打印一行说明，绝不阻断调用方（挂进 post-commit 不会卡任何东西）。
#   1 = 用法错误。
#
# 依赖
#   bash + python3（标准库）；无头浏览器由 CHROME_PATH 指定或自动探测。
#   探测**必须实际执行一次**（--version）：架构不匹配的二进制存在但跑不起来，
#   只看文件在不在会把它当成可用。
#
# 输出位置为什么选 .git/：不进版本控制、不产生二进制变更、不用动 .gitignore。
# 关掉渲染：AGENT_DOC_PRINT_OFF=1（或干脆不装钩子）。

set -uo pipefail

TAG="[print]"
QUIET=0
STAGED=0
OUT_DIR=""
ARCHIVE_DIR=""
TARGETS=()
KEEP="${AGENT_DOC_PDF_KEEP:-10}"                 # 无 --archive 时的滚动保留份数
ARCHIVE_KEEP="${AGENT_DOC_PDF_ARCHIVE_KEEP:-30}"  # 归档目录每个文档名的封顶份数（0 = 不限）

while [ $# -gt 0 ]; do
  case "$1" in
    --staged) STAGED=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    --out)    OUT_DIR="${2:-}"; shift 2 ;;
    --archive) ARCHIVE_DIR="${2:-}"; shift 2 ;;
    -h|--help) awk 'NR==1{next} /^#/{print; next} {exit}' "$0"; exit 0 ;;
    -*) echo "$TAG 未知参数：$1" >&2; exit 1 ;;
    *)  TARGETS+=("$1"); shift ;;
  esac
done

[ "${AGENT_DOC_PRINT_OFF:-0}" = 1 ] && exit 0

say() { [ "$QUIET" = 1 ] || echo "$TAG $*"; }

# ── 1. 找文件：没给就自动发现 ─────────────────────────────────────────
if [ ${#TARGETS[@]} -eq 0 ]; then
  for n in AGENTS.md AGENT.md; do [ -f "$n" ] && TARGETS+=("$n"); done
fi
if [ ${#TARGETS[@]} -eq 0 ]; then
  say "未找到入口文档，跳过"
  exit 0
fi

# ── 2. 找浏览器（必须实跑一次，排除架构不匹配）────────────────────────
find_chrome() {
  local c
  for c in "${CHROME_PATH:-}" \
           /workspace/chrome/arm64/chrome-headless-shell-linux-arm64/chrome-headless-shell \
           /workspace/assets/chrome/chrome-headless-shell-linux64/chrome-headless-shell \
           "$(command -v google-chrome 2>/dev/null)" \
           "$(command -v chromium 2>/dev/null)" \
           "$(command -v chromium-browser 2>/dev/null)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    if timeout 10s "$c" --version >/dev/null 2>&1; then echo "$c"; return 0; fi
  done
  return 1
}
CHROME="$(find_chrome)" || {
  say "没找到可用的无头浏览器（可设 CHROME_PATH）→ 本步跳过，不影响任何流程"
  exit 0
}

# ── 3. markdown → HTML（零第三方依赖；块级结构：代码 / 引用 / 表格 / 列表 / 标题 / 段落）──
# 三条纪律（改这里前先读）：
#   ① 表格必须渲染成 <table>（不是等宽 pre）——pre 是引用/代码的外观，表格会因此"看起来无法渲染"；
#   ② 引用块整体合并后**递归**渲染内部 —— 于是引用里嵌表格、嵌列表都能正常出；
#   ③ 列表项必须有 <ul>/<ol> 包裹 —— 否则项目符号不显示，列表塌成一段段文字。
md2html() {  # $1=md $2=html $3=排版档（std|fit）
  python3 - "$1" "$2" "${3:-std}" <<'PY'
import html, re, sys

QUOTE = re.compile(r"^\s*>\s?")
UL = re.compile(r"^\s*[-*+]\s+")
OL = re.compile(r"^\s*\d+[.)]\s+")
HR = re.compile(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$")
FENCE = re.compile(r"^\s*```")
HEAD = re.compile(r"^(#{1,6})\s+(.*)$")


def inline(s):
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"<span class=link>\1</span>", s)
    return s


def esc(s):
    return inline(html.escape(s))


def strip_q(line):
    return QUOTE.sub("", line, count=1)


def is_sep(line):
    """表格分隔行：只由 | - : 与空白组成，且含 >=2 个短横。"""
    t = line.strip()
    return bool(t) and set(t) <= set("|-: \t") and t.count("-") >= 2


def cells(line):
    r = line.strip()
    r = r[1:] if r.startswith("|") else r
    r = r[:-1] if r.endswith("|") else r
    return [c.strip() for c in r.split("|")]


def take_table(lines, i):
    head, rows = cells(lines[i]), []
    i += 2
    while i < len(lines) and lines[i].strip() and "|" in lines[i]:
        rows.append(cells(lines[i]))
        i += 1
    t = ["<table><thead><tr>%s</tr></thead><tbody>"
         % "".join("<th>%s</th>" % esc(c) for c in head)]
    for r in rows:
        t.append("<tr>%s</tr>" % "".join("<td>%s</td>" % esc(c) for c in r))
    t.append("</tbody></table>")
    return "".join(t), i


def render(lines):
    out, i, n = [], 0, len(lines)
    while i < n:
        raw = lines[i]
        if FENCE.match(raw):                                   # 代码块
            i += 1
            buf = []
            while i < n and not FENCE.match(lines[i]):
                buf.append(html.escape(lines[i]))
                i += 1
            i += 1
            out.append("<pre class=code>%s</pre>" % "\n".join(buf))
            continue
        if QUOTE.match(raw):                                   # 引用块：合并 + 内部递归
            buf = []
            while i < n and (QUOTE.match(lines[i]) or (buf and not lines[i].strip())):
                buf.append(strip_q(lines[i]) if QUOTE.match(lines[i]) else "")
                i += 1
            out.append("<blockquote>%s</blockquote>" % render(buf))
            continue
        if "|" in raw and i + 1 < n and is_sep(lines[i + 1]):   # 表格（含引用内的）
            t, i = take_table(lines, i)
            out.append(t)
            continue
        if UL.match(raw) or OL.match(raw):                      # 列表
            pat = UL if UL.match(raw) else OL
            tag = "ul" if pat is UL else "ol"
            items = []
            while i < n and pat.match(lines[i]):
                item = pat.sub("", lines[i], count=1)
                i += 1
                while (i < n and lines[i].strip() and not pat.match(lines[i])
                       and not FENCE.match(lines[i]) and not QUOTE.match(lines[i])
                       and not HEAD.match(lines[i]) and "|" not in lines[i]):
                    item += " " + lines[i].strip()
                    i += 1
                items.append("<li>%s</li>" % esc(item))
            out.append("<%s>%s</%s>" % (tag, "".join(items), tag))
            continue
        if HR.match(raw):
            out.append("<hr>")
            i += 1
            continue
        m = HEAD.match(raw)
        if m:
            lv = len(m.group(1))
            out.append("<h%d>%s</h%d>" % (lv, esc(m.group(2)), lv))
            i += 1
            continue
        if not raw.strip():
            i += 1
            continue
        buf = [raw.strip()]                                     # 段落：合并连续普通行
        i += 1
        while (i < n and lines[i].strip() and not FENCE.match(lines[i])
               and not QUOTE.match(lines[i]) and not HEAD.match(lines[i])
               and not UL.match(lines[i]) and not OL.match(lines[i])
               and not HR.match(lines[i]) and "|" not in lines[i]):
            buf.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % esc(" ".join(buf)))
    return "\n".join(out)


body = render(open(sys.argv[1], encoding="utf-8").read().split("\n"))

# 页数绑定在这份 CSS 上：换字体/字号/行距/边距，页数就变。所以「标准排版」必须写死在一处，
# 跟阈值同一个纪律——两种排版下的页数不是同一把尺子，不可互相比较。
# 字体与 sandbox-gui/tools/md2pdf.py（工作区里对标 Typora 输出的那份）对齐：
# 正文衬线（Georgia + Noto Serif CJK SC／思源宋体），标题黑体，代码等宽。
#
# 两档排版，只有两个用途：
#   std（默认，标准排版）：一切页数以此为准，页数间可比。
#   fit（末页合并）：仅当标准排版下**末页只剩很少内容**（收一收就能进前一页）时启用，
#       专治「第二页只有一行」——简历不给人留一行空白页。fit 收紧边距/字号/行距（多容纳
#       约三成，收益即末页那点内容的去向）；吞不下就说明该改内容，不该再压格式。
#       产出行会标出用的哪档；fit 只在「页数真少一页」时才采用。
tier = sys.argv[3] if len(sys.argv) > 3 else "std"
if tier == "fit":
    V = dict(margin="16mm 17mm", fs="9.8pt", lh="1.42", pm=".28em", lim=".09em",
             ulm=".18em 0 .28em 1.15em", hm=".75em 0 .3em", tbl="9.2pt", pre="8.4pt",
             bqm=".35em 0")
else:
    V = dict(margin="22mm 20mm", fs="10.5pt", lh="1.7", pm=".45em", lim=".16em",
             ulm=".3em 0 .4em 1.25em", hm="1.1em 0 .45em", tbl="10pt", pre="9pt",
             bqm=".5em 0")

css = """@page { size: A4; margin: @@MARGIN@@; }
body { font-family: Georgia,"Palatino Linotype","Book Antiqua",Palatino,
                     "Noto Serif CJK SC","Source Han Serif SC","SimSun","STSong",serif;
       font-size: @@FS@@; line-height: @@LH@@; color: #111; }
h1,h2,h3,h4 { font-family: -apple-system,"Segoe UI","Noto Sans CJK SC","PingFang SC",
                     Helvetica,Arial,sans-serif;
              line-height: 1.3; margin: @@HM@@; page-break-after: avoid; }
h1 { font-size: 17pt; border-bottom: 1px solid #c9c9c9; padding-bottom: .25em; }
h2 { font-size: 13.5pt; } h3 { font-size: 12pt; } h4 { font-size: 11pt; }
p { margin: @@PM@@ 0; }
ul, ol { margin: @@ULM@@; padding: 0; }
li { margin: @@LIM@@ 0; }
pre { background: #f6f6f6; padding: .5em .7em; font-size: @@PRE@@; line-height: 1.45;
      white-space: pre-wrap; word-break: break-word; page-break-inside: avoid; }
pre.code { border-left: 2px solid #bfbfbf; }
table { border-collapse: collapse; margin: .55em 0; width: 100%%; font-size: @@TBL@@; }
th, td { border: 1px solid #cfcfcf; padding: .25em .5em; text-align: left; vertical-align: top; }
thead th { background: #f2f2f2; }
tbody tr:nth-child(even) td { background: #fafafa; }
tr { page-break-inside: avoid; }
blockquote table { width: auto; font-size: 9.5pt; }
code { font-size: .93em; background: #f0f0f0; padding: 0 .18em; }
blockquote { margin: @@BQM@@; padding: .1em .9em; border-left: 3px solid #d0d0d0; color: #444; }
hr { border: 0; border-top: 1px solid #ddd; margin: 1em 0; }
.link { text-decoration: underline; }
"""
for k, v in V.items():
    css = css.replace("@@%s@@" % k.upper(), v)
doc = ('<!doctype html><html><head><meta charset="utf-8"><style>' + css
       + '</style></head><body>%s</body></html>') % body
open(sys.argv[2], "w", encoding="utf-8").write(doc)
PY
}

# 数 PDF 里的页对象（stdlib，不引第三方依赖）
pdf_pages() {
  python3 -c 'import re,sys;print(len(re.findall(rb"/Type\s*/Page(?![s])", open(sys.argv[1],"rb").read())))' "$1" 2>/dev/null
}

# 用指定排版档渲一次，产出写到 $2
render_to() {  # $1=md $2=pdf $3=tier
  local html="${2%.pdf}.html"
  md2html "$1" "$html" "$3" || return 1
  [ -s "$html" ] || return 1
  timeout 25s "$CHROME" --headless --no-sandbox --disable-gpu --disable-dev-shm-usage \
      --no-pdf-header-footer --print-to-pdf="$2" "file://$html" >/dev/null 2>&1 || return 1
  [ -s "$2" ]
}

# ── 4. 逐个渲染 ──────────────────────────────────────────────────────
render_one() {
  local target="$1"
  local abs tmp pdf base stamp out note="工作区版" root rel

  abs="$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")"
  [ -e "$abs" ] || { say "$target 不存在，跳过"; return 0; }

  # 仓库内相对路径：既用于取暂存版，也用于给产出文件命名
  # （一个仓库里常有多份同名入口文档，如两个 SKILL.md，只按 basename 命名会撞车）
  root="$(git -C "$(dirname "$abs")" rev-parse --show-toplevel 2>/dev/null)"
  rel=""
  [ -n "$root" ] && rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$abs" "$root" 2>/dev/null)"

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/entry-doc.XXXXXX")"
  if [ "$STAGED" = 1 ]; then
    if [ -n "$root" ]; then
      if git -C "$root" show ":$rel" > "$tmp/doc.md" 2>/dev/null; then
        note="暂存版"
      else
        cp "$abs" "$tmp/doc.md" 2>/dev/null || { rm -rf "$tmp"; say "$target 读不到，跳过"; return 0; }
        note="工作区版（暂存区无此文件）"
      fi
    else
      cp "$abs" "$tmp/doc.md" 2>/dev/null || { rm -rf "$tmp"; return 0; }
    fi
  else
    cp "$abs" "$tmp/doc.md" 2>/dev/null || { rm -rf "$tmp"; return 0; }
  fi

  md2html "$tmp/doc.md" "$tmp/doc.html" std
  if [ ! -s "$tmp/doc.html" ]; then rm -rf "$tmp"; say "$target HTML 生成失败，跳过"; return 0; fi

  if [ -n "$OUT_DIR" ]; then
    dest="$OUT_DIR"
  elif [ -n "$root" ] && [ -d "$root/.git" ]; then
    dest="$root/.git/entry-doc-pdf"
  else
    dest="$(dirname "$abs")/.entry-doc-pdf"
  fi
  mkdir -p "$dest" 2>/dev/null || { rm -rf "$tmp"; say "输出目录建不了：$dest，跳过"; return 0; }

  # 文件名带路径信息：一个仓库里可能有多份同名入口文档（如两个 SKILL.md）
  if [ -n "$root" ] && [ -n "${rel:-}" ]; then
    base="$(printf '%s' "${rel%.md}" | tr '/' '-')"
  else
    base="$(basename "$abs" .md)"
  fi
  stamp="$(date +%Y%m%d-%H%M%S)"
  pdf="$dest/${base}-${stamp}.pdf"

  if ! render_to "$tmp/doc.md" "$pdf" std; then
    rm -rf "$tmp"; say "$target 排版失败或超时 → 跳过，不影响任何流程"; return 0
  fi

  # 末页合并：标准排版下末页只剩一点点时，改用 fit 档再排一次；
  # 只有「真少一页」才采用（吞不下就是内容该改，不是格式该再压）。
  local p_std p_fit
  p_std="$(pdf_pages "$pdf")"
  if [ -n "$p_std" ] && [ "$p_std" -gt 1 ] 2>/dev/null; then
    if render_to "$tmp/doc.md" "$tmp/fit.pdf" fit; then
      p_fit="$(pdf_pages "$tmp/fit.pdf")"
      if [ -n "$p_fit" ] && [ "$p_fit" = "$((p_std - 1))" ]; then
        mv -f "$tmp/fit.pdf" "$pdf"; note="$note·末页合并"
        [ "$QUIET" = 1 ] || echo "$TAG   $target：末页收进前页（$p_std 页 → $p_fit 页，排版档 fit）"
      fi
    fi
  fi

  python3 - "$pdf" "$tmp/doc.md" "$note" "$QUIET" "$base" <<'PY'
import glob, os, re, sys
pdf, md, note, quiet, base = sys.argv[1:6]


def _emit(s):
    """按 stdout 能否编码把装饰符号降级为 ASCII（手法同 measure.safe_text）。
    Windows GBK 控制台编不了 📄 会抛 UnicodeEncodeError，把结果行整份丢掉——
    恰好是最该看到结论的时候。打印层不能 import measure（渲染器会被复制进目标仓库
    独立运行，不许依赖别的成员），所以自备一份；两边要改一起改。"""
    try:
        s.encode(getattr(sys.stdout, "encoding", None) or "ascii")
        return s
    except (UnicodeEncodeError, LookupError):
        return s.replace("📄", "[pdf]")

raw = open(pdf, "rb").read()
pages = len(re.findall(rb"/Type\s*/Page(?![s])", raw))
text = open(md, encoding="utf-8").read()
CJK = r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uff65\u2018-\u201d\u2013\u2014]"
cjk = len(re.findall(CJK, text))
# 注意：必须先剔除 CJK 再去空白。写成一趟 re.sub(CJK + r"\s", ...) 是错的——
# CJK 串末尾自带 "]", 拼接后 \s 落在字符类**外面**，只会删掉「CJK+空白」的成对组合，
# 于是 ASCII 字数被高估（实测把 2.1 页估成 2.7 页）。这类 bug 静默无声。
no_cjk = re.sub(CJK, "", text)
ascii_chars = len(re.sub(r"\s", "", no_cjk))
est = (cjk + ascii_chars * 0.5) / 1400.0        # 每页 ≈ 1400 全角等效字符（密排）
print(_emit("📄 %s（%s）实排 %d 页｜算术 %.1f 页｜排版开销 %+.1f 页"
      % (os.path.basename(pdf), note, pages, est, pages - est)))
if not quiet:
    print(_emit("   路径：%s" % pdf))
    print("   注：算术页数是纯体积模型；实排多出来的部分是短行、表格、项目符号造成的行尾留白。")
PY
  rm -rf "$tmp"

  # 保留策略
  #   给了 --archive：产出位只留最新一份，旧的移进归档（归档再按 ARCHIVE_KEEP 封顶）
  #   没给：退化为滚动保留最近 $KEEP 份（一个 PDF 内嵌中文字体约 600KB，不清理会攒体积）
  if [ -n "$ARCHIVE_DIR" ]; then
    ls -1t "$dest/${base}-"*.pdf 2>/dev/null | tail -n +2 | while read -r old; do
      if mkdir -p "$ARCHIVE_DIR" 2>/dev/null && mv -f "$old" "$ARCHIVE_DIR/" 2>/dev/null; then
        [ "$QUIET" = 1 ] || echo "$TAG   归档：$(basename "$old") → $ARCHIVE_DIR"
      fi
    done
    if [ "$ARCHIVE_KEEP" -gt 0 ] 2>/dev/null; then
      ls -1t "$ARCHIVE_DIR/${base}-"*.pdf 2>/dev/null | tail -n +"$((ARCHIVE_KEEP + 1))" | while read -r gone; do
        rm -f "$gone"
      done
    fi
  elif [ "$KEEP" -gt 0 ] 2>/dev/null; then
    ls -1t "$dest/${base}-"*.pdf 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
      rm -f "$old"
    done
  fi
  return 0
}

for t in "${TARGETS[@]}"; do render_one "$t"; done
exit 0
