#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AGENTS.md 信息密度度量 —— 零依赖、只读、可移植。

定位
    AI 代理入口文档（AGENTS.md / AGENT.md）的体积与信息密度**度量器**。
    本文件是阈值与 token 近似算法的**唯一事实源**：SKILL.md、git 钩子、CI
    都引用它，不要在任何别处再抄一份数字。权威值随时可查：

        python3 measure.py --print-policy

用法
    python3 measure.py                          # 当前目录自动发现 AGENTS.md / AGENT.md
    python3 measure.py path/to/AGENTS.md ...    # 指定文件（可多个，可跨仓库）
    python3 measure.py --staged                 # 量 git 暂存区版本（即将提交的内容）
    python3 measure.py --json                   # 机器可读
    python3 measure.py --print-policy           # 输出权威阈值

依赖
    Python 3.8+ 标准库。无网络、无第三方包、不读环境变量、不写任何文件。

退出码
    0 = 度量完成（**无论是否超限**）—— 本工具只报告，不判定成败。
    1 = 用法错误或文件读不到（argparse 错误已被钳制为 1，不用 Python 默认的 2，
        避免与 guard.py「2 = 仅提醒」的语义撞车）。
    强制拦截由 guard.py 负责；不要把 measure.py 当门禁（它永远不该阻断提交）。
