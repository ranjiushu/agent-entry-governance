#!/usr/bin/env bash
# serve-entry-doc.sh —— 把查看模式产出的图片挂成静态服务，给人看那一页页页面
#
# 为什么需要它
#   本地路径（`/abs/x.png`、`file:///…`、相对路径）在很多 markdown 渲染器里加载不出来，
#   手机上的聊天 App 尤其如此；http 图片才渲染。所以「把人能看的页面递出去」这件事，
#   最后一步是：把这个目录挂在一个手机/浏览器够得着的地址上，然后把 URL 贴出去。
#   服务是长驻进程——请在你自己的持久终端里跑，别塞进任何钩子或流水线。
#
# 用法
#   serve-entry-doc.sh                      # 服务查看模式的默认产出目录，前台阻塞，Ctrl-C 停
#   serve-entry-doc.sh --dir DIR            # 指定目录（查看模式当时用的那个 --out）
#   serve-entry-doc.sh --port 8899 --bind 0.0.0.0
#   serve-entry-doc.sh --host 10.0.0.5      # 显式指定要贴出去的地址（默认自动挑第一个非回环 IPv4）
#   serve-entry-doc.sh --print              # 只打印地址与引用行，不起服务（给 agent 拼引用用）
#
# 产出：目录列表 + 每个图片一份可直接粘进 markdown 的 URL
# 退出码：0 正常结束（Ctrl-C / --print）/ 1 用法错误或目录不存在
set -uo pipefail
TAG="[serve-entry-doc]"

DIR=""; PORT=8899; BIND=0.0.0.0; HOST=""; PRINT_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)   DIR="${2:-}"; shift 2 ;;
    --port)  PORT="${2:-}"; shift 2 ;;
    --bind)  BIND="${2:-}"; shift 2 ;;
    --host)  HOST="${2:-}"; shift 2 ;;
    --print) PRINT_ONLY=1; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{print; next} {exit}' "$0"; exit 0 ;;
    *) echo "$TAG 未知参数：$1（--help 看用法）" >&2; exit 1 ;;
  esac
done

case "$PORT" in ''|*[!0-9]*) echo "$TAG --port 需要端口号：$PORT" >&2; exit 1 ;; esac

# 默认目录 = 查看模式的默认产出位，其次当前目录
if [ -z "$DIR" ]; then
  _root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_root" ] && [ -d "$_root/.git/entry-doc-pdf" ]; then
    DIR="$_root/.git/entry-doc-pdf"
  else
    DIR="$PWD"
  fi
fi
[ -d "$DIR" ] || { echo "$TAG ❌ 目录不存在：$DIR（查看模式时用 --out 指定的那个）" >&2; exit 1; }
DIR="$(cd "$DIR" && pwd)"

# 挑一个「别人够得着」的地址：显式 --host 优先，否则按候选列表挑。
# 候选来自本机所有非回环 IPv4；容器网桥（docker 默认 172.17–172.31）排到最后——
# 它在列表里往往排第一，但那是沙盒内部地址，手机上够不着。
CONTAINER_RE='^172\.(1[7-9]|2[0-9]|3[01])\.'
ip_candidates() {
  { hostname -I 2>/dev/null | tr ' ' '\n'
    ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1
    ipconfig getifaddr en0 2>/dev/null; ipconfig getifaddr en1 2>/dev/null
  } | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | grep -v '^127\.' | grep -v '^169\.254\.' | awk '!seen[$0]++'
}
IPLIST="$(ip_candidates)"
if [ -z "$HOST" ]; then
  HOST="$(printf '%s\n' "$IPLIST" | grep -vE "$CONTAINER_RE" | head -1)"
  [ -n "$HOST" ] || HOST="$(printf '%s\n' "$IPLIST" | head -1)"
fi
if [ -z "$HOST" ]; then
  echo "$TAG ⚠️  没自动认出对外地址（可加 --host <地址>）；下面只给本机回环的引用。" >&2
  HOST="127.0.0.1"
fi
BASE="http://$HOST:$PORT"
# 备选：够不着就换一个（沙盒里常见 tailnet 与内网两个段）
ALTS="$(printf '%s\n' "$IPLIST" | grep -vxF "$HOST" | grep -vE "$CONTAINER_RE" | head -2 | tr '\n' ' ')"

echo "$TAG 目录：$DIR"
echo "$TAG 地址：$BASE/"
[ -n "$ALTS" ] && echo "$TAG 备选（够不着就换）：$(printf '%s\n' $ALTS | sed "s|^|http://|; s|$|:$PORT/|" | tr '\n' ' ')"

# 图片引用：一行一张，供直接粘进 markdown（按文件名排序，页面顺序稳定）
_n=0
while IFS= read -r f; do
  _n=$((_n + 1))
  if [ "$_n" -le 60 ]; then echo "$TAG   ![]($BASE/$(basename "$f"))"; else echo "$TAG   …（更多图片略）"; break; fi
done < <(find "$DIR" -maxdepth 1 -type f -name '*-p[0-9]*.png' 2>/dev/null | sort)
[ "$_n" = 0 ] && echo "$TAG ⚠️  这个目录里没有查看模式产出的图片（*-pN.png）；先跑 view-entry-doc.sh" >&2

if [ "$PRINT_ONLY" = 1 ]; then exit 0; fi

echo "$TAG 起服务（前台；Ctrl-C 停）："
echo "$TAG   python3 -m http.server $PORT --bind $BIND --directory \"$DIR\""
exec python3 -m http.server "$PORT" --bind "$BIND" --directory "$DIR"
