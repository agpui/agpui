# Chapter 1: Getting Started (Quick Start)

> Source: The GPUI Book — the three getting-started sections. Corresponding original text: `src/getting-started/`.

## Core Idea

GPUI is brought in as a crates.io or git dependency (the crate itself is hosted in the Zed repository and evolves continuously with Zed's needs); the official CLI `create-gpui-app` generates a runnable application skeleton in one command.

## Key Concepts

- **Two dependency approaches** (Cargo.toml):
  - crates.io: periodically published versions, `gpui = { version = "*" }` (real projects should pin a specific version)
  - git: `gpui = { git = "https://github.com/zed-industries/zed" }`, tracks mainline; the API may change as Zed evolves
- **create-gpui-app** (official CLI):
  - Install: `cargo install create-gpui-app`
  - Single-package layout: `create-gpui-app --name my-app` (src/main.rs + Cargo.toml)
  - Workspace layout: `create-gpui-app --workspace --name my-app` (crates/my-app/...)
- **Manual project setup**:
  - `cargo new my-app && cd my-app`
  - `cargo add gpui` or `cargo add gpui --git https://github.com/zed-industries/zed`

## Code Examples

```toml
[dependencies]
gpui = { version = "*" } # pin a specific version
# OR
gpui = { git = "https://github.com/zed-industries/zed" }
```

- **What it demonstrates**: the two paths for bringing in GPUI; the book warns that the API from a git dependency may differ from the crates.io version.

## Key Takeaways

1. For new projects prefer `create-gpui-app`; with an established project structure, manually `cargo add gpui`.
2. A git dependency gets the latest API, but GPUI is under active evolution; pinning a version is more stable.
3. For a runnable minimal Hello World see ch14 (the main skeleton is universal across applications).

## Connects To

- **ch02**: after creating the project, understand the Application → App → Window → Context architecture.
- **ch14**: complete runnable minimal example code.
