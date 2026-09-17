#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AGENTS.md 信息密度守卫 —— 判据 + 退出码（强制层）。

分层
    measure.py = 度量（只读，永不阻断）
    guard.py   = 判据（本文件；算法与阈值由 measure.py 提供，**不另存一份数字**）

用法
    python3 guard.py --staged                     # 钩子里用：量暂存区（即将提交的版本）
    python3 guard.py path/to/AGENTS.md            # 量指定文件
    python3 guard.py --max-tokens 4000 <文件>      # 覆盖阈值（仅确需覆盖时；默认值在 measure.py）
    python3 guard.py --names CLAUDE.md --staged   # 入口文档名由环境声明时用 --names 注入

--staged 的语义（量「将生效版本」，不静默换对象）
    · 文件**未纳入本次提交**（暂存区无此文件）→ 显式跳过并说明，**不**回退去量工作区版。
    · 暂存版与 HEAD **逐字节相同**（本次未改动）→ 存量豁免，显式跳过；
      避免存量超限文件把仓库里所有无关提交永久锁死。一旦改动它，就必须合规。
    · git 前提缺失（git 不可用 / 非 git 工作区 / 不在仓库内）→ fail-closed 拒绝。

退出码（调用方必须按此 **fail-closed** 处理）
    0  全部在阈内                    → 放行
    1  存在超上限、用法错误，或校验无法完成 → **拒绝**
    2  仅提醒线以上 / gzip 冗余       → 放行（打印告警）
    注：argparse 的用法错误已被钳制为 rc=1（Python 默认是 2，会与「仅提醒」撞车导致静默放行）。

依赖：Python 3.8+ 标准库；需与 measure.py 同目录。
"""

import argparse
import os
import sys

sys.dont_write_bytecode = True  # 不在调用方仓库里落 __pycache__（守卫按需运行，无需缓存）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure  # noqa: E402  （同目录；阈值与 token 算法的唯一事实源）

TAG = "[guard]"
# 自包含提示：守卫会被装进别的仓库，clone 它的人没有技能目录，绝不指向库外路径。
HINT = "（精简动作：指针化下沉 / 归档历史 / 职责切割 / 拆分）"


def _emit(msg):
    r"""输出到 stderr；按 stderr 的编码把装饰符号降级为 ASCII。

    Windows 控制台常为 GBK，✅ / ❌ / ⏭️ 无法编码，默认会退化成 `\u2705` 这种
    转义字面量（观感差）。降级逻辑与符号表由 measure.safe_text 统一提供（单一事实源）。
    """
    print(measure.safe_text(msg, sys.stderr), file=sys.stderr)


def load(path, staged):
    """返回 (raw, source_label, skip_reason)。

    raw 为 None 且 skip_reason 非空 → 显式跳过（不算失败）；
    raw 为 None 且 skip_reason 为空 → source_label 是失败原因（fail-closed）。
    """
    if staged:
        raw, note = measure.read_staged(path)
        if raw is None:
            if note == "暂存区无此文件":
                return None, "", "未纳入本次提交（暂存区无此文件）"
            # git 前提缺失：策略要求显式响应，不静默换个对象来量 → 拒绝
            return None, "取暂存版失败（%s）" % note, ""
        head, hnote = measure.read_head(path)
        if head is not None and head == raw:
            return None, "", "暂存版与 HEAD 相同（本次未改动，存量豁免）"
        return raw, "暂存版" + ("（新增，HEAD 无基线）" if hnote == "HEAD 无此文件" else ""), ""
    try:
        with open(path, "rb") as f:
            return f.read(), "工作区版", ""
    except OSError as e:
        return None, e.strerror or str(e), ""


def main(argv=None):
    ap = measure._Parser(
        description="AGENTS.md 信息密度守卫（内核来自 measure.py）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("paths", nargs="*", help="待校验文件；省略则自动发现入口文档（见 --names）")
    ap.add_argument("--names", default=None,
                    help="自动发现的入口文档名（逗号分隔），默认 %s" % ",".join(measure.DISCOVER_NAMES))
    ap.add_argument("--staged", action="store_true", help="量 git 暂存区版本（钩子里必须用）")
    ap.add_argument("--quiet", action="store_true", help="通过时不输出任何内容")
    ap.add_argument("--warn-tokens", type=int, default=measure.POLICY["warn_tokens"])
    ap.add_argument("--max-tokens", type=int, default=measure.POLICY["max_tokens"])
    ap.add_argument("--max-gzip", type=int, default=measure.POLICY["max_gzip_bytes"])
    args = ap.parse_args(argv)

    policy = {
        "warn_tokens": args.warn_tokens,
        "max_tokens": args.max_tokens,
        "max_gzip_bytes": args.max_gzip,
    }

    discover_names = tuple(args.names.split(",")) if args.names else measure.DISCOVER_NAMES
    targets = [os.path.abspath(p) for p in args.paths]
    if not targets:
        targets = [os.path.abspath(n) for n in discover_names if os.path.isfile(n)]
    if not targets:
        return 0  # 本仓库没有入口文档：无事可做，不是错误

    worst = 0
    for path in targets:
        name = os.path.basename(path)
        raw, label, skip = load(path, args.staged)
        if raw is None and skip:
            if not args.quiet:
                _emit("%s ⏭️  %s %s —— 跳过校验" % (TAG, name, skip))
            continue
        if raw is None:
            # fail-closed：校验无法完成 → 拒绝（静默放行等于门禁变哑）
            _emit("%s ❌ %s 校验无法完成：%s —— 拒绝（fail-closed）" % (TAG, name, label))
            worst = 1
            continue

        rec = measure.measure_bytes(raw)
        level, _ = measure.verdict(rec, policy)

        if rec["tokens"] > policy["max_tokens"]:
            _emit("%s ❌ %s %s 已达约 %d token（上限 %d），拒绝提交" %
                  (TAG, name, label, rec["tokens"], policy["max_tokens"]))
            _emit("%s    请先精简：指针化下沉 docs/，或归档历史内容%s" % (TAG, HINT))
            worst = max(worst, 1)
            continue

        if rec["tokens"] > policy["warn_tokens"]:
            _emit("%s ⚠️  %s %s 已达约 %d token（提醒线 %d，上限 %d）——建议精简后再提交%s" %
                  (TAG, name, label, rec["tokens"], policy["warn_tokens"], policy["max_tokens"], HINT))
            worst = max(worst, 2)

        if rec["gzip_bytes"] > policy["max_gzip_bytes"]:
            _emit("%s ⚠️  %s gzip 后 %d 字节（>%d，冗余探针）——检查是否有重复/灌水内容" %
                  (TAG, name, rec["gzip_bytes"], policy["max_gzip_bytes"]))
            worst = max(worst, 2)

        if level == "ok" and not args.quiet:
            _emit("%s ✅ %s %s约 %d token（距提醒线 %d）" %
                  (TAG, name, label, rec["tokens"], policy["warn_tokens"] - rec["tokens"]))

    return worst


if __name__ == "__main__":
    sys.exit(main())
