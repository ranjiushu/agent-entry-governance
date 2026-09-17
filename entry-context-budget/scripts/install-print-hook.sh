#!/usr/bin/env bash
# 把「入口文档打印」这个彩蛋装进某个 git 仓库（**可选层，不是门禁**）。
#
# 装两样东西：
#   <repo>/tools/entry-doc/print-entry-doc.sh   渲染器本体（**入库**，随 clone 走）
#   <repo>/.githooks/post-commit                薄壳调用块（标记包裹，幂等）
# 并按需设置 git config core.hooksPath=.githooks。
#
# 为什么挂 post-commit 而不是 pre-commit：
#   渲染要 1–2 秒，而**慢钩子会把人逼去用 --no-verify**，届时 pre-commit 里的真守卫
#   会被一起跳过。彩蛋绝不能拖累防线，所以它挂在提交完成之后，且本块**永不返回非零**。
#
# 用法：
#   bash install-print-hook.sh                          # 装到当前仓库，自动发现 AGENTS.md
#   bash install-print-hook.sh --repo <路径>
#   bash install-print-hook.sh --docs "SKILL.md entry-context-budget/SKILL.md"
#                                                       # 显式声明要打印哪些文件（仓库内相对路径）
#   bash install-print-hook.sh --script <仓库内相对路径>  # 自举模式：不复制本体，直接调仓库里那份
#                                                       #   （本技能自己的仓库用它，避免同一文件两份）
#   bash install-print-hook.sh --check | --dry-run | --uninstall
#
# 跳过规则：本次提交**没碰**声明的入口文档时自动跳过（存量豁免）；
#           AGENT_DOC_PRINT_ALWAYS=1 可强制每次提交都排。
# 退出码：0 成功 / 1 失败或校验不通过。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_SCRIPT="print-entry-doc.sh"
MARK_BEGIN="# >>> agent-entry-governance: entry-doc-print (start) >>>"
MARK_END="# <<< agent-entry-governance: entry-doc-print (end) <<<"

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
SELF_SCRIPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2 ;;
    --docs)   DOCS="${2:-}"; shift 2 ;;
    --script) SELF_SCRIPT="${2:-}"; shift 2 ;;
    --check)  MODE=check; shift ;;
    --dry-run) MODE=dryrun; shift ;;
    --uninstall) MODE=uninstall; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{print; next} {exit}' "$0"; exit 0 ;;
    *) echo "[print-install] 未知参数：$1（--help 看用法）" >&2; exit 1 ;;
  esac
done

# ── 定位仓库 ──────────────────────────────────────────────────────────
if [ -z "$REPO" ]; then REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"; fi
if [ -z "$REPO" ] || ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "[print-install] ❌ 不是 git 仓库：${REPO:-（当前目录）}；用 --repo <路径> 指定" >&2
  exit 1
fi
REPO="$(cd "$REPO" && pwd)"
HOOK="$REPO/.githooks/post-commit"
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
# 一律写进钩子（不留分支）：钩子里少一个分支就少一处能让彩蛋变哑的地方。
[ -z "$DOCS" ] && DOCS="AGENTS.md AGENT.md"
read -r -d '' DOCS_BLOCK <<DOCSEOF || true
_ep_docs=($(for d in $DOCS; do printf '"%s" ' "$d"; done))
DOCSEOF

