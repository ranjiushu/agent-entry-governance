# repo-resume

**Your repo's resume, kept hireable for humans and agents.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Python 3.8+](https://img.shields.io/badge/python-3.8%2B-blue.svg)](#运行环境)
[![Dependencies: none](https://img.shields.io/badge/dependencies-none-brightgreen.svg)](#运行环境)

repo-resume 是一个 Agent 技能：把 `AGENTS.md`、`CLAUDE.md` 这类入口文档写成仓库的简历。接手的人读它，agent 每次会话开头也整份读它，而且读得比人勤。项目长大以后简历膨胀成百科，每次开工得先重读一遍。

**把它当简历来写：常驻的那份短到能一口气读完，超载就拦。** 判据落在两处：

- 常驻上下文保持短，超出预算的知识下沉成指针。
- 简历要给人读：排成 A4 通读一遍，再交付。
- 超限在提交点拦下，fail-closed，不留侥幸。
- 兼容 `AGENTS.md` / `CLAUDE.md` / `SKILL.md`，自定义命名用 `--names` 注入。

## 判决看页面

人感觉不到 token 和字节，感觉到的是页数。所以本技能的主线是打印：把入口文档排成 PDF，拿它当终审的依据。

### 为什么多这一步

Markdown 本来就能读，再排一遍看着多余。理由是页面比源码诚实：编辑器里一行超长的表格只是一坨，排到页面上才看得出它散架。多排这一遍，买的是「通读」这个动作：人读得进去，才会读、才会改、才会把自己的判断放进来；没人维护的入口文档会烂掉，Agent 开工拿到的上下文跟着一起错。代价是每次提交多跑一遍渲染（Typst 首次还要拉一次编译器），换不来内容，也管不了机器侧的预算（那是守卫的事）。理由写全在 [entry-card-craft/references/philosophy.md](entry-card-craft/references/philosophy.md)。

```bash
bash entry-card-craft/scripts/print-entry-doc-typst.sh SKILL.md entry-*/SKILL.md
```

```
📄 SKILL-20260918-125105.pdf（工作区版）实排 2 页｜算术 1.5 页｜排版开销 +0.5 页
📄 entry-card-craft-SKILL-20260918-125107.pdf（工作区版）实排 2 页｜算术 1.6 页｜排版开销 +0.4 页
📄 entry-deai-style-SKILL-20260918-125109.pdf（工作区版）实排 1 页｜算术 0.6 页｜排版开销 +0.4 页
📄 entry-doc-governance-SKILL-20260918-125110.pdf（工作区版·末页合并）实排 2 页｜算术 1.9 页｜排版开销 +0.1 页
```

这行结果里有两样东西。实排页数是给人看的刻度；算术页数的差是**排版开销**，表格、短行、项目符号的留白都记在它头上。末页只剩一点点时脚本会自动紧排一次，真少一页才采用，产出标「末页合并」。简历不给人留一行空白页。

正文用衬线体（Georgia 加思源宋体，标题黑体），对标 Typora 的输出质量。产出默认落在仓库的 `.git/` 下，用 `--out`、`--archive` 指定集中位置。

要看页面本身而不只是页数时用查看模式：`view-entry-doc.sh` 把已选定的那一档逐页导出成图片，并写一份 `INDEX.md` 用相对路径引用每页（图片落在 PDF 旁边、同名滚动覆盖、不进版本控制）。仅 Typst 后端支持。

要把它递到人眼前——手机、浏览器、对话里的 markdown——还得挂个服务：本地路径多数渲染器加载不出来（手机聊天 App 尤其），http 才行。`serve-entry-doc.sh` 把产出目录挂成静态服务，并打印可直接粘进 markdown 的引用；它是长驻进程，在持久终端里前台跑，别挂进钩子。

打印不阻断流程：要跑一次渲染，Typst 首次还要拉一次编译器（版本钉死、核对 sha256 后进用户缓存），所以挂 post-commit，永不返回非零。这不是说它次要：**守卫管有没有失控，页面管读不读得下去。**缺编译器时脚本会明说这次没排成，终审据此标注「未经页面终审」，不装作看过。无头浏览器版仍在，`--backend chrome` 可回退。

## 快速开始

量一次，只读不阻断；阈值不抄进文档，问度量器要权威值：

```bash
python3 entry-doc-governance/scripts/measure.py AGENTS.md
python3 entry-doc-governance/scripts/measure.py --print-policy
```

装到提交点（`--check` 校验安装状态）：

```bash
bash entry-doc-governance/scripts/install-hook.sh --repo /path/to/repo      # 守卫，超限 fail-closed
bash entry-doc-governance/scripts/install-hook.sh --repo /path/to/repo --check
bash entry-card-craft/scripts/install-print-hook.sh --repo /path/to/repo    # 打印层
```

作为技能加载则不用记命令：把整个 `repo-resume/` 目录放进 skills 目录，框架读各份 `SKILL.md` 的 frontmatter 决定何时加载。参数细节看各脚本的 `--help` 和文件头。

## 越线会看到什么

守卫和度量器读同一份策略，下面是真实输出。

超上限的直接拒绝提交，合规的只报个数：

```
[guard] ❌ AGENTS.md 工作区版 已达约 5869 token（上限 3000），拒绝提交
[guard]    请先精简：指针化下沉 docs/，或归档历史内容（精简动作：指针化下沉 / 归档历史 / 职责切割 / 拆分）
[guard] ✅ SKILL.md 工作区版约 780 token（距提醒线 1720）
```

退出码有三档，调用方按 fail-closed 处理：

| 码 | 含义 | 动作 |
|---|---|---|
| 0 | 全部在阈值内 | 放行 |
| 1 | 超上限、用法错误，或校验无法完成 | 拒绝 |
| 2 | 只在提醒线以上 / gzip 冗余 | 放行，并打印告警 |

`--staged` 量的是即将提交的那份：没进本次提交就显式跳过，与 HEAD 逐字节相同（本次没改它）也跳过，免得一个存量超限的文件把仓库里无关的提交全锁死。

## 三条边界

安全与不可逆约束（敏感资产、关键路径、fail-closed 关口）照原样写死，不因为追求好看就软化。事实、路径、命令、判断照准写，不为顺口变模糊。文档不能长到挤爆代理的默认上下文，超了把细节搬走，不删真相。

## 三个成员

| 成员 | 管什么 |
|---|---|
| `entry-card-craft` | 简历本身：结构与排版、页面终审（含打印层）、简历与 README 的分工 |
| `entry-doc-governance` | 度量与阈值、安全下沉（指针可达、无第二事实源）、把守卫装成必被执行的关口 |
| `entry-deai-style` | 文风：去 AI 味，完整标准在上游 `humanizer-zh` |

聚合层的 `SKILL.md` 只放索引、分工与跨成员约束，不复制成员内容。

## 目录

```
SKILL.md                            聚合索引：三条边界、分工秩序、关键词路由
entry-card-craft/                   简历本身：判决、排版、打印、页面终审
├── SKILL.md
├── references/philosophy.md        设计理据：核心假设与判据的理由，按需加载
├── references/final-audit.md       终审清单（叙事 / 排版 / 文风 / 调性），终审时才读
└── scripts/                        打印层：print-entry-doc-typst.sh + md2typst.py（默认 Typst 后端）
                                    print-entry-doc.sh（无头浏览器回退）+ install-print-hook.sh
                                    view-entry-doc.sh（查看模式：逐页图片 + INDEX.md）
                                    serve-entry-doc.sh（把产出目录挂成静态服务，给手机/浏览器看）
entry-doc-governance/               文档治理：度量、阈值、安全下沉、提交点守卫
├── SKILL.md
├── references/final-audit.md       终审清单（关口 / 事实源 / 度量 / 搬迁），终审时才读
└── scripts/{measure.py, guard.py, install-hook.sh}        度量器 / 判据 / 安装器
entry-deai-style/SKILL.md           去 AI 味（上游 humanizer-zh，内置降级四条）
```

技能按三层渐进披露：frontmatter 决定框架何时加载，正文是策略与工作流，`references/` 按需加载。

## 工作流

1. 改入口文档前后各量一次，越线先精简再提交。
2. 排一次，通读实排页面：几页、末页空不空、表格散没散、标题层级跳不跳。
3. 判定去留。每次任务都要读到、又无法从代码派生的，留在入口；只有部分任务需要的，下沉成指针；能从代码或工具直接派生的，删掉；历史背景和失效内容，归档。
4. 下沉前先审接收方：目标存在、自身可用，且还没持有这条事实。
5. 迁移后报账：搬走了什么、搬到哪、入口现在怎么找到它。
6. 交付前过终审清单，两个成员各有一份。

## 我们自己也这么用

本仓四份入口文档的实测值（2026-09-17）：

| 文档 | token | 实排 | 状态 |
|---|---|---|---|
| `SKILL.md` | 1953 | 2 页 | 距提醒线 547 |
| `entry-deai-style/SKILL.md` | 780 | 1 页 | 距提醒线 1720 |
| `entry-card-craft/SKILL.md` | 2192 | 2 页 | 距提醒线 308 |
| `entry-doc-governance/SKILL.md` | 2591 | 3 页 | 提醒线以上，距上限 409 |

页数和 token 是两个尺度：**一页纸是给人的判据，token 预算是给机器的约束**，不必同时满足——下表里就有一份 3 页、且停在提醒线以上的。

这份 README 不在受管清单里（被取用、不被注入），但它一样排过：实排 3 页，末页 91%。

`entry-doc-governance` 停在提醒线以上、上限以内是有意留的：成员 `SKILL.md` 属于取用层，框架需要时才加载，每次注入的只有聚合层 frontmatter 那一段。判决看加载时机，不看孤立数字。

## 适用范围

只管代理入口文档，以及安全下沉入口知识所需的文档关系，不管整个仓库的通用文档生命周期。打印层服务的也是入口文档，不是通用 Markdown 排版工具。

## 运行环境

- 度量器与判据（`entry-doc-governance`）：Python 3.8+ 标准库，不联网、不写文件、不依赖版本控制（版本控制只用于取将生效的版本）。
- 打印层（`entry-card-craft`）：bash + Python 3.8+ 标准库，另需 Typst（版本由脚本钉死、首次运行自动拉取到用户缓存并核对 sha256）；不阻断流程。无头浏览器版保留作回退（`--backend chrome`）。
- 安装器：往 git 仓库的钩子位装东西，需要 git。
- 去味（`entry-deai-style`）：依赖上游技能 `humanizer-zh`，缺席时用内置降级四条并显式声明。
- 入口文档的命名和层数由所在环境声明。脚本默认发现 `AGENTS.md` / `AGENT.md`，其他命名用 `--names` 注入，不改源码。

前提缺失时必须显式响应，不得静默降级。

## 可移植性

可移植单元是整个目录。支持 Skills 的框架直接放进 skills 目录读 `SKILL.md`；不支持的把 `SKILL.md` 正文塞进系统提示词，脚本照常能单独跑。守卫能装提交点就装；只有流水线或启动入口，就在其中 fail-closed 调用 `guard.py`；一个关口都没有，就退化为入口处的显式提示，不假装已经装上了。

## 参与与许可

issue 和 PR 都欢迎，中英文都行。改 `SKILL.md` 或脚本之后，提交前照「快速开始」里的两条命令各跑一次；守卫会在提交点再拦一道。MIT 许可，见 [LICENSE](LICENSE)。
