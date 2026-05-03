# MSIX Sandbox & File System Debugging Methodology

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> A systematic methodology for debugging **MSIX-packaged applications** where file system virtualization causes "file not found" errors, sandbox startup failures, or path resolution issues.
>
> 一套用于调试 **MSIX 打包应用**文件系统虚拟化问题的系统方法论，解决因路径重定向导致的"文件找不到"、沙箱启动失败等问题。

---

## The Problem 问题

MSIX-packaged apps (Windows Store, sideloaded) have a **redirected filesystem** — `%APPDATA%` and `%LOCALAPPDATA%` are transparently mapped to `Packages\{identity}\LocalCache\`. Native code within the app (C++, Rust, Swift) sees the **redirected path**, not the logical path. This causes baffling "file not found" errors even when the file clearly exists.

MSIX 打包应用的文件系统是**重定向的**——`%APPDATA%` 和 `%LOCALAPPDATA%` 被透明映射到 `Packages\{identity}\LocalCache\`。应用内的原生代码（C++/Rust/Swift）看到的是**重定向后的路径**，而非逻辑路径。这导致文件明明存在，应用却报"找不到文件"。

Traditional fixes like directory junctions (`mklink /J`) **don't work** inside MSIX containers because the MSIX filter driver does not traverse reparse points. The correct answer is often **NTFS hardlinks** (`mklink /H`).

传统的目录交接点（junction）修复**在 MSIX 容器内无效**，因为 MSIX 过滤器驱动不跟随重解析点。正确的答案往往是 **NTFS 硬链接**。

---

## Contents 内容

| File | Description |
|------|-------------|
| [`skill.en.md`](skill.en.md) | Full methodology (English) |
| [`skill.zh.md`](skill.zh.md) | 完整方法论（中文） |
| [`cases/claude-cowork-vm.md`](cases/claude-cowork-vm.md) | Real case: Claude Desktop Cowork VM (双语) |
| [`scripts/create-hardlinks.ps1`](scripts/create-hardlinks.ps1) | Utility: batch hardlink creation |

## Quick Start 快速开始

```powershell
# 1. Identify the error from logs 从日志定位错误
Select-String -Path "cowork_vm_node.log" -Pattern "error" | Select -First 10

# 2. Check if it's an MSIX redirect path 检查是否为 MSIX 重定向路径
#    (contains "Packages\...\LocalCache\")

# 3. Verify constraint matrix 验证约束矩阵
#    - Admin? 管理员权限？
#    - Can kill process? 可杀进程？
#    - File locked? 文件锁定？

# 4. Apply fix: hardlinks instead of junction 应用修复：硬链接替代交接点
fsutil reparsepoint delete "C:\Users\...\Packages\...\Claude-3p"
mklink /H <packages_path>\file.vhdx <appdata_path>\file.vhdx
```

## Core Principle 核心原则

> **Don't ask "What could work?" — Ask "What can't be eliminated?"**
>
> **不要问"什么方案能用"——而是问"什么方案不能被排除"。**

List all candidate solutions. Eliminate those that violate your constraints. The only remaining solution is the answer — even if it seems unintuitive.

列出所有候选方案，用约束逐条排除。唯一留下的就是答案——即使它看起来不直观。

## License

MIT
