# agent-entry-governance

**Stop your `AGENTS.md` from eating the context window.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Python 3.8+](https://img.shields.io/badge/python-3.8%2B-blue.svg)](#运行环境)
[![Dependencies: none](https://img.shields.io/badge/dependencies-none-brightgreen.svg)](#运行环境)

`AGENTS.md`、`CLAUDE.md` 这类入口文档，在每次会话开头被整份注入。项目长大以后它往往长成一部百科，代理开一次工就得先重读一遍。这个技能给入口文档定下 token 预算，把超出预算的知识沉成指针，再在提交点装一道守卫：超限的提交会被拦下。

度量器和守卫都是 Python 3.8 标准库，不联网、不读环境变量、不写文件。守卫本体随仓库入库，别人 clone 下来照样生效。

## 快速开始

装进 Agent 框架：把整个 `agent-entry-governance/` 目录放进 skills 目录即可。框架读各个 `SKILL.md` 的 frontmatter 决定何时加载，使用的人不用记命令。

想手动操作：

```bash
# 量一次入口文档（只读，不阻断）
python3 entry-doc-governance/scripts/measure.py AGENTS.md

# 装到提交点（幂等，可反复执行；守卫本体入库，clone 后仍有效）
bash entry-doc-governance/scripts/install-hook.sh --repo /path/to/repo

# 校验安装状态
bash entry-doc-governance/scripts/install-hook.sh --repo /path/to/repo --check
```

阈值不抄进文档，随时问度量器要权威值：

```bash
python3 entry-doc-governance/scripts/measure.py --print-policy
```

参数细节看各脚本的 `--help` 和文件头。

## 越线会看到什么

守卫和度量器读同一份策略，下面是真实输出。

超上限的文件被拒绝提交，退出码 1：

```
[guard] ❌ AGENTS.md 工作区版 已达约 5869 token（上限 3000），拒绝提交
[guard]    请先精简：指针化下沉 docs/，或归档历史内容（精简动作：指针化下沉 / 归档历史 / 职责切割 / 拆分）
```

合规的文件只报个数：

```
[guard] ✅ SKILL.md 工作区版约 780 token（距提醒线 1720）
```

退出码有三档，调用方按 fail-closed 处理：

| 码 | 含义 | 动作 |
|---|---|---|
| 0 | 全部在阈值内 | 放行 |
| 1 | 超上限、用法错误，或校验无法完成 | 拒绝 |
| 2 | 只在提醒线以上 / gzip 冗余 | 放行，并打印告警 |

`--staged` 量的是暂存区里的版本，也就是即将提交的那份。文件没进本次提交就显式跳过，不回退去量工作区版；暂存版与 HEAD 逐字节相同（本次没改它）也跳过，免得一个存量超限的文件把仓库里无关的提交全锁死。改了它就得合规。

## 三条边界

安全与不可逆约束（敏感资产、关键路径、fail-closed 关口）照原样写死，不因为追求好看就软化。事实、路径、命令、判断照准写，不为顺口变模糊。文档不能长到挤爆代理的默认上下文，超了就把细节搬走，不删真相。

## 三个成员

| 成员 | 管什么 |
|---|---|
| `entry-doc-governance` | 度量与阈值、安全下沉（指针可达、无第二事实源）、把守卫装成必被执行的关口 |
| `entry-card-craft` | 结构与排版：以人为本的判决、简历与 README 的分工、实排页面终审 |
| `entry-deai-style` | 文风：去 AI 味，完整标准在上游 `humanizer-zh` |

聚合层的 `SKILL.md` 只放索引、分工与跨成员约束，不复制成员内容。

## 目录

```
SKILL.md                              聚合索引：三条边界、分工秩序、关键词路由
entry-deai-style/                     ① 去 AI 味（上游 humanizer-zh，内置降级四条）
│   └── SKILL.md
entry-card-craft/                     ② 简历式优化：以人为本的判决、排版、页面终审
│   ├── SKILL.md
│   ├── references/philosophy.md      设计理据：为什么这么定，按需加载
│   ├── references/final-audit.md     终审清单（叙事 / 排版 / 文风 / 调性），终审时才读
│   └── scripts/
│       ├── print-entry-doc.sh        可选层：把入口文档排成 A4 PDF，报页数与排版开销
│       └── install-print-hook.sh     可选层安装器：幂等把打印挂到 post-commit（永不阻断提交）
entry-doc-governance/                 ③ 文档治理：度量、阈值、安全下沉、提交点守卫
    ├── SKILL.md
    ├── references/final-audit.md     终审清单（关口 / 事实源 / 度量 / 搬迁），终审时才读
    └── scripts/
        ├── measure.py                度量器：只读，报告 token 与 gzip 密度
        ├── guard.py                  判据：退出码 0 / 1 / 2，供关口 fail-closed 调用
        └── install-hook.sh           安装器：幂等把守卫装进 git 仓库的提交点
```

技能按三层渐进披露：frontmatter 决定框架何时加载，正文放策略与工作流，`references/` 按需加载。

## 工作流

1. 改入口文档前后各量一次，越线先精简再提交。
2. 判定去留。每次任务都要读到、又无法从代码派生的，留在入口；只有部分任务需要的，下沉成指针；能从代码或工具直接派生的，删掉；历史背景和失效内容，归档。
3. 下沉前先审接收方：目标存在、自身可用，且还没持有这条事实。
4. 迁移后报账：搬走了什么、搬到哪、入口现在怎么找到它。
5. 交付前过终审清单，两个成员各有一份。

## 我们自己也这么用

本仓四份入口文档的实测值（`measure.py`，2026-09-17）：

| 文档 | token | 状态 |
|---|---|---|
| `SKILL.md` | 1544 | 距提醒线 956 |
| `entry-deai-style/SKILL.md` | 780 | 距提醒线 1720 |
| `entry-card-craft/SKILL.md` | 2103 | 距提醒线 397 |
| `entry-doc-governance/SKILL.md` | 2593 | 提醒线以上，距上限 407 |

`entry-doc-governance` 的正文停在提醒线以上、上限以内，是有意留的。按本技能自己的代价结构，成员 `SKILL.md` 属于取用层，框架需要时才加载，每次注入的只有聚合层 frontmatter 那一段，所以判决看的是加载时机，不是一个孤立的数字。

## 边界

只管代理入口文档，以及安全下沉入口知识所需的文档关系，不管整个仓库的通用文档生命周期。

渲染层（`entry-card-craft/scripts/print-entry-doc.sh`）是可选层：依赖无头浏览器，不进判据、不阻断任何流程，缺依赖就显式跳过并说明这次没看到页面。

## 运行环境

- 度量器与判据（`entry-doc-governance`）：Python 3.8+ 标准库，不联网、不写文件、不依赖版本控制（版本控制只用于取将生效的版本）。
- 安装器：往 git 仓库的提交点装守卫，需要 git。
- 渲染层（`entry-card-craft`）：可选，依赖无头浏览器。
- 去味（`entry-deai-style`）：依赖上游技能 `humanizer-zh`，缺席时用内置降级四条并显式声明。
- 入口文档的命名和层数由所在环境声明。脚本默认发现 `AGENTS.md` / `AGENT.md`，其他命名用 `--names` 注入，不改源码。

前提缺失时必须显式响应，不得静默降级。

## 可移植性

可移植单元是整个目录。支持 Skills 的框架直接放进 skills 目录读 `SKILL.md`；不支持的框架把 `SKILL.md` 正文塞进系统提示词，脚本照常能单独跑。有版本控制就把守卫装到提交点；只有流水线或启动入口，就在其中 fail-closed 调用 `guard.py`；一个关口都没有，就退化为入口处的显式提示，不假装已经装上了。

## 参与

issue 和 PR 都欢迎，中英文都行。改 `SKILL.md` 或脚本之后，提交前跑一次 `python3 entry-doc-governance/scripts/measure.py SKILL.md entry-*/SKILL.md`，本仓自己的守卫也会在提交点拦一道。

## 许可

MIT，见 [LICENSE](LICENSE)。
