---
name: agent-entry-governance
description: 控制 AGENTS.md / CLAUDE.md 这类 Agent 入口文档的长度和信息密度：设定上下文预算，超出的知识下沉成指针，并在提交点装守卫拦截超限内容。关键词：AGENTS.md, AGENT.md, CLAUDE.md, 入口文档治理, 上下文预算, token, 信息密度, 精简, 指针化下沉, 拆分, 归档, 门禁, pre-commit。
---

# agent-entry-governance（Agent 入口文档治理 · 技能聚合）

让入口文档成为项目／工作区的「简历」——简洁、美观、优雅；同时对机器友好：不无限膨胀（不挤爆上下文）、不腐烂成过时副本、不出现第二处事实源、不为了好看牺牲精度。
与分支交付类技能的分工：那个管「分支怎么交付」，本技能管「入口文档怎么不烂」，不重叠。

组织原则：聚合层只做索引与分工，不复制成员内容；成员只做策略（不变量）加机制（可替换实现），策略层不写环境专名。

## 一、关键词速查

| 你说的场景 | 跳到 |
|---|---|
| 入口文档太长 / 要不要精简 / 加内容会不会超限 | entry-context-budget |
| 量一下当前入口文档的体积与密度 | entry-context-budget（度量器） |
| 文档太杂、想拆 | entry-context-budget（精简动作 · 拆分） |
| 给仓库装文档门禁（关键路径上的关口） | entry-context-budget（安装器） |
| 把门禁搬到别的框架 / 别的运行环境 | entry-context-budget（可移植性） |
| 卡片读起来累 / 不好看 / 想做得优雅 | entry-context-budget（§〇 以人为本） |
| 给新项目、新工作区写一张入口卡（简历） | entry-context-budget（首部与 §〇） |
| 怕精简改坏精度、改出事实错误 | entry-context-budget（§〇 两条边界） |
| 拿不准写得好不好，想看成品 | entry-context-budget（人类刻度 · 实排页面） |
| 想知道为什么这么定 / 要改判据本身 | entry-context-budget/references/philosophy.md |
| 写入口文档时要文风标准 | entry-context-budget/references/style.md |

## 二、成员

| 子技能 | 用途 | 读取路径 |
|---|---|---|
| entry-context-budget | 入口文档的体积与信息密度治理：度量（token / gzip / 密度）、阈值判据、超限后的精简动作（指针化下沉、归档、职责切割、拆分）、把守卫装成必被执行的关口 | agent-entry-governance/entry-context-budget/SKILL.md |

## 三、调用方式

读 agent-entry-governance/entry-context-budget/SKILL.md 并按其中指令执行；脚本用相对路径调用，精确用法以其 --help / 文件头为准。

## 四、运行环境

- 度量器与判据（measure.py / guard.py）：纯标准库，无第三方依赖、不联网、不读环境变量、不依赖版本控制（版本控制只是取将生效版本的增强；有 git 时 guard.py --staged 会用它取暂存版与存量基线）。
- 安装器（install-hook.sh）是例外：它把守卫装进 git 仓库，依赖 git、写文件、幂等，上述两条不适用于它。
- 渲染与它的安装器（print-entry-doc.sh / install-print-hook.sh）同属例外，且是**可选层**：依赖无头浏览器，不进判据、不阻断任何流程，缺依赖就显式跳过并说明。

前提缺失时必须显式响应，不得静默降级。

## 五、权威来源与自身一致性

- 策略的权威源是各成员自身的判据实现（如 --print-policy）；文档与关口一律引用，不抄数字。
- 本目录的 canonical 位置与同步机制由环境声明；skills 目录下通常是副本，因此只描述随附在本目录里的产物，副本没随附的工具就不承诺它的用法。
- 聚合层不复制成员内容：同一事实只出现在一处，这里只留指针。
