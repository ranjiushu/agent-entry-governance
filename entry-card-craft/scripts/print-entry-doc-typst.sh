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
#   print-entry-doc-typst.sh --archive DIR            # 归档目录：同一文档名只留最新一份，旧的移到这里
#                                                     #   不给 --archive 时退化为「保留最近 KEEP 份」
#   print-entry-doc-typst.sh --quiet                  # 只报结果行（适合挂进钩子）
#   print-entry-doc-typst.sh --fetch-typst            # 只拉取钉死的 Typst 到缓存，不排版
#   print-entry-doc-typst.sh --images [--ppi N]       # 查看模式：除 PDF 外再导出逐页图片，
#                                                     #   并写 <输出目录>/INDEX.md 用 markdown 引用它们
#                                                     #   （--ppi 默认 140，A4 约 1160 px 宽）
#
# 排版档（两档，页数以标准档为准）
#   std（默认）：标准排版；一切页数按它计，页数间可比。
#   fit（末页合并）：自动启用，不需要手动指定。标准排版下末页只剩一点点时，
#       用 fit 档（收紧边距/字号/行距，多容纳约三成）再排一次，**真少一页**才采用。
#       专治「第二页只有一行」——简历不给人留一行空白页。产出行的档位标注为「末页合并」。
#
# 查看模式（--images）
#   状态：实验件 —— 到 2026-09-18 只在 Linux + Typst 0.15.1 上验证过；参数名与产出布局可能调。
#   给人、也给能读图的 agent 看页面：把**已经选定的那一档**（std 或 fit）再编译一遍导出 PNG
#   （Typst 直接出图，不需要额外光栅器），然后写一份 INDEX.md 用相对路径引用每页图片。
#   判页数的机制一点没变，图片与 PDF 同档同页——看页面和打印裁决不会打架。
#   图片是给人看的二进制：默认落在 PDF 旁边（不进版本控制），按文档名滚动覆盖，不累积。
#   后端限 Typst；引擎不可用时显式说明，不静默跳过。
#
# 退出码
#   0 = 完成。**包括「没排成」的所有情况**（缺 Typst / 超时 / 渲染失败）——
#       这类情况只打印一行说明，绝不阻断调用方。
#   1 = 用法错误。
#
# 依赖
#   bash + python3（标准库）；Typst 编译器。Typst 版本钉死、首次运行自动拉取（见下）。
#   字体：需要 Noto Serif CJK SC（正文）和 Noto Sans CJK SC（标题），
#         否则 Typst 会回退到默认字体，可能影响排版效果。
#
# Typst 版本与校验和
#   钉死版本：TYPST_PIN_VERSION（见「解析 Typst」一节）。缓存目录：
#     ${XDG_CACHE_HOME:-$HOME/.cache}/repo-resume/typst/<版本>/<target>/typst
#   首次运行按本机平台从官方 GitHub release 拉取对应产物，先核对 sha256 再解压；
#   校验不过一律拒用，且全程 fail-open（拉不到就跳过，绝不阻断调用方）。
#   解析顺序：TYPST_PATH → 本地缓存 → 首次自动拉取 → 系统 typst（版本可能不同，会告警）。
#   开关：TYPST_PATH 显式指定；TYPST_CACHE 改缓存位置；AGENT_DOC_TYPST_FETCH=0 禁止联网拉取。
#   注意：官方 release 不提供校验和文件，表内 sha256 是下载后实算并钉死在本脚本里的
#   本地值，用于检测下载损坏或被替换，不是发布方签名。
#
# 中文排版（为什么不做「中英文之间加空格」那件事）
#   中西文间隙交给 Typst 原生 cjk-latin-spacing（默认 auto，约 0.25em 间隙），
#   在源文本里插字面空格会与它叠加、并污染行内代码。
#   软换行拼接见 md2typst.py 的 smart_join：CJK 一侧不补空格，
#   避开「中文断行处多出一个空格」（Typst 里源码换行即空格）。
#   转换器刻意不引第三方包，保持零依赖、可离线编译；若愿意接受运行时依赖，
#   md2typst(PyPI) 或 cmarker(Typst 包) 均可替换——实测页数一致，
#   但会在 git 钩子里引入 pip 依赖或首次编译联网取包。
#
# 输出位置为什么选 .git/：不进版本控制、不产生二进制变更、不用动 .gitignore。
# 关掉渲染：AGENT_DOC_PRINT_OFF=1（或干脆不装钩子）。

