# agent-entry-governance

让 AI 代理的入口文档写不烂：不无限膨胀、不腐烂成过时副本、不出现第二处事实源。

第一原则：入口文档不是知识库，是 agent 的上下文入口；默认上下文是稀缺资源。

## 它解决什么问题

AGENTS.md / CLAUDE.md 这类文件是代理每次开工时的默认上下文入口。项目长大后，它很容易长成一部百科全书，代理每次都要先读一遍。本技能把「入口知识」与「项目知识」分开，并给出一条可执行的治理链路：

    测量 → 判定去留 → 下沉 → 报账 → 终审

出口是装在提交点上的守卫：内容超限时拦下提交，而不是等上下文被撑爆之后才发现。

## 组成

    SKILL.md                              聚合索引：关键词路由与成员分工
    entry-context-budget/
    ├── SKILL.md                          策略：要什么（正面标准，不写环境专名）
    ├── references/final-audit.md         交付前终审清单，只在终审阶段加载
    └── scripts/
        ├── measure.py                    度量器：只读，报告 token 与 gzip 密度
        ├── guard.py                      判据：退出码 0 / 1 / 2，供关口 fail-closed 调用
        └── install-hook.sh               安装器：幂等把守卫装进 git 仓库的提交点

阈值与 token 近似算法的唯一事实源是度量器，随时可查：

    python3 entry-context-budget/scripts/measure.py --print-policy

## 怎么用

量一次当前入口文档：

    python3 entry-context-budget/scripts/measure.py AGENTS.md

装到提交点（幂等，可反复执行；守卫本体随仓库入库，clone 后不会失效）：

    bash entry-context-budget/scripts/install-hook.sh --repo /path/to/repo

校验安装状态：

    bash entry-context-budget/scripts/install-hook.sh --repo /path/to/repo --check

精确用法以各脚本的 --help / 文件头为准，本文件不复述参数。

## 工作流

1. 改入口文档前后各量一次，越线先精简再提交。
2. 判定去留：留在入口的（几乎所有任务都需要、无法从代码派生）、下沉成指针的（部分任务才需要）、删掉静态副本的（能从代码或工具直接派生）、删除或归档的（历史背景、已失效）。
3. 下沉前先审接收方：目标存在、自身可用、且尚未持有该事实。
4. 迁移后报账：搬走什么、搬去哪、入口现在如何找到它。
5. 交付前对照终审清单逐条自检。

## 边界

本技能只管代理入口文档，以及为安全下沉入口知识所必需的文档关系；不管整个仓库的通用文档生命周期管理。

## 运行环境

- 度量器与判据：Python 3.8+ 标准库，不联网、不写文件、不依赖版本控制（版本控制只用于取将生效的版本）。
- 安装器：把守卫装进 git 仓库的提交点，因此需要 git。
- 入口文档的命名与层数由所在环境声明。脚本默认发现 AGENTS.md / AGENT.md，别的命名用 `--names` 注入，不改源码。

## 可移植性

可移植单元是整个目录。支持 skills 的框架直接放进 skills 目录读 `SKILL.md`；不支持时把 `SKILL.md` 正文放进系统提示词、脚本直接运行；有版本控制就把守卫装到提交点，只有流水线或启动入口则在其中 fail-closed 调用判据；一个关口都没有时，退化为入口处显式提示，不假装已装。