# ── 校验模式 ──────────────────────────────────────────────────────────
if [ "$MODE" = check ]; then
  rc=0
  hooks_path="$(git -C "$REPO" config --get core.hooksPath || true)"
  if [ "$hooks_path" != ".githooks" ]; then
    echo "[print-install] ❌ core.hooksPath=$hooks_path（应为 .githooks）——钩子不会生效" >&2; rc=1
  fi
  if [ ! -f "$HOOK" ] || ! grep -qF "$MARK_BEGIN" "$HOOK"; then
    echo "[print-install] ❌ $HOOK 里没有本彩蛋的调用块" >&2; rc=1
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
  if [ ! -f "$RUNNER" ]; then
    echo "[print-install] ❌ 渲染器不在位：$RUNNER_REL（自举模式指向的那份可能被移走了）" >&2; rc=1
  elif [ -z "$SELF_SCRIPT" ] && ! cmp -s "$HERE/$PAYLOAD_SCRIPT" "$RUNNER"; then
    echo "[print-install] ⚠️  渲染器与上游不一致（仓库副本被手改过，或上游已更新）" >&2; rc=1
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
read -r -d '' BLOCK <<BLOCKEOF || true
$MARK_BEGIN
# 由 agent-entry-governance 技能（子技能 entry-context-budget）的 install-print-hook.sh 写入，
# **勿手改**；更新走上游重跑安装脚本（幂等）。
# 这是**彩蛋层，不是门禁**：本块永不返回非零，渲染失败只留一行说明。
{
  _ep_root="\$(git rev-parse --show-toplevel 2>/dev/null)"
  _ep_script="\$_ep_root/$RUNNER_REL"
  $DOCS_BLOCK
  if [ -n "\$_ep_root" ] && [ -f "\$_ep_script" ]; then
    _ep_run=0
    if [ "\${AGENT_DOC_PRINT_ALWAYS:-0}" = 1 ]; then
      _ep_run=1
    else
      _ep_changed="\$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null)"
      for _ep_d in "\${_ep_docs[@]}"; do
        if printf '%s\\n' "\$_ep_changed" | grep -qxF "\$_ep_d"; then _ep_run=1; break; fi
      done
    fi
    if [ "\$_ep_run" = 1 ]; then
      ( cd "\$_ep_root" && bash "\$_ep_script" --quiet "\${_ep_docs[@]}" ) || true
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
    echo "[print-install] 钩子里没有本彩蛋的块，无需移除"
  fi
  if [ -z "$SELF_SCRIPT" ]; then
    rm -rf "$PAYLOAD_DIR/__pycache__"
    rm -f "$PAYLOAD_DIR/$PAYLOAD_SCRIPT" "$PAYLOAD_DIR/SOURCE.md"
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
    echo "[print-install] [dry-run] 将写入：$PAYLOAD_DIR/{$PAYLOAD_SCRIPT,SOURCE.md}"
  fi
  echo "[print-install] [dry-run] 将在 $HOOK 写入/替换标记块"
  echo "[print-install] [dry-run] 将设置 core.hooksPath=.githooks"
  echo "[print-install] [dry-run] 文档清单：${DOCS:-（自动发现 AGENTS.md / AGENT.md）}"
  exit 0
fi

# ── 安装 ──────────────────────────────────────────────────────────────
mkdir -p "$REPO/.githooks"
if [ -z "$SELF_SCRIPT" ]; then
  mkdir -p "$PAYLOAD_DIR"
  cp "$HERE/$PAYLOAD_SCRIPT" "$PAYLOAD_DIR/$PAYLOAD_SCRIPT"
  chmod +x "$PAYLOAD_DIR/$PAYLOAD_SCRIPT"
  cat > "$PAYLOAD_DIR/SOURCE.md" <<'NOTICEEOF'
# tools/entry-doc —— 入口文档打印（分发副本，**可选层**）

本目录由 agent-entry-governance 技能（子技能 `entry-context-budget`）的 `install-print-hook.sh` 写入，
**请勿手改**：手改会在下次安装时被覆盖，并让仓库与上游漂移。

- 上游：技能的 `entry-context-budget/scripts/`
- 更新：拿到新版技能目录后重跑 `install-print-hook.sh`（幂等，可反复执行）
- 校验：`install-print-hook.sh --check`
- 定位：**这不是门禁**。它把入口文档排成 A4 PDF、报页数（给人一个能感觉到的刻度），
  并报出「排版开销」＝实排页数 − 算术页数。它挂在 post-commit，永不阻断任何提交。
- 依赖：无头浏览器（`CHROME_PATH` 或自动探测）；缺了就跳过并说明，不静默假装成功。
- 产出：`<仓库>/.git/entry-doc-pdf/`（不进版本控制），每个文档名滚动保留最近 10 份。
NOTICEEOF
fi

if [ ! -f "$HOOK" ]; then
  printf '#!/usr/bin/env bash\n# 由 agent-entry-governance 技能 create 的钩子（原先无 post-commit）\nset -uo pipefail\n\n' > "$HOOK"
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
echo "[print-install]    自检：bash $0 --repo $REPO --check"
exit 0