set -uo pipefail

TAG="[print-typst]"
QUIET=0
OUT_DIR=""
ARCHIVE_DIR=""
TARGETS=()
KEEP="${AGENT_DOC_PDF_KEEP:-10}"                  # 无 --archive 时的滚动保留份数
ARCHIVE_KEEP="${AGENT_DOC_PDF_ARCHIVE_KEEP:-30}"  # 归档目录每个文档名的封顶份数（0 = 不限）
FETCH_ONLY=0
IMAGES=0
IMG_PPI="${AGENT_DOC_PPI:-140}"
IMG_REC=""                                        # 查看模式下逐文档累积结果，收尾写 INDEX.md

while [ $# -gt 0 ]; do
  case "$1" in
    --quiet)  QUIET=1; shift ;;
    --out)    OUT_DIR="${2:-}"; shift 2 ;;
    --archive) ARCHIVE_DIR="${2:-}"; shift 2 ;;
    --images) IMAGES=1; shift ;;
    --ppi)    IMG_PPI="${2:-}"; shift 2 ;;
    --fetch-typst) FETCH_ONLY=1; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{print; next} {exit}' "$0"; exit 0 ;;
    -*) echo "$TAG 未知参数：$1" >&2; exit 1 ;;
    *)  TARGETS+=("$1"); shift ;;
  esac
done

[ "${AGENT_DOC_PRINT_OFF:-0}" = 1 ] && exit 0

case "$IMG_PPI" in
  ''|*[!0-9]*) echo "$TAG --ppi 需要正整数：$IMG_PPI" >&2; exit 1 ;;
esac
[ "$IMAGES" = 1 ] && IMG_REC="$(mktemp "${TMPDIR:-/tmp}/entry-doc-idx.XXXXXX" 2>/dev/null || true)"

say() { [ "$QUIET" = 1 ] || echo "$TAG $*"; }

# ── 1. 找文件：没给就自动发现 ─────────────────────────────────────────
if [ ${#TARGETS[@]} -eq 0 ]; then
  for n in AGENTS.md AGENT.md; do [ -f "$n" ] && TARGETS+=("$n"); done
fi
if [ ${#TARGETS[@]} -eq 0 ] && [ "$FETCH_ONLY" != 1 ]; then
  say "未找到入口文档，跳过"
  exit 0
fi

# ── 2. 解析 Typst：显式指定 → 本地缓存 → 首次自动拉取 → 系统回退 ─────────
# 版本与校验和都钉死，保证同一份文档在任何机器上排出来的页面一致。
TYPST_PIN_VERSION="0.15.1"
TYPST_CACHE="${TYPST_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/repo-resume/typst}"
TYPST_FETCH="${AGENT_DOC_TYPST_FETCH:-1}"   # 0 = 禁止联网拉取

note() { [ "$QUIET" = 1 ] || echo "$TAG $*" >&2; }   # 进度（可静默）
warn() { echo "$TAG $*" >&2; }                       # 失败与告警（始终可见）

sha256_of() {  # $1=文件 → 打印十六进制摘要
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum  >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else return 1; fi
}

# 本机平台 → Typst 官方 release 的 target 名
typst_target() {
  case "$(uname -s):$(uname -m)" in
    Linux:x86_64)              echo x86_64-unknown-linux-musl ;;
    Linux:aarch64|Linux:arm64) echo aarch64-unknown-linux-musl ;;
    Darwin:x86_64)             echo x86_64-apple-darwin ;;
    Darwin:arm64)              echo aarch64-apple-darwin ;;
    *) return 1 ;;
  esac
}

