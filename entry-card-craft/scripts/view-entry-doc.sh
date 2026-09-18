#!/usr/bin/env bash
# view-entry-doc.sh —— 查看入口文档：排成 A4 页面、导出逐页图片，并生成引用它们的 markdown
#
# 定位
#   这是打印层（判决层）的**查看模式**入口：一份薄壳，真正实现在同目录
#   print-entry-doc-typst.sh 的 --images。只做转发、不另写一份，是因为取档（std/fit）、
#   页数判断、Typst 版本钉死都只该有一处实现——查看和打印必须看到同一批页面，
#   否则「看页面」会变成第二个判据。
#
# 用法（与打印层一致，另加 --ppi）
#   view-entry-doc.sh                        # 自动发现 AGENTS.md / AGENT.md
#   view-entry-doc.sh AGENTS.md scripts/AGENTS.md
#   view-entry-doc.sh --out DIR --ppi 200    # 图片分辨率，默认 140（A4 约 1160 px 宽）
#
# 产出：<输出目录>/<文档键>-p<页号>.png + INDEX.md（用 markdown 引用每页图片，路径相对本文件）
# 退出码：0 完成（含没排成）/ 1 用法错误。缺 Typst 时显式说明「这次没看到页面」，不静默跳过。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/print-entry-doc-typst.sh" --images "$@"
