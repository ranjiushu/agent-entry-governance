#!/usr/bin/env bash
# 把「入口文档打印」装进某个 git 仓库（**判决层**：不阻断流程，但它是页面终审的依据）。
#
# 装两样东西：
#   <repo>/tools/entry-doc/<渲染器>             渲染器本体（**入库**，随 clone 走）
#   <repo>/.githooks/post-commit                薄壳调用块（标记包裹，幂等）
# 渲染后端（--backend，默认 typst）：
#   typst  = print-entry-doc-typst.sh  Typst 排版；版本钉死、首次运行自动拉取到用户缓存
#   chrome = print-entry-doc.sh        无头浏览器版；留作回退（不想联网拉 Typst 时）
# 并按需设置 git config core.hooksPath=.githooks。
#
# 为什么挂 post-commit 而不是 pre-commit：
#   渲染要 1–2 秒，而**慢钩子会把人逼去用 --no-verify**，届时 pre-commit 里的真守卫
#   会被一起跳过。所以它挂在提交完成之后，且本块**永不返回非零** —— 不阻断不等于次要，它管的是判决那一侧。
#   （Typst 版渲染本身很快，但首次运行要拉取编译器；挂 post-commit 的理由不变。）
#
# 用法：
#   bash install-print-hook.sh                          # 装到当前仓库，自动发现 AGENTS.md
#   bash install-print-hook.sh --repo <路径>
#   bash install-print-hook.sh --docs "SKILL.md entry-card-craft/SKILL.md"
#                                                       # 显式声明要打印哪些文件（仓库内相对路径）
#   bash install-print-hook.sh --script <仓库内相对路径>  # 自举模式：不复制本体，直接调仓库里那份
#                                                       #   （本技能自己的仓库用它，避免同一文件两份）
#   bash install-print-hook.sh --out <绝对目录>          # 产出集中到指定目录（默认 <仓库>/.git/entry-doc-pdf/）
#                                                       #   多个仓库共用一个输出位时，按仓分子目录传入即可
#   bash install-print-hook.sh --archive <绝对目录>      # 归档目录：产出位只留最新一份，旧的移进去
#                                                       #   （不给就退化为「保留最近 KEEP 份」）
#   bash install-print-hook.sh --backend typst|chrome    # 选渲染后端（默认 typst）
#   bash install-print-hook.sh --check | --dry-run | --uninstall
#
# 跳过规则：本次提交**没碰**声明的入口文档时自动跳过（存量豁免）；
#           AGENT_DOC_PRINT_ALWAYS=1 可强制每次提交都排。
# 退出码：0 成功 / 1 失败或校验不通过。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BACKEND="typst"
PAYLOAD_SCRIPT=""   # 由 --backend 决定，见下方参数解析之后
MARK_BEGIN="# >>> repo-resume: entry-doc-print (start) >>>"
MARK_END="# <<< repo-resume: entry-doc-print (end) <<<"

strip_block() {  # $1=钩子文件 $2=起始标记 $3=结束标记
  [ -f "$1" ] || return 0
  grep -qF "$2" "$1" || return 0
  python3 - "$1" "$2" "$3" <<'PYEOF'
import io, sys
hook, mb, me = sys.argv[1:4]
src = io.open(hook, encoding="utf-8").read()
i, j = src.find(mb), src.find(me)
if i != -1 and j != -1:
    io.open(hook, "w", encoding="utf-8").write((src[:i] + src[j + len(me):]).strip("\n") + "\n")
PYEOF
}

MODE=install
REPO=""
DOCS=""
DOCS_GIVEN=0
SELF_SCRIPT=""
OUT=""
ARCHIVE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2 ;;
    --docs)   DOCS="${2:-}"; DOCS_GIVEN=1; shift 2 ;;
    --script) SELF_SCRIPT="${2:-}"; shift 2 ;;
    --out)    OUT="${2:-}"; shift 2 ;;
    --archive) ARCHIVE="${2:-}"; shift 2 ;;
    --backend) BACKEND="${2:-}"; shift 2 ;;
    --check)  MODE=check; shift ;;
    --dry-run) MODE=dryrun; shift ;;
    --uninstall) MODE=uninstall; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{print; next} {exit}' "$0"; exit 0 ;;
    *) echo "[print-install] 未知参数：$1（--help 看用法）" >&2; exit 1 ;;
  esac
done