"""

import argparse
import gzip
import json
import os
import re
import subprocess
import sys


# ── 输出编码兜底（纯展示层，不参与任何判定）──────────────────────────
# Windows 控制台编码常为 GBK(cp936)，而 Python 在 Windows 上 stdout 的默认
# errors 是 surrogateescape：打印 ❌ / ⚠️ / ⏭️ 这类 GBK 外字符会直接抛
# UnicodeEncodeError，**整份报告一起丢**（实测：文档越线时反而看不到结论）。
# 对策：按「当前输出流能不能编码」把装饰符号降级为 ASCII，并给两个流装上
# backslashreplace 兜底（覆盖 JSON 等其它输出路径）。UTF-8 终端下行为完全不变。
_ASCII_FALLBACK = {
    "✅": "[OK]", "⚠️": "[!] ", "⚠": "[!] ",
    "❌": "[X] ", "⏭️": "[--]", "⏭": "[--]",
}


def safe_text(s, stream=None):
    """把当前输出流编码不了的装饰符号降级为 ASCII；其余字符原样返回。"""
    stream = stream if stream is not None else sys.stdout
    try:
        s.encode(getattr(stream, "encoding", None) or "ascii")
        return s
    except (UnicodeEncodeError, LookupError):
        pass
    for _k, _v in _ASCII_FALLBACK.items():
        s = s.replace(_k, _v)
    return s


for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="backslashreplace")
    except (AttributeError, ValueError):
        pass


class _Parser(argparse.ArgumentParser):
    """argparse 默认以 rc=2 报用法错误；钳制为 1，与 docstring 的退出码约定一致，
    也避免调用方把「用法错误」误当 guard.py 的「2 = 仅提醒，放行」。"""

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(1, "%s: error: %s\n" % (self.prog, message))

# ── 策略：唯一事实源（改阈值只改这里）─────────────────────────────────
POLICY = {
    "warn_tokens": 2500,     # 超过 → 提醒，不阻断
    "max_tokens": 3000,      # 超过 → 拒绝提交
    "max_gzip_bytes": 5000,  # 超过 → 冗余告警（净信息量探针）
}

POLICY_DOC = {
    "warn_tokens": "超过 → 提醒（不阻断）",
    "max_tokens": "超过 → 拒绝提交",
    "max_gzip_bytes": "超过 → 冗余 / 灌水告警",
}

# CJK 统一表意文字（含扩展 A）+ CJK 标点 + 全角字符 + 常用中文弯引号/破折号。
# 盲区提醒：全角标点（，。、；）在真实 tokenizer 里约 1 token / 个，必须算进 CJK 桶，
# 否则落入 ASCII 4:1 桶会被低估 4 倍（中文文档标点占比 15–25%，低估会推迟越线信号）。
_CJK_RANGES = "\u4e00-\u9fff\u3400-\u4dbf\u3000-\u303f\uff00-\uff65\u2018-\u201d\u2013\u2014"
CJK_RE = re.compile("[%s]" % _CJK_RANGES)
STRIP_RE = re.compile("[%s\\s]" % _CJK_RANGES)

DISCOVER_NAMES = ("AGENTS.md", "AGENT.md")


# ── 度量内核（guard.py 也 import 这里，别另写一份）────────────────────
def count_tokens(text):
    """token 近似（零依赖）：CJK 字与全角标点每字 ≈ 1 token、ASCII 每 4 字符 ≈ 1 token、每换行 ≈ 1 token。

    这套近似对应 Agent 真实读取成本；字节数对中文失真约 3 倍，故不作主判据。
    """
    cjk = len(CJK_RE.findall(text))
    ascii_chars = len(STRIP_RE.sub("", text))
    return int(cjk + ascii_chars / 4 + text.count("\n")), cjk, ascii_chars


def measure_bytes(raw):
    """度量一段字节（文件内容或 git blob），返回纯数据字典。"""
    text = raw.decode("utf-8", errors="replace")
    tokens, cjk, ascii_chars = count_tokens(text)
    gz = len(gzip.compress(raw, 9))
    return {
        "bytes": len(raw),
        "lines": text.count("\n"),
        "tokens": tokens,
        "cjk_chars": cjk,
        "ascii_chars": ascii_chars,
        "gzip_bytes": gz,
        "gzip_ratio": round(gz / len(raw), 3) if raw else 0.0,
    }


def verdict(rec, policy=None):
    """按策略给出 (level, 中文说明)。level: ok / warn / over。只报告，不退出。"""
    p = policy or POLICY
    gz_bad = rec["gzip_bytes"] > p["max_gzip_bytes"]
    if rec["tokens"] > p["max_tokens"]:
        level = "over"
        head = "❌ 超限：token %d > %d" % (rec["tokens"], p["max_tokens"])
    elif rec["tokens"] > p["warn_tokens"]:
        level = "warn"
        head = "⚠️ 提醒线以上（距上限 %d）" % (p["max_tokens"] - rec["tokens"])
    elif gz_bad:
        level = "warn"
        head = "⚠️ token 合规（距提醒线 %d）" % (p["warn_tokens"] - rec["tokens"])
    else:
        level = "ok"
        head = "OK（距提醒线 %d）" % (p["warn_tokens"] - rec["tokens"])
    if gz_bad:
        head += "；gzip %d > %d，疑似重复/灌水" % (rec["gzip_bytes"], p["max_gzip_bytes"])
    return level, head


# ── 取内容：优先 git 暂存区（提交的是暂存区，不是工作区）──────────────
def read_staged(path):
    """返回 (raw, note)。取不到暂存版时 raw 为 None，note 说明原因。

    note 取值（guard.py 据此区分「可跳过的未暂存」与「前提缺失」）：
    "git 不可用" / "非 git 工作区" / "不在该仓库内" / "git show 失败" / "暂存区无此文件"。
    """
    d = os.path.dirname(os.path.abspath(path)) or "."
    try:
        root = subprocess.run(
            ["git", "-C", d, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None, "git 不可用"
    if root.returncode != 0:
        return None, "非 git 工作区"
    repo = root.stdout.strip()
    rel = os.path.relpath(os.path.abspath(path), repo)
    if rel.startswith(".."):
        return None, "不在该仓库内"
    try:
        show = subprocess.run(
            ["git", "-C", repo, "show", ":" + rel],
            capture_output=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None, "git show 失败"
    if show.returncode != 0:
        return None, "暂存区无此文件"
    return show.stdout, "staged"


def read_head(path):
    """返回 (raw, note)：path 在 HEAD 中的版本（存量基线）。

    取不到时 raw 为 None。note = "HEAD 无此文件" 表示新增文件（无基线，照常校验）；
    其余 note 与 read_staged 同义（git 前提缺失）。
    """
    d = os.path.dirname(os.path.abspath(path)) or "."
    try:
        root = subprocess.run(
            ["git", "-C", d, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None, "git 不可用"
    if root.returncode != 0:
        return None, "非 git 工作区"
    repo = root.stdout.strip()
    rel = os.path.relpath(os.path.abspath(path), repo)
    if rel.startswith(".."):
        return None, "不在该仓库内"
    try:
        show = subprocess.run(
            ["git", "-C", repo, "show", "HEAD:" + rel],
            capture_output=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None, "git show 失败"
    if show.returncode != 0:
        return None, "HEAD 无此文件"
    return show.stdout, "HEAD"


# ── 输出 ─────────────────────────────────────────────────────────────
def _dwidth(s):
    """终端显示宽度：CJK / 全角算 2 列。"""
    return sum(2 if ord(c) > 0x2E7F else 1 for c in s)


def _pad(s, w):
    return s + " " * max(0, w - _dwidth(s))


def render_table(rows):
    headers = ["文件", "来源", "字节", "行", "token", "gzip", "密度", "状态"]
    table = [headers] + [[
        r["name"], r["source"], str(r["bytes"]), str(r["lines"]),
        str(r["tokens"]), str(r["gzip_bytes"]), "%.0f%%" % (r["gzip_ratio"] * 100),
        r["verdict_text"],
    ] for r in rows]
    widths = [max(_dwidth(row[i]) for row in table) for i in range(len(headers))]
    out = []
    for i, row in enumerate(table):
        out.append("  ".join(_pad(c, widths[j]) for j, c in enumerate(row)).rstrip())
        if i == 0:
            out.append("  ".join("-" * w for w in widths))
    return "\n".join(out)


def print_policy(stream=sys.stdout):
    print("AGENTS.md 信息密度策略（权威值，来自 scripts/measure.py 的 POLICY）", file=stream)
    for k, v in POLICY.items():
        print("  %-15s %-6s %s" % (k, v, POLICY_DOC.get(k, "")), file=stream)
    print("token 近似：CJK 字与全角标点 1 字 + ASCII 1/4 字符 + 换行 1（字节数对中文失真约 3 倍，不作主判据）",
          file=stream)
    print("改阈值只改 measure.py 的 POLICY；文档与钩子请引用 --print-policy 而非抄数字",
          file=stream)


def main(argv=None):
    ap = _Parser(
        description="AGENTS.md 信息密度度量（只读，不阻断）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("paths", nargs="*", help="待度量文件；省略则自动发现入口文档（见 --names）")
    ap.add_argument("--names", default=None,
                    help="自动发现的入口文档名（逗号分隔），默认 %s" % ",".join(DISCOVER_NAMES))
    ap.add_argument("--staged", action="store_true", help="优先量 git 暂存区版本（即将提交的内容）")
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--print-policy", action="store_true", help="只输出权威阈值后退出")
    ap.add_argument("--warn-tokens", type=int, default=POLICY["warn_tokens"])
    ap.add_argument("--max-tokens", type=int, default=POLICY["max_tokens"])
    ap.add_argument("--max-gzip", type=int, default=POLICY["max_gzip_bytes"])
    args = ap.parse_args(argv)

    if args.print_policy:
        print_policy()
        return 0

    policy = {
        "warn_tokens": args.warn_tokens,
        "max_tokens": args.max_tokens,
        "max_gzip_bytes": args.max_gzip,
    }

    discover_names = tuple(args.names.split(",")) if args.names else DISCOVER_NAMES
    targets = [os.path.abspath(p) for p in args.paths]
    if not targets:
        targets = [os.path.abspath(n) for n in discover_names if os.path.isfile(n)]
    if not targets:
        print("[measure] 未指定文件，且当前目录没有 %s" % " / ".join(discover_names), file=sys.stderr)
        print("[measure] 用法：python3 measure.py [--staged] [--json] <文件>...", file=sys.stderr)
        return 1

    rows, failed = [], False
    for path in targets:
        raw, source = None, "worktree"
        if args.staged:
            raw, note = read_staged(path)
            if raw is None:
                print("[measure] %s 取暂存版失败（%s）→ 回退工作区文件" % (path, note), file=sys.stderr)
            else:
                source = note  # "staged"
        if raw is None:
            try:
                with open(path, "rb") as f:
                    raw = f.read()
            except OSError as e:
                print("[measure] 读不到 %s（%s）" % (path, e.strerror or e), file=sys.stderr)
                failed = True
                continue
        rec = measure_bytes(raw)
        level, text = verdict(rec, policy)
        rel = os.path.relpath(path, os.getcwd())
        rec.update({
            "path": path,
            # 短名优先：相对路径太长时退回 basename（绝对路径只会更长，纯属反向优化）
            "name": rel if _dwidth(rel) <= 40 else os.path.basename(path),
            "source": source,
            "level": level,
            "verdict_text": text,
        })
        rows.append(rec)

    if failed and not rows:
        return 1

    if args.json:
        print(safe_text(json.dumps({"policy": policy, "files": rows}, ensure_ascii=False, indent=2)))
    else:
        print(safe_text(render_table(rows)))
        worst = [r for r in rows if r["level"] != "ok"]
        if worst:
            print()
            print("需处理 %d 个：%s" % (len(worst), "、".join(r["name"] for r in worst)))
            print("精简动作见 SKILL.md §三；阈值权威值见 --print-policy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
