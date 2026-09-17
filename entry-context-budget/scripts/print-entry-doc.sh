#!/usr/bin/env bash
# print-entry-doc.sh —— 把入口文档真排成 A4 PDF，报页数（可选层，不是门禁）
#
# 定位
#   技能核心（measure.py / guard.py）是纯标准库、不依赖外部程序。
#   本脚本是**可选层**：需要无头浏览器。它不进判据，也不许阻断任何流程。
#   用途有两个：
#     1) 给人一个能感觉到的刻度（几页纸）——token / 字节 人体感不到，页数能；
#     2) 把「排版开销」量出来：实排页数 − 算术页数 = 短行、表格、项目符号造成的行尾留白。
#
# 用法
#   print-entry-doc.sh                          # 自动发现 AGENTS.md / AGENT.md
#   print-entry-doc.sh SKILL.md docs/RULES.md   # 指定文件（可多个：入口文档不止一份时）
#   print-entry-doc.sh --staged                 # 排 git 暂存版（即将提交的那份）
#   print-entry-doc.sh --out DIR                # 输出目录（默认 <仓库>/.git/entry-doc-pdf）
#   print-entry-doc.sh --quiet                  # 只报结果行（适合挂进钩子）
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
TARGETS=()
KEEP="${AGENT_DOC_PDF_KEEP:-10}"

while [ $# -gt 0 ]; do
  case "$1" in
    --staged) STAGED=1; shift ;;
    --quiet)  QUIET=1; shift ;;
    --out)    OUT_DIR="${2:-}"; shift 2 ;;
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

# ── 3. markdown → HTML（够看即可，不引第三方解析器）──────────────────
md2html() {  # $1=md $2=html
  python3 - "$1" "$2" <<'PY'
import html, re, sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
out, in_code, in_table = [], False, False

def inline(s):
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"(?<![\[\w])\[([^\]]+)\]\(([^)]+)\)", r"<span class=link>\1</span>", s)
    return s

def flush_table():
    global in_table
    if in_table:
        out.append("</pre>"); in_table = False

for raw in lines:
    if re.match(r"^\s*```", raw):
        flush_table()
        out.append("</pre>" if in_code else "<pre class=code>")
        in_code = not in_code
        continue
    if in_code:
        out.append(html.escape(raw)); continue
    if raw.strip().startswith("|") and "|" in raw:
        if not in_table:
            out.append("<pre class=table>"); in_table = True
        out.append(html.escape(raw)); continue
    flush_table()
    if not raw.strip():
        out.append(""); continue
    m = re.match(r"^(#{1,6})\s+(.*)$", raw)
    if m:
        n = len(m.group(1))
        out.append("<h%d>%s</h%d>" % (n, inline(html.escape(m.group(2))), n)); continue
    if re.match(r"^\s*[-*+]\s+", raw):
        out.append("<li>%s</li>" % inline(re.sub(r"^\s*[-*+]\s+", "", html.escape(raw)))); continue
    if re.match(r"^\s*\d+[.)]\s+", raw):
        out.append("<li>%s</li>" % inline(re.sub(r"^\s*\d+[.)]\s+", "", html.escape(raw)))); continue
    if raw.lstrip().startswith(">"):
        out.append("<blockquote>%s</blockquote>" % inline(html.escape(raw.lstrip()[1:].strip()))); continue
    if re.match(r"^\s*(-{3,}|\*{3,})\s*$", raw):
        out.append("<hr>"); continue
    out.append("<p>%s</p>" % inline(html.escape(raw)))
flush_table()
if in_code:
    out.append("</pre>")

# 页数绑定在这份 CSS 上：换字号/行距/边距，页数就变。所以「标准排版」必须写死在一处，
# 跟阈值同一个纪律——两种排版下的页数不是同一把尺子，不可互相比较。
doc = """<!doctype html><html><head><meta charset="utf-8"><style>
@page { size: A4; margin: 22mm 20mm; }
body { font-family: "Noto Sans CJK SC","Source Han Sans SC",system-ui,sans-serif;
       font-size: 10.5pt; line-height: 1.6; color: #111; }
h1,h2,h3,h4 { line-height: 1.3; margin: 1.1em 0 .45em; page-break-after: avoid; }
h1 { font-size: 17pt; border-bottom: 1px solid #c9c9c9; padding-bottom: .25em; }
h2 { font-size: 13.5pt; } h3 { font-size: 12pt; } h4 { font-size: 11pt; }
p { margin: .45em 0; }
li { margin: .18em 0 0 1.4em; }
pre { background: #f6f6f6; padding: .5em .7em; font-size: 9pt; line-height: 1.45;
      white-space: pre-wrap; word-break: break-word; page-break-inside: avoid; }
pre.code, pre.table { border-left: 2px solid #bfbfbf; }
code { font-size: .93em; background: #f0f0f0; padding: 0 .18em; }
blockquote { margin: .5em 0; padding: .1em .9em; border-left: 3px solid #d0d0d0; color: #444; }
hr { border: 0; border-top: 1px solid #ddd; margin: 1em 0; }
.link { text-decoration: underline; }
</style></head><body>%s</body></html>""" % "\n".join(out)
open(sys.argv[2], "w", encoding="utf-8").write(doc)
PY
}

# ── 4. 逐个渲染 ──────────────────────────────────────────────────────
render_one() {
  local target="$1"
  local abs tmp pdf base stamp out note="工作区版" root rel

  abs="$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")"
  [ -e "$abs" ] || { say "$target 不存在，跳过"; return 0; }

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/entry-doc.XXXXXX")"
  if [ "$STAGED" = 1 ]; then
    root="$(git -C "$(dirname "$abs")" rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$root" ]; then
      rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$abs" "$root" 2>/dev/null)"
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

  md2html "$tmp/doc.md" "$tmp/doc.html"
  if [ ! -s "$tmp/doc.html" ]; then rm -rf "$tmp"; say "$target HTML 生成失败，跳过"; return 0; fi

  root="$(git -C "$(dirname "$abs")" rev-parse --show-toplevel 2>/dev/null)"
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

  if ! timeout 25s "$CHROME" --headless --no-sandbox --disable-gpu --disable-dev-shm-usage \
        --no-pdf-header-footer --print-to-pdf="$pdf" "file://$tmp/doc.html" >/dev/null 2>&1; then
    rm -rf "$tmp"; say "$target 排版失败或超时 → 跳过，不影响任何流程"; return 0
  fi
  [ -s "$pdf" ] || { rm -rf "$tmp"; say "$target 排版产出为空 → 跳过"; return 0; }

  python3 - "$pdf" "$tmp/doc.md" "$note" "$QUIET" "$base" <<'PY'
import glob, os, re, sys
pdf, md, note, quiet, base = sys.argv[1:6]
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
print("📄 %s（%s）实排 %d 页｜算术 %.1f 页｜排版开销 %+.1f 页"
      % (os.path.basename(pdf), note, pages, est, pages - est))
if not quiet:
    print("   路径：%s" % pdf)
    print("   注：算术页数是纯体积模型；实排多出来的部分是短行、表格、项目符号造成的行尾留白。")
PY
  rm -rf "$tmp"

  # 滚动保留：每个文档名只留最近 $KEEP 份（一个 PDF 内嵌中文字体约 600KB，不清理会攒体积）
  if [ "$KEEP" -gt 0 ] 2>/dev/null; then
    ls -1t "$dest/${base}-"*.pdf 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
      rm -f "$old"
    done
  fi
  return 0
}

for t in "${TARGETS[@]}"; do render_one "$t"; done
exit 0
