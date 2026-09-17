# agent-entry-governance

一个 Agent 技能（Skill）：控制 AGENTS.md / CLAUDE.md 这类 Agent 入口文档的长度和信息密度——设定上下文预算，超出的知识下沉成指针，并在提交点装守卫拦截超限内容。

把整个目录放进 Agent 框架的 skills 目录即可生效；框架读 `SKILL.md` 的 frontmatter 判断何时调用它。

入口文档不是知识库，是代理的上下文入口，而默认上下文是稀缺资源。

## 它解决什么问题

AGENTS.md / CLAUDE.md 这类文件是代理每次开工时必读的内容。项目长大后，它容易长成一部百科全书，代理每次都要先读一遍。本技能把「入口知识」和「项目知识」分开，治理链路是：

    测量 → 判定去留 → 下沉 → 报账 → 终审

链路末端是装在提交点上的守卫：内容超限就拦下提交，不等到上下文被撑爆才发现。

长度不是目标。入口文档要能让第一次翻开它的 Agent 说清「这是什么地方、为什么有这些规矩、细节去哪找」；精简砍的是重复、背景和可派生的事实，不是因果。一张每行都写着「→ 见某文件」的卡，读者得先跳出去才知道为什么要跳。

再往前一步，判准的立足点是**人**：入口文档没有客观最优解，所以取「好看、易看、愿意看」当标准（详见 `entry-context-budget/SKILL.md` §〇）。人读得进去才愿意改、愿意用，协作里人的判断是主要变量；体积阈值只管有没有失控。

## 组成

    SKILL.md                              聚合索引：关键词路由与成员分工
    entry-context-budget/
    ├── SKILL.md                          策略：要什么（正面标准，不写环境专名）
    ├── references/final-audit.md         交付前终审清单，只在终审阶段加载
    └── scripts/
        ├── measure.py                    度量器：只读，报告 token 与 gzip 密度
        ├── guard.py                      判据：退出码 0 / 1 / 2，供关口 fail-closed 调用
        ├── install-hook.sh               安装器：幂等把守卫装进 git 仓库的提交点
        ├── print-entry-doc.sh            可选层：把入口文档排成 A4 PDF，报页数与排版开销
        └── install-print-hook.sh         可选层安装器：幂等把打印挂到 post-commit（永不阻断提交）

技能靠三层渐进披露：`SKILL.md` 的 frontmatter 决定框架何时加载它，正文是策略与工作流，`references/` 只在交付前终审时读。

阈值和 token 近似算法的唯一事实源是度量器，随时可查：

    python3 entry-context-budget/scripts/measure.py --print-policy

## 怎么用

作为技能加载时，人不用记任何命令：框架按 `SKILL.md` 的判断在需要时加载它，Agent 自己会去量、去精简、去装守卫。想手动操作，命令如下。

量一次当前入口文档：

    python3 entry-context-budget/scripts/measure.py AGENTS.md

装到提交点（幂等，可反复执行；守卫本体随仓库入库，clone 后仍有效）：

    bash entry-context-budget/scripts/install-hook.sh --repo /path/to/repo

校验安装状态：

    bash entry-context-budget/scripts/install-hook.sh --repo /path/to/repo --check

参数细节看各脚本的 --help 和文件头，本文件不复述。

## 工作流

1. 改入口文档前后各量一次，越线先精简再提交。
2. 判定去留：留在入口的（几乎所有任务都需要、无法从代码派生）、下沉成指针的（只有部分任务需要）、删掉的（能从代码或工具直接派生）、删除或归档的（历史背景、已失效）。
3. 下沉前先审接收方：目标存在、自身可用、且尚未持有该事实。
4. 迁移后报账：搬走什么、搬去哪、入口现在如何找到它。
5. 交付前对照终审清单逐条自检。

## 边界

只管代理入口文档，以及安全下沉入口知识所需的文档关系；不管整个仓库的通用文档生命周期。

## 运行环境

- 度量器与判据：Python 3.8+ 标准库，不联网、不写文件、不依赖版本控制（版本控制仅用于取将生效的版本）。
- 安装器：往 git 仓库的提交点装守卫，需要 git。
- 入口文档的命名和层数由所在环境声明。脚本默认发现 AGENTS.md / AGENT.md，其他命名用 `--names` 注入，不改源码。

## 可移植性

可移植单元是整个目录。支持 skills 的框架直接放进 skills 目录读 `SKILL.md`；不支持的框架把 `SKILL.md` 正文放进系统提示词，脚本照常直接运行。有版本控制就把守卫装到提交点；只有流水线或启动入口，就在其中 fail-closed 调用判据；一个关口都没有，就退化为入口处的显式提示，不假装已装。

## 许可

MIT，见 [LICENSE](LICENSE)。