# target → 官方 release 产物的 sha256
# 来源 https://github.com/typst/typst/releases/tag/v0.15.1（2026-09-18 下载后实算）。
# 官方不提供校验和文件，这是本地钉死值，用于检测下载损坏或被替换，非发布方签名。
typst_sha() {
  case "$1" in
    x86_64-unknown-linux-musl)  echo a6d077d0a95eed5a2eba715b2dae06be954f624ccbf85758a03f389ded33118c ;;
    aarch64-unknown-linux-musl) echo 5aa8d74a3d906e60ea12a66ac2f37f8eef1b14cbad7182a745e393a10c23dcee ;;
    x86_64-apple-darwin)        echo 7f9fdd9584866245de9a79e0add8f9236fae6f40a8a45e2c4771ccc14db4e0fa ;;
    aarch64-apple-darwin)       echo 48f62ed034aa3a7978309579ac6ca00045e2ef0da73114e8af27cfd8e74dc05a ;;
    *) return 1 ;;
  esac
}

# 拉取 → 校验 sha256 → 解压进缓存；成功回显可执行文件路径
typst_fetch() {  # $1=target $2=期望 sha256
  local target="$1" want="$2"
  local dest bin
  dest="$TYPST_CACHE/$TYPST_PIN_VERSION/$target"
  bin="$dest/typst"
  local url="https://github.com/typst/typst/releases/download/v$TYPST_PIN_VERSION/typst-$target.tar.xz"
  command -v curl >/dev/null 2>&1 || { warn "没找到 curl，无法自动拉取 Typst"; return 1; }
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/typst-fetch.XXXXXX")" || return 1
  note "首次运行：拉取 Typst $TYPST_PIN_VERSION（$target）…"
  if ! curl -sSL --fail --retry 2 -o "$tmp/pack.tar.xz" "$url"; then
    warn "拉取失败：$url"; rm -rf "$tmp"; return 1
  fi
  local got; got="$(sha256_of "$tmp/pack.tar.xz")" || {
    warn "本机没有 sha256sum/shasum，无法校验，放弃拉取"; rm -rf "$tmp"; return 1
  }
  if [ "$got" != "$want" ]; then
    warn "校验和不符，拒用（期望 $want，实得 $got）"; rm -rf "$tmp"; return 1
  fi
  if ! tar -xJf "$tmp/pack.tar.xz" -C "$tmp" 2>/dev/null; then
    warn "解压失败（tar 需要 xz 支持）"; rm -rf "$tmp"; return 1
  fi
  local src; src="$(find "$tmp" -type f -name typst 2>/dev/null | head -1)"
  [ -n "$src" ] || { warn "包里没找到 typst 可执行文件"; rm -rf "$tmp"; return 1; }
  mkdir -p "$dest" || { rm -rf "$tmp"; return 1; }
  cp -f "$src" "$bin" && chmod +x "$bin" || { warn "写入缓存失败：$bin"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  echo "$bin"
}

typst_resolve() {
  # 1) 显式指定优先
  if [ -n "${TYPST_PATH:-}" ] && [ -x "${TYPST_PATH}" ]; then echo "$TYPST_PATH"; return 0; fi
  # 2) 本地缓存的钉死版本 → 3) 首次自动拉取
  local target sha cached
  if target="$(typst_target)" && sha="$(typst_sha "$target")"; then
    cached="$TYPST_CACHE/$TYPST_PIN_VERSION/$target/typst"
    if [ -x "$cached" ]; then echo "$cached"; return 0; fi
    if [ "$TYPST_FETCH" = 1 ]; then
      local b; b="$(typst_fetch "$target" "$sha")" && [ -n "$b" ] && { echo "$b"; return 0; }
    else
      note "自动拉取已关闭（AGENT_DOC_TYPST_FETCH=0）"
    fi
  fi
  # 4) 回退：系统里的 typst，版本可能与钉死值不同
  local sys; sys="$(command -v typst 2>/dev/null)"
  if [ -n "$sys" ] && [ -x "$sys" ]; then
    warn "回退到系统 typst（$sys），版本可能不是钉死的 $TYPST_PIN_VERSION"
    echo "$sys"; return 0
  fi
  return 1
}

TYPST="$(typst_resolve)" || {
  warn "没找到 Typst 也没拉到（可设 TYPST_PATH，或 grep 本脚本的缓存路径手动放置）→ 这次没排成；不影响任何流程"
  exit 0
}

# ── 3. 版本核对 ────────────────────────────────────────────────────────
TYPST_VERSION="$("$TYPST" --version 2>/dev/null | head -1)"
[ -n "$TYPST_VERSION" ] || { warn "Typst 版本检测失败 → 这次没排成"; exit 0; }
say "使用 $TYPST_VERSION"
case "$TYPST_VERSION" in
  *" $TYPST_PIN_VERSION "*) : ;;
  *) warn "注意：实际版本不是钉死的 $TYPST_PIN_VERSION，页面可能与别处不可比" ;;
