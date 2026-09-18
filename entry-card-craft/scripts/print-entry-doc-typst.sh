#!/usr/bin/env bash
# print-entry-doc-typst.sh —— 使用 Typst 排版入口文档为 PDF（替代无头浏览器方案）
#
# 定位
#   本脚本是 print-entry-doc.sh 的 Typst 替代方案，依赖 Typst 编译器而非无头浏览器。
#   同样用于页面终审：生成 PDF 作为判决依据，不阻断流程。
#
# 用法
#   print-entry-doc-typst.sh                          # 自动发现 AGENTS.md / AGENT.md
#   print-entry-doc-typst.sh SKILL.md docs/RULES.md   # 指定文件
#   print-entry-doc-typst.sh --out DIR                # 输出目录（默认 <仓库>/.git/entry-doc-pdf）
#   print-entry-doc-typst.sh --quiet                  # 只报结果行
#
# 排版档（两档，页数以标准档为准）
#   std（默认）：标准排版；一切页数按它计，页数间可比。
#   fit（末页合并）：自动启用，不需要手动指定。标准排版下末页只剩一点点时，
#       用 fit 档（收紧边距/字号/行距，多容纳约三成）再排一次，**真少一页**才采用。
#       专治「第二页只有一行」——简历不给人留一行空白页。产出行的档位标注为「末页合并」。
#
# 退出码
#   0 = 完成。**包括「没排成」的所有情况**（缺 Typst / 超时 / 渲染失败）——
#       这类情况只打印一行说明，绝不阻断调用方。
#   1 = 用法错误。
#
# 依赖
#   bash + python3（标准库）；Typst 编译器（typst 命令）。
#   字体：需要 Noto Serif CJK SC（正文）和 Noto Sans CJK SC（标题），
#         否则 Typst 会回退到默认字体，可能影响排版效果。
#
# 输出位置为什么选 .git/：不进版本控制、不产生二进制变更、不用动 .gitignore。
# 关掉渲染：AGENT_DOC_PRINT_OFF=1（或干脆不装钩子）。

set -uo pipefail

TAG="[print-typst]"
QUIET=0
OUT_DIR=""
TARGETS=()
KEEP="${AGENT_DOC_PDF_KEEP:-10}"