case "$BACKEND" in
  typst)  PAYLOAD_SCRIPT="print-entry-doc-typst.sh" ;;
  chrome) PAYLOAD_SCRIPT="print-entry-doc.sh" ;;
  *) echo "[print-install] ❌ 未知后端：$BACKEND（可选 typst | chrome）" >&2; exit 1 ;;
esac

# 渲染器可能带配套文件（Typst 后端依赖同目录的 md2typst.py 转换器）。
# 它们必须一起复制，否则装到目标仓库后渲染器找不到自己的零件。
PAYLOAD_EXTRA=()
# Typst 后端多带几件配套：转换器（渲染器按自身目录找它）、查看模式入口、看图的静态服务。
[ "$PAYLOAD_SCRIPT" = "print-entry-doc-typst.sh" ] && PAYLOAD_EXTRA=("md2typst.py" "view-entry-doc.sh" "serve-entry-doc.sh")
PAYLOAD_FILES="SOURCE.md $PAYLOAD_SCRIPT"
for _e in "${PAYLOAD_EXTRA[@]:-}"; do [ -n "$_e" ] && PAYLOAD_FILES="$PAYLOAD_FILES $_e"; done

# ── 定位仓库 ──────────────────────────────────────────────────────────
if [ -z "$REPO" ]; then REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"; fi
if [ -z "$REPO" ] || ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[print-install] ❌ 不是 git 仓库：${REPO:-（当前目录）}；用 --repo <路径> 指定" >&2
  exit 1
fi
REPO="$(cd "$REPO" && pwd)"
HOOK="$REPO/.githooks/post-commit"