esac

if [ "$FETCH_ONLY" = 1 ]; then
  say "Typst 已就绪：$TYPST"
  exit 0
fi

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

# ── 7. 查看模式：导出图片、写 INDEX.md ─────────────────────────────────
# 图片只是「把已选定的那一档再渲一遍」；取档与页数判断仍只在渲染那一段发生一次。
export_images() {  # $1=tmp $2=已选档的 typ $3=dest $4=base；成功 0，失败 1（调用方据此只留 PDF）
  local tmp="$1" src="$2" dest="$3" base="$4"
  local frames="$tmp/png" n=0 i
  mkdir -p "$frames" || return 1
  if ! timeout 25s "$TYPST" compile --format png --ppi "$IMG_PPI" "$src" "$frames/p-{p}.png" >/dev/null 2>&1; then
    warn "$base：图片导出失败（Typst 的 PNG 输出不可用）→ 这次只留 PDF"
    return 1
  fi
  while [ -f "$frames/p-$((n + 1)).png" ]; do n=$((n + 1)); done   # 页号连续，别用 ls|sort 排
  [ "$n" -gt 0 ] || { warn "$base：Typst 没产出图片 → 这次只留 PDF"; return 1; }
  rm -f "$dest/${base}-p"*.png                                     # 同名旧图先清，不累积
  for i in $(seq 1 "$n"); do
    cp -f "$frames/p-$i.png" "$dest/${base}-p$i.png" || { warn "$base：图片写不进 $dest"; return 1; }
  done
  say "   图片 $n 张：$dest/${base}-p1.png …"
  return 0
}

# INDEX.md 落在第一份文档的产出目录；图片按相对本文件的路径引用（md 和图能一起搬走）。
write_index() {  # $1=记录文件（每行一个文档）；$2=INDEX.md 路径
  python3 - "$1" "$2" "$TYPST_VERSION" "$IMG_PPI" <<'PY'
import io, os, sys, datetime
rec, out, ver, ppi = sys.argv[1:5]
rows = [l.rstrip("\n").split("\t") for l in io.open(rec, encoding="utf-8") if l.strip()]
L = ["# 入口文档 · 图片", "",
     "> 由 repo-resume 打印层生成：入口文档排成 A4 页面后逐页导出图片，图片路径相对于本文件。",
     "> 后端 Typst %s · %s ppi · 生成于 %s"
     % (ver.replace("typst ", ""), ppi, datetime.datetime.now().strftime("%Y-%m-%d %H:%M")), "",
     "| 文档 | 实排 | 档 | 图片 |", "|---|---:|---|---:|"]
for dest, base, rel, pages, note, est, have in rows:
    L.append("| `%s` | %s 页 | %s | %s |" % (rel, pages, note, pages + " 张" if have == "1" else "—"))
L.append("")
for dest, base, rel, pages, note, est, have in rows:
    L += ["## %s" % rel, "",
          "实排 %s 页（%s）｜排版开销 %+.1f 页" % (pages, note, int(pages) - float(est)), ""]
    if have != "1":
        L += ["_这次没导出图片。_", ""]
        continue
    for i in range(1, int(pages) + 1):
        img = os.path.join(dest, "%s-p%d.png" % (base, i))
        L += ["![%s 第 %d 页](%s)" % (rel, i, os.path.relpath(img, os.path.dirname(out))), ""]
io.open(out, "w", encoding="utf-8").write("\n".join(L))
PY
}

