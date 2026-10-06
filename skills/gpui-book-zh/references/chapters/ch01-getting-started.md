# Chapter 1: Getting Started（快速上手）

> 来源：The GPUI Book — getting-started 三节。对应原文：`src/getting-started/`。

## Core Idea

GPUI 通过 crates.io 或 git 依赖引入（crate 本体托管在 Zed 仓库内，随 Zed 的需求持续演进）；官方 CLI `create-gpui-app` 可一键生成可运行的应用骨架。

## Key Concepts

- **两种依赖方式**（Cargo.toml）：
  - crates.io：定期发布版本，`gpui = { version = "*" }`（实际项目应锁定具体版本）
  - git：`gpui = { git = "https://github.com/zed-industries/zed" }`，跟随主线，API 可能随 Zed 演进变化
- **create-gpui-app**（官方 CLI）：
  - 安装：`cargo install create-gpui-app`
  - 单包结构：`create-gpui-app --name my-app`（src/main.rs + Cargo.toml）
  - workspace 结构：`create-gpui-app --workspace --name my-app`（crates/my-app/...）
- **手动建项**：
  - `cargo new my-app && cd my-app`
  - `cargo add gpui` 或 `cargo add gpui --git https://github.com/zed-industries/zed`

## Code Examples

```toml
[dependencies]
gpui = { version = "*" } # 应指定具体版本
# OR
gpui = { git = "https://github.com/zed-industries/zed" }
```

- **What it demonstrates**：引入 GPUI 的两条路径；书提醒 git 依赖拿到的 API 与 crates.io 版本可能不同。

## Key Takeaways

1. 新项目首选 `create-gpui-app`；已有既定工程结构时手动 `cargo add gpui`。
2. git 依赖可拿到最新 API，但 GPUI 处于活跃演进期，锁定版本更稳。
3. 可运行的最小 Hello World 见 ch14（main 骨架全应用通用）。

## Connects To

- **ch02**: 建好项目后，理解 Application → App → Window → Context 的架构。
- **ch14**: 完整可运行的最小范例代码。