# --out 必须是绝对路径：钩子会 cd 到仓库根再调用，相对路径会漂
if [ -n "$OUT" ]; then
  case "$OUT" in
    /*) ;;
    *) echo "[print-install] ❌ --out 需要绝对路径：$OUT" >&2; exit 1 ;;
  esac
  case "${OUT%/}/" in
    "$REPO"/*) echo "[print-install] ⚠️  --out 落在仓库工作树内（$OUT）——PDF 会进版本控制，通常不该这样" >&2 ;;
  esac
fi
if [ -n "$ARCHIVE" ]; then
  case "$ARCHIVE" in
    /*) ;;
    *) echo "[print-install] ❌ --archive 需要绝对路径：$ARCHIVE" >&2; exit 1 ;;
  esac
fi
PAYLOAD_DIR="$REPO/tools/entry-doc"

# 自举模式：钩子直接调仓库内那份（本技能自己的仓库用）
if [ -n "$SELF_SCRIPT" ]; then
  RUNNER="$REPO/$SELF_SCRIPT"
  RUNNER_REL="$SELF_SCRIPT"
else
  RUNNER="$PAYLOAD_DIR/$PAYLOAD_SCRIPT"
  RUNNER_REL="tools/entry-doc/$PAYLOAD_SCRIPT"
fi

# 要打印哪些文件：显式 --docs 优先，否则落成默认的自动发现名单。
# 一律写进钩子（不留分支）：钩子里少一个分支就少一处能让打印变哑的地方。
[ -z "$DOCS" ] && DOCS="AGENTS.md AGENT.md"
read -r -d '' DOCS_BLOCK <<DOCSEOF || true
_ep_docs=($(for d in $DOCS; do printf '"%s" ' "$d"; done))
DOCSEOF

# ── 校验模式 ──────────────────────────────────────────────────────────
if [ "$MODE" = check ]; then
  rc=0
  # 没显式给 --docs 时，清单对齐到钩子里写死那份：否则「只放 AGENTS.md」的仓
  # 会被校验的默认名单（AGENTS.md AGENT.md）误报成「声明的文档不存在」。
  if [ "$DOCS_GIVEN" = 0 ] && [ -f "$HOOK" ]; then
    _hd="$(sed -n 's/^[[:space:]]*_ep_docs=(\(.*\))[[:space:]]*$/\1/p' "$HOOK" | head -1 | tr -d '"')"
    [ -n "$_hd" ] && DOCS="$_hd"
  fi
  hooks_path="$(git -C "$REPO" config --get core.hooksPath || true)"
  if [ "$hooks_path" != ".githooks" ]; then
    echo "[print-install] ❌ core.hooksPath=$hooks_path（应为 .githooks）——钩子不会生效" >&2; rc=1
  fi
  if [ ! -f "$HOOK" ] || ! grep -qF "$MARK_BEGIN" "$HOOK"; then
    echo "[print-install] ❌ $HOOK 里没有本打印层的调用块" >&2; rc=1
  fi
  if ! grep -qF "$(echo $DOCS | awk '{print $1}')" "$HOOK"; then
    echo "[print-install] ⚠️  钩子里的文档清单与本次 --docs 不一致" >&2; rc=1
  fi
  # 声明了不存在的文档 = 配错。渲染器在 --quiet 下对这类情况保持沉默（不然每次提交都刷屏），
  # 所以配错只能在这里抓出来——校验是唯一能发现它的地方。
  for _d in $DOCS; do
    if [ ! -e "$REPO/$_d" ]; then
      echo "[print-install] ❌ 声明的文档不存在：$_d" >&2; rc=1
    fi
  done
  # 产出位置：本次带了 --out 就必须写进钩子，否则 PDF 会落回 <仓库>/.git/ 里
  if [ -n "$ARCHIVE" ] && ! grep -qF -- "--archive \"$ARCHIVE\"" "$HOOK"; then
    echo "[print-install] ❌ 钩子里的归档目录与本次 --archive 不一致（预期 $ARCHIVE）" >&2; rc=1
  fi
  if [ -n "$OUT" ]; then
    if ! grep -qF -- "--out \"$OUT\"" "$HOOK"; then
      echo "[print-install] ❌ 钩子里的产出目录与本次 --out 不一致（预期 $OUT）" >&2; rc=1
    fi
    [ -d "$OUT" ] || echo "[print-install] ⚠️  产出目录尚不存在（首次渲染自建）：$OUT" >&2
  fi
  if [ ! -f "$RUNNER" ]; then
    _other="print-entry-doc-typst.sh"
    [ "$PAYLOAD_SCRIPT" = "print-entry-doc-typst.sh" ] && _other="print-entry-doc.sh"
    if [ -z "$SELF_SCRIPT" ] && [ -f "$REPO/tools/entry-doc/$_other" ]; then
      echo "[print-install] ⚠️  这个仓库装的是另一个后端（$_other）；用对应的 --backend 重跑校验" >&2
    fi
    echo "[print-install] ❌ 渲染器不在位：$RUNNER_REL（自举模式指向的那份可能被移走了）" >&2; rc=1
  elif [ -z "$SELF_SCRIPT" ] && ! cmp -s "$HERE/$PAYLOAD_SCRIPT" "$RUNNER"; then
    echo "[print-install] ⚠️  渲染器与上游不一致（后端 $BACKEND；仓库副本被手改过、装了别的后端，或上游已更新）" >&2; rc=1
  fi
  if [ -z "$SELF_SCRIPT" ]; then
    for _e in "${PAYLOAD_EXTRA[@]:-}"; do
      [ -n "$_e" ] || continue
      if [ ! -f "$PAYLOAD_DIR/$_e" ]; then
        echo "[print-install] ❌ 渲染器的配套文件不在位：tools/entry-doc/$_e" >&2; rc=1
      elif ! cmp -s "$HERE/$_e" "$PAYLOAD_DIR/$_e"; then
        echo "[print-install] ⚠️  配套文件与上游不一致：$_e" >&2; rc=1
      fi
    done
  fi
  if [ "$rc" = 0 ]; then
    echo "[print-install] ✅ 已正确安装：$REPO"
    echo "[print-install]    渲染器：$RUNNER_REL"
    echo "[print-install]    触发点：$HOOK（post-commit；改动入口文档时才排）"
  else
    echo "[print-install] 修复：重跑 bash $0 --repo $REPO（幂等）" >&2
  fi
  exit "$rc"
fi

# ── 组块内容 ──────────────────────────────────────────────────────────
# 产出与归档目录：给了就写死进钩子（钩子里少一个分支，就少一处能让打印变哑的地方）
EP_ARGS=""
[ -n "$OUT" ] && EP_ARGS="--out \"$OUT\" "
[ -n "$ARCHIVE" ] && EP_ARGS="$EP_ARGS--archive \"$ARCHIVE\" "

read -r -d '' BLOCK <<BLOCKEOF || true
$MARK_BEGIN
# 由 repo-resume 技能（子技能 entry-card-craft）的 install-print-hook.sh 写入，
# **勿手改**；更新走上游重跑安装脚本（幂等）。
# 这是**打印层（判决依据），不是门禁**：本块永不返回非零，渲染失败只留一行说明。
{
  _ep_root="\$(git rev-parse --show-toplevel 2>/dev/null)"
  _ep_script="\$_ep_root/$RUNNER_REL"
  $DOCS_BLOCK
  if [ -n "\$_ep_root" ] && [ -f "\$_ep_script" ]; then
    _ep_run=0
    if [ "\${AGENT_DOC_PRINT_ALWAYS:-0}" = 1 ]; then
      _ep_run=1
    else
      _ep_changed="\$(git diff-tree --no-commit-id --name-only -r --root HEAD 2>/dev/null)"
      for _ep_d in "\${_ep_docs[@]}"; do
        if printf '%s\\n' "\$_ep_changed" | grep -qxF "\$_ep_d"; then _ep_run=1; break; fi
      done
    fi
    if [ "\$_ep_run" = 1 ]; then
      ( cd "\$_ep_root" && bash "\$_ep_script" --quiet $EP_ARGS"\${_ep_docs[@]}" ) || true
    fi
  fi
}
$MARK_END
BLOCKEOF

if [ "$MODE" = uninstall ]; then
  if [ -f "$HOOK" ] && grep -qF "$MARK_BEGIN" "$HOOK"; then
    strip_block "$HOOK" "$MARK_BEGIN" "$MARK_END"
    echo "[print-install] ✅ 已移除钩子块：$HOOK"
  else
    echo "[print-install] 钩子里没有本打印层的块，无需移除"
  fi
  if [ -z "$SELF_SCRIPT" ]; then
    rm -rf "$PAYLOAD_DIR/__pycache__"
    rm -f "$PAYLOAD_DIR/SOURCE.md"
    for _e in "$PAYLOAD_SCRIPT" "${PAYLOAD_EXTRA[@]:-}"; do
      [ -n "$_e" ] && rm -f "$PAYLOAD_DIR/$_e"
    done
    rmdir "$PAYLOAD_DIR" 2>/dev/null || true
  fi
  echo "[print-install]    提示：若 $HOOK 已无其他内容，可自行删除该空壳钩子"
  echo "[print-install]    已产出的 PDF 在 <仓库>/.git/entry-doc-pdf/，可自行删除"
  exit 0
fi

if [ "$MODE" = dryrun ]; then
  echo "[print-install] [dry-run] 仓库：$REPO"
  if [ -n "$SELF_SCRIPT" ]; then
    echo "[print-install] [dry-run] 渲染器：复用仓库内 $RUNNER_REL（不复制）"
  else
    echo "[print-install] [dry-run] 将写入：$PAYLOAD_DIR/{$(echo $PAYLOAD_FILES | tr ' ' ',')}"
  fi
  echo "[print-install] [dry-run] 将在 $HOOK 写入/替换标记块"
  echo "[print-install] [dry-run] 将设置 core.hooksPath=.githooks"
  echo "[print-install] [dry-run] 文档清单：${DOCS:-（自动发现 AGENTS.md / AGENT.md）}"
  echo "[print-install] [dry-run] 产出目录：${OUT:-$REPO/.git/entry-doc-pdf}"
  echo "[print-install] [dry-run] 归档目录：${ARCHIVE:-（无，退化为保留最近 10 份）}"
  exit 0
fi

# ── 安装 ──────────────────────────────────────────────────────────────
mkdir -p "$REPO/.githooks"
if [ -z "$SELF_SCRIPT" ]; then
  mkdir -p "$PAYLOAD_DIR"
  cp "$HERE/$PAYLOAD_SCRIPT" "$PAYLOAD_DIR/$PAYLOAD_SCRIPT"
  chmod +x "$PAYLOAD_DIR/$PAYLOAD_SCRIPT"
  for _e in "${PAYLOAD_EXTRA[@]:-}"; do
    [ -n "$_e" ] && cp "$HERE/$_e" "$PAYLOAD_DIR/$_e"
  done
  cat > "$PAYLOAD_DIR/SOURCE.md" <<'NOTICEEOF'
# tools/entry-doc —— 入口文档打印（分发副本，判决层）

本目录由 repo-resume 技能（子技能 `entry-card-craft`）的 `install-print-hook.sh` 写入，
**请勿手改**：手改会在下次安装时被覆盖，并让仓库与上游漂移。

- 上游：技能的 `entry-card-craft/scripts/`
- 文件：渲染器本体 + 它的配套（Typst 后端含 `md2typst.py` 转换器与 `view-entry-doc.sh`
  查看模式入口，都与渲染器同目录；勿单独移走或改名——渲染器按自身所在目录找转换器）。
- 更新：拿到新版技能目录后重跑 `install-print-hook.sh`（幂等，可反复执行）
- 校验：`install-print-hook.sh --check`
- 定位：**这不是门禁**。它把入口文档排成 A4 PDF、报页数（给人一个能感觉到的刻度），
  并报出「排版开销」＝实排页数 − 算术页数。它挂在 post-commit，永不阻断任何提交。
- 依赖：Typst（版本由脚本钉死，首次运行自动拉取到用户缓存并核对 sha256）；缺了就跳过并说明，
  不静默假装成功。无头浏览器版仍在技能里留作回退（重装时加 `--backend chrome`）。
- 产出：默认 `<仓库>/.git/entry-doc-pdf/`；安装时带 `--out <绝对目录>` 可把产出集中到仓库外
  （多个仓库共用一个输出位时，按仓分子目录传）。
- 查看模式：`bash tools/entry-doc/view-entry-doc.sh <文档…>` 把已选定的一档逐页导出为
  PNG，并写 `<输出目录>/INDEX.md` 用相对路径引用每页（图片是给人看的二进制，同名滚动
  覆盖、不进版本控制）。它等价于渲染器加 `--images`，不是第二套渲染实现。
- 把它递给人：本地路径在很多渲染器里加载不出来（手机聊天 App 尤其），`serve-entry-doc.sh`
  把产出目录挂成静态服务并打印可直接粘进 markdown 的 http 引用。它是**长驻进程**，
  要在持久终端里前台跑，别挂进钩子。
- 产出位只留最新：带 `--archive <绝对目录>` 时，同一文档名的旧 PDF 自动移进归档目录，
  产出位永远只有最新一份；不给 `--archive` 就退化为「每个文档名保留最近 10 份」。
NOTICEEOF
fi

if [ ! -f "$HOOK" ]; then
  printf '#!/usr/bin/env bash\n# 由 repo-resume 技能 create 的钩子（原先无 post-commit）\nset -uo pipefail\n\n' > "$HOOK"
fi

python3 - "$HOOK" "$MARK_BEGIN" "$MARK_END" "$BLOCK" <<'PYEOF'
import io, os, sys
hook, mb, me, block = sys.argv[1:5]
block = block.rstrip("\n") + "\n"
src = io.open(hook, encoding="utf-8").read() if os.path.exists(hook) else ""
i, j = src.find(mb), src.find(me)
if i != -1 and j != -1:
    new = src[:i] + block + src[j + len(me):].lstrip("\n")
else:
    new = src.rstrip("\n") + "\n\n" + block if src.strip() else block
io.open(hook, "w", encoding="utf-8").write(new)
PYEOF
chmod +x "$HOOK"

_prev_hooks="$(git -C "$REPO" config --get core.hooksPath 2>/dev/null || true)"
if [ -n "$_prev_hooks" ] && [ "$_prev_hooks" != ".githooks" ]; then
  echo "[print-install] ⚠️  原 core.hooksPath=$_prev_hooks 将被覆盖为 .githooks" >&2
  echo "[print-install]    若该目录已有其他钩子（如 husky），请人工迁移合并到 .githooks/ 后重跑 --check" >&2
fi
git -C "$REPO" config core.hooksPath .githooks

echo "[print-install] ✅ 已安装：$REPO"
if [ -n "$SELF_SCRIPT" ]; then
  echo "[print-install]    渲染器：复用仓库内 $RUNNER_REL（未复制，避免同文件两份）"
else
  echo "[print-install]    渲染器：$PAYLOAD_DIR/{$PAYLOAD_SCRIPT,SOURCE.md}"
fi
echo "[print-install]    钩子块：$HOOK（post-commit）"
echo "[print-install]    文档清单：${DOCS:-自动发现 AGENTS.md / AGENT.md}"
echo "[print-install]    产出目录：${OUT:-$REPO/.git/entry-doc-pdf}"
echo "[print-install]    归档目录：${ARCHIVE:-（无，则每份名滚动保留最近 10 个）}"
echo "[print-install]    自检：bash $0 --repo $REPO --check"
exit 0