while [ $# -gt 0 ]; do
  case "$1" in
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

# ── 2. 找 Typst 编译器 ─────────────────────────────────────────────────
find_typst() {
  local t
  for t in "${TYPST_PATH:-}" \
           "$(command -v typst 2>/dev/null)" \
           /usr/local/bin/typst \
           /usr/bin/typst; do
    [ -n "$t" ] && [ -x "$t" ] && { echo "$t"; return 0; }
  done
  return 1
}
TYPST="$(find_typst)" || {
  say "没找到 Typst 编译器（可设 TYPST_PATH）→ 本步跳过，不影响任何流程"
  exit 0
}

# ── 3. 检查 Typst 版本 ─────────────────────────────────────────────────
TYPST_VERSION="$("$TYPST" --version 2>/dev/null | head -1)" || {
  say "Typst 版本检测失败 → 本步跳过"
  exit 0
}
say "使用 $TYPST_VERSION"

# ── 4. 字体检测 ────────────────────────────────────────────────────────
# Typst 需要字体文件。我们检查是否有所需字体，如果没有，给出警告。
check_font() {
  local font_name="$1"
  # 使用 typst fonts 命令列出可用字体
  if "$TYPST" fonts 2>/dev/null | grep -qi "$font_name"; then
    return 0
  else
    return 1
  fi
}
if ! check_font "Noto Serif CJK SC"; then
  say "警告：未找到 Noto Serif CJK SC 字体，正文可能使用默认字体"
fi
if ! check_font "Noto Sans CJK SC"; then
  say "警告：未找到 Noto Sans CJK SC 字体，标题可能使用默认字体"
fi

# ── 5. Markdown → Typst 转换函数 ────────────────────────────────────────
md2typst() {  # $1=md $2=typ $3=排版档（std|fit）
  local script_dir="$(cd "$(dirname "$0")" && pwd)"
  python3 "$script_dir/md2typst.py" "$1" "$2" "${3:-std}"
}

# ── 6. 数 PDF 页数（复用原脚本逻辑）────────────────────────────────────
pdf_pages() {
  python3 -c 'import re,sys;print(len(re.findall(rb"/Type\s*/Page(?![s])", open(sys.argv[1],"rb").read())))' "$1" 2>/dev/null
}

# ── 7. 渲染函数 ────────────────────────────────────────────────────────
render_one() {
  local target="$1"
  local abs tmp typ pdf base stamp out note="工作区版" root rel

  abs="$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")"
  [ -e "$abs" ] || { say "$target 不存在，跳过"; return 0; }

  # 仓库内相对路径
  root="$(git -C "$(dirname "$abs")" rev-parse --show-toplevel 2>/dev/null)"
  rel=""
  [ -n "$root" ] && rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$abs" "$root" 2>/dev/null)"

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/entry-doc-typst.XXXXXX")"
  cp "$abs" "$tmp/doc.md" 2>/dev/null || { rm -rf "$tmp"; say "$target 读不到，跳过"; return 0; }

  # 输出目录
  if [ -n "$OUT_DIR" ]; then
    dest="$OUT_DIR"
  elif [ -n "$root" ] && [ -d "$root/.git" ]; then
    dest="$root/.git/entry-doc-pdf"
  else
    dest="$(dirname "$abs")/.entry-doc-pdf"
  fi
  mkdir -p "$dest" 2>/dev/null || { rm -rf "$tmp"; say "输出目录建不了：$dest，跳过"; return 0; }

  # 文件名
  if [ -n "$root" ] && [ -n "${rel:-}" ]; then
    base="$(printf '%s' "${rel%.md}" | tr '/' '-')"
  else
    base="$(basename "$abs" .md)"
  fi
  stamp="$(date +%Y%m%d-%H%M%S)"
  pdf="$dest/${base}-${stamp}.pdf"

  # 转换为 Typst
  md2typst "$tmp/doc.md" "$tmp/doc.typ" std
  if [ ! -s "$tmp/doc.typ" ]; then
    rm -rf "$tmp"; say "$target Typst 转换失败，跳过"; return 0
  fi

  # 编译为 PDF
  if ! timeout 25s "$TYPST" compile "$tmp/doc.typ" "$pdf" >/dev/null 2>&1; then
    rm -rf "$tmp"; say "$target Typst 编译失败或超时 → 跳过，不影响任何流程"
    return 0
  fi

  [ -s "$pdf" ] || { rm -rf "$tmp"; say "$target PDF 生成失败，跳过"; return 0; }

  # 末页合并：标准排版下末页只剩一点点时，改用 fit 档再排一次
  local p_std p_fit
  p_std="$(pdf_pages "$pdf")"
  if [ -n "$p_std" ] && [ "$p_std" -gt 1 ] 2>/dev/null; then
    # 生成 fit 档的 Typst 文件
    md2typst "$tmp/doc.md" "$tmp/fit.typ" fit
    if [ -s "$tmp/fit.typ" ]; then
      if timeout 25s "$TYPST" compile "$tmp/fit.typ" "$tmp/fit.pdf" >/dev/null 2>&1; then
        p_fit="$(pdf_pages "$tmp/fit.pdf")"
        if [ -n "$p_fit" ] && [ "$p_fit" = "$((p_std - 1))" ]; then
          mv -f "$tmp/fit.pdf" "$pdf"; note="$note·末页合并"
          [ "$QUIET" = 1 ] || echo "$TAG   $target：末页收进前页（$p_std 页 → $p_fit 页，排版档 fit）"
        fi
      fi
    fi
  fi

  # 输出统计信息
  python3 - "$pdf" "$tmp/doc.md" "$note" "$QUIET" "$base" <<'PY'
import re, sys
pdf, md, note, quiet, base = sys.argv[1:6]
raw = open(pdf, "rb").read()
pages = len(re.findall(rb"/Type\s*/Page(?![s])", raw))
text = open(md, encoding="utf-8").read()
CJK = r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uff65\u2018-\u201d\u2013\u2014]"
cjk = len(re.findall(CJK, text))
no_cjk = re.sub(CJK, "", text)
ascii_chars = len(re.sub(r"\s", "", no_cjk))
est = (cjk + ascii_chars * 0.5) / 1400.0
print("📄 %s（%s）实排 %d 页｜算术 %.1f 页｜排版开销 %+.1f 页"
      % (base, note, pages, est, pages - est))
if not quiet:
    print("   路径：%s" % pdf)
    print("   注：算术页数是纯体积模型；实排多出来的部分是短行、表格、项目符号造成的行尾留白。")
PY

  rm -rf "$tmp"

  # 保留策略：滚动保留最近 $KEEP 份
  if [ "$KEEP" -gt 0 ] 2>/dev/null; then
    ls -1t "$dest/${base}-"*.pdf 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
      rm -f "$old"
    done
  fi
  return 0
}

# ── 8. 主循环 ──────────────────────────────────────────────────────────
for t in "${TARGETS[@]}"; do render_one "$t"; done
exit 0