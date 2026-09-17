---
name: agent-entry-governance
description: 控制 AGENTS.md / CLAUDE.md 这类 Agent 入口文档的长度和信息密度：设定上下文预算，超出的知识下沉成指针，并在提交点装守卫拦截超限内容。关键词：AGENTS.md, AGENT.md, CLAUDE.md, 入口文档治理, 上下文预算, token, 信息密度, 精简, 指针化下沉, 拆分, 归档, 门禁, pre-commit。
---

# agent-entry-governance（Agent 入口文档治理 · 技能聚合）

让入口文档成为项目／工作区的「简历」——简洁、美观、优雅；同时对机器友好：不无限膨胀（不挤爆上下文）、不腐烂成过时副本、不出现第二处事实源、不为了好看牺牲精度。

组织原则：聚合层只做索引、分工与跨成员约束，不复制成员内容；成员只做策略（不变量）加机制（可替换实现），策略层不写环境专名。

## 〇、三条边界（约束所有成员，不随「好看」让步）

**安全与不可逆约束**（敏感资产、关键路径、fail-closed 关口）照原样写死，不因可读性软化。**精度**不牺牲：事实、路径、命令、判断照准写，不为了顺口变模糊——文档的可信度就是它的功能。**上下文**不破坏：卡片不能长到挤爆 Agent 的默认上下文，超限走下沉（把细节搬走），不走删真相。

## 分工秩序

三个成员各司其职，但有序：治理是底线，简历式优化是在治理约束内做美——排版挣来的「愿意看」，不许用指针弹球和事实模糊来换。去味服务前两者：凡是写文档、改文档、终审文档的场景都可触发它。

## 一、关键词速查

| 你说的场景 | 跳到 |
|---|---|
| 入口文档太长 / 要不要精简 / 加内容会不会超限 | entry-doc-governance |
| 量一下当前入口文档的体积与密度 | entry-doc-governance（度量器） |
| 下沉后怕找不到、怕丢信息、怕出第二事实源 | entry-doc-governance（安全下沉） |
| 给仓库装文档门禁（关键路径上的关口） | entry-doc-governance（安装器） |
| 把门禁搬到别的框架 / 别的运行环境 | entry-doc-governance（可移植性） |
| 卡片读起来累 / 不好看 / 结构与排版 | entry-card-craft |
| 给新项目、新工作区写一张入口卡（简历） | entry-card-craft |
| 简历与 README 怎么分工 | entry-card-craft（代价结构与三测试） |
| 拿不准写得好不好，想看成品 / 实排页面 | entry-card-craft（渲染层 · 页面终审） |
| 这段文字像 AI 写的 / 去味 / 文风生硬 | entry-deai-style（上游 humanizer-zh） |
| 想知道为什么这么定 / 要改判据本身 | entry-card-craft/references/philosophy.md |

## 二、成员

| 子技能 | 用途 | 读取路径 |
|---|---|---|
| entry-deai-style | 去 AI 味：文风判据。完整标准在上游 humanizer-zh，本成员负责衔接治理流程并提供内置降级层 | agent-entry-governance/entry-deai-style/SKILL.md |
| entry-card-craft | 简历式优化：以人为本的判决（好看、易看、愿意看）、简历与 README 的分工、结构与排版、实排页面终审 | agent-entry-governance/entry-card-craft/SKILL.md |
| entry-doc-governance | 文档治理：度量（token / gzip / 密度）与阈值判据、超限后的安全下沉（指针可达、无第二事实源）、把守卫装成必被执行的关口 | agent-entry-governance/entry-doc-governance/SKILL.md |

## 三、调用方式

读对应成员的 SKILL.md 并按其中指令执行；脚本用相对路径调用，精确用法以其 --help / 文件头为准。

## 四、运行环境

- entry-doc-governance 的度量器与判据（measure.py / guard.py）：纯标准库，无第三方依赖、不联网、不读环境变量、不依赖版本控制（版本控制只是取将生效版本的增强）。安装器（install-hook.sh）是例外：它把守卫装进 git 仓库，依赖 git、写文件、幂等。
- entry-card-craft 的渲染层（print-entry-doc.sh / install-print-hook.sh）是**可选层**：依赖无头浏览器，不进判据、不阻断任何流程，缺依赖就显式跳过并说明。
- entry-deai-style 依赖上游技能 humanizer-zh；缺席时用内置降级层并显式声明。

前提缺失时必须显式响应，不得静默降级。

## 五、权威来源与自身一致性

- 阈值与算法的唯一事实源：entry-doc-governance 的度量实现（--print-policy）；文档与关口一律引用，不抄数字。
- 文风的完整标准：上游 humanizer-zh；本仓只留降级层，不抄第二份。
- 本目录的 canonical 位置与同步机制由环境声明；skills 目录下通常是副本，因此只描述随附在本目录里的产物，副本没随附的工具就不承诺它的用法。
- 聚合层不复制成员内容：同一事实只出现在一处，这里只留指针与跨成员约束。