# ── 8. 渲染函数 ────────────────────────────────────────────────────────
render_one() {
  local target="$1"
  local abs tmp typ pdf base stamp out note="工作区版" root rel

  abs="$(cd "$(dirname "$target")" 2>/dev/null && pwd)/$(basename "$target")"
  [ -e "$abs" ] || { say "$target 不存在，跳过"; return 0; }

  # 文档键：先取「相对当前目录的路径」（钩子从仓库根调用 → 与历史命名一致；多仓、
  # 多份同名文档混在一个产出目录时也分得开），出不了当前目录再退回仓库内相对路径，
  # 都没有才用文件名——否则根 AGENTS.md 与 scripts/AGENTS.md 会撞成同一个键、图片互相覆盖。
  root="$(git -C "$(dirname "$abs")" rev-parse --show-toplevel 2>/dev/null)"
  rel="$(python3 - "$abs" "${root:-}" "$PWD" <<'PY'
import os, sys
abs_, root, cwd = sys.argv[1:4]
def rel_from(base):
    p = os.path.relpath(abs_, base)
    return p if not p.startswith("..") else ""
print(rel_from(cwd) or rel_from(root) or os.path.basename(abs_))
PY
)"
  [ -n "${rel:-}" ] || rel="$(basename "$abs")"

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/entry-doc-typst.XXXXXX")"
  cp "$abs" "$tmp/doc.md" 2>/dev/null || { rm -rf "$tmp"; warn "$target 读不到，跳过"; return 0; }

  # 输出目录
  if [ -n "$OUT_DIR" ]; then
    dest="$OUT_DIR"
  elif [ -n "$root" ] && [ -d "$root/.git" ]; then
    dest="$root/.git/entry-doc-pdf"
  else
    dest="$(dirname "$abs")/.entry-doc-pdf"
  fi
  mkdir -p "$dest" 2>/dev/null || { rm -rf "$tmp"; warn "输出目录建不了：$dest，跳过"; return 0; }

  # 文件名：文档键 = 文档相对路径去掉 .md、把 '/' 换成 '-'
  base="$(printf '%s' "${rel%.md}" | tr '/' '-')"
  stamp="$(date +%Y%m%d-%H%M%S)"
  pdf="$dest/${base}-${stamp}.pdf"

  # 转换为 Typst
  md2typst "$tmp/doc.md" "$tmp/doc.typ" std
  if [ ! -s "$tmp/doc.typ" ]; then
    rm -rf "$tmp"; warn "$target：Typst 转换失败 → 这次没排成"; return 0
  fi

  # 编译为 PDF
  if ! timeout 25s "$TYPST" compile "$tmp/doc.typ" "$pdf" >/dev/null 2>&1; then
    rm -rf "$tmp"; warn "$target：Typst 编译失败或超时 → 这次没排成；不影响任何流程"
    return 0
  fi

  [ -s "$pdf" ] || { rm -rf "$tmp"; warn "$target：PDF 生成失败 → 这次没排成"; return 0; }

  # 末页合并：标准排版下末页只剩一点点时，改用 fit 档再排一次
  # 档位与页数只在这里判一次；查看模式复用这个结果（图片与 PDF 同档同页）。
  local p_std p_fit tier typ_src
  tier=std; typ_src="$tmp/doc.typ"; p_fit=""
  p_std="$(pdf_pages "$pdf")"
  if [ -n "$p_std" ] && [ "$p_std" -gt 1 ] 2>/dev/null; then
    # 生成 fit 档的 Typst 文件
    md2typst "$tmp/doc.md" "$tmp/fit.typ" fit
    if [ -s "$tmp/fit.typ" ]; then
      if timeout 25s "$TYPST" compile "$tmp/fit.typ" "$tmp/fit.pdf" >/dev/null 2>&1; then
        p_fit="$(pdf_pages "$tmp/fit.pdf")"
        if [ -n "$p_fit" ] && [ "$p_fit" = "$((p_std - 1))" ]; then
          mv -f "$tmp/fit.pdf" "$pdf"; note="$note·末页合并"
          tier=fit; typ_src="$tmp/fit.typ"
          [ "$QUIET" = 1 ] || echo "$TAG   $target：末页收进前页（$p_std 页 → $p_fit 页，排版档 fit）"
        fi
      fi
    fi
  fi
  local pages_final; pages_final="$p_std"; [ "$tier" = fit ] && pages_final="$p_fit"

  # 查看模式：把已选定的这一档导出成逐页图片（失败只留 PDF，不动判决）
  local have_img=0
  if [ "$IMAGES" = 1 ] && export_images "$tmp" "$typ_src" "$dest" "$base"; then have_img=1; fi

  # 输出统计信息（页数上一步已判好，这里只算「排版开销」；查看模式顺带记一行给 INDEX.md）
  python3 - "$pdf" "$dest" "$tmp/doc.md" "$note" "$QUIET" "$base" "$pages_final" "$rel" "${IMG_REC:-}" "$have_img" <<'PY'
