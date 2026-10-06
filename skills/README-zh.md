# 技能库

agpui 项目的 Agent Skill 集中发布目录。

- **命名约定**：无后缀目录 = 英文版；`-zh` 后缀 = 中文版。同一技能的两个版本同构（布局一致、章节编号一致）。
- **自包含**：每个技能目录独立可用——拷入运行时的 skills 目录即可使用。

## 索引

| 技能 | 说明 |
|---|---|
| [gpui-lesson](gpui-lesson/SKILL.md) | AK97 项目（Rust + GPUI + Win32 IPC）排障纪律 |
| [gpui-lesson-zh](gpui-lesson-zh/SKILL.md) | gpui-lesson 中文版 |
| [gpui-book](gpui-book/SKILL.md) | The GPUI Book（Matin Aniss 著）知识库 |
| [gpui-book-zh](gpui-book-zh/SKILL.md) | gpui-book 中文版 |

## gpui-lesson

从五份实战复盘（设置窗卡死、服务 PipeServer 自死锁、热键链、空闲 CPU 烧核、激活管道 231/路由静默 no-op）提炼的排障纪律：症状→病类分流矩阵、真机取证方法，以及 GPUI / Win32 / 生命周期 / C#→Rust 翻译接线面红线。不做泛化诊断，只提供本项目实证过的路径与工具锚。

- `references/` — 五份复盘 + 三张取证工单
- `scripts/` — 六个诊断工具的跨平台对：PowerShell（Windows）/ bash（Linux）；Windows 侧经真机实证，Linux 侧为同型对应实现（已显式标注）
- 出处：AK97 项目；超大留档（RUN-NOTES 等）为外部指针，未随发布

## gpui-book

**The GPUI Book**（Matin Aniss 著，mdBook，39 小节 + 52 代码片段）知识库：构建 GPUI 应用所需的概念——启动链（Application / App / Window / Context）、Entity 与 Global 状态管理、Div / Text / Img / Deferred 元素、Taffy 样式与布局、动画、鼠标与键盘动作/焦点、Render 与 RenderOnce 混合渲染、前台/后台异步执行器，含可复制的最小范例代码。覆盖 GPUI 框架本身；组件库用法与设计规范见 gpui-kit、gpui-kit-design-guides 技能。

- `references/chapters/` — 14 章摘要（ch01–ch14）
- `references/glossary.md` / `patterns.md` / `cheatsheet.md` — 46 个词条、9 个技法模式、决策表 + 症状→根因速查
- 已于 2026-10-06 对照源书逐节核验：错误已修正，书外引申标注「延伸」；书尚未撰写的部分（Svg / Anchored / List / Uniform List / Canvas、Implementing Element、Testing）如实标注
- 源书：[github.com/MatinAniss/gpui-book](https://github.com/MatinAniss/gpui-book)（已克隆至 `ref-projs/gpui-book`）