import os, re, sys
pdf, dest, md, note, quiet, base, pages_final, rel, rec, have_img = sys.argv[1:11]
pages = int(pages_final)
text = open(md, encoding="utf-8").read()
CJK = r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uff65\u2018-\u201d\u2013\u2014]"
cjk = len(re.findall(CJK, text))
no_cjk = re.sub(CJK, "", text)
ascii_chars = len(re.sub(r"\s", "", no_cjk))
est = (cjk + ascii_chars * 0.5) / 1400.0
print("📄 %s（%s）实排 %d 页｜算术 %.1f 页｜排版开销 %+.1f 页"
      % (os.path.basename(pdf), note, pages, est, pages - est))
if not quiet:
    print("   路径：%s" % pdf)
    print("   注：算术页数是纯体积模型；实排多出来的部分是短行、表格、项目符号造成的行尾留白。")
if rec:
    with open(rec, "a", encoding="utf-8") as f:
        f.write("\t".join([dest, base, rel or base, str(pages), note, "%.2f" % est, str(have_img)]) + "\n")
PY

  rm -rf "$tmp"

  # 保留策略（与 print-entry-doc.sh 逐字一致）
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

# ── 9. 主循环 ──────────────────────────────────────────────────────────
for t in "${TARGETS[@]}"; do render_one "$t"; done

# 查看模式收尾：写 INDEX.md（导出失败的文档在表里标「—」，不假装有图）
if [ "$IMAGES" = 1 ] && [ -n "${IMG_REC:-}" ] && [ -s "$IMG_REC" ]; then
  _idx_dir="$(head -1 "$IMG_REC" | cut -f1)"
  if [ -n "$_idx_dir" ]; then
    write_index "$IMG_REC" "$_idx_dir/INDEX.md"
    say "INDEX.md：$_idx_dir/INDEX.md"
    # 本地路径很多渲染器（手机聊天 App 尤其）加载不出来，http 才行——把最后一步递出去。
    say "要给人看（手机 / 浏览器 / 对话里的 markdown）：bash \"$(cd "$(dirname "$0")" && pwd)/serve-entry-doc.sh\" --dir \"$_idx_dir\""
  fi
fi
[ -n "${IMG_REC:-}" ] && rm -f "$IMG_REC"
exit 0