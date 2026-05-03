# MSIX 沙箱与文件系统调试方法论

MSIX 打包应用的文件系统虚拟化导致"找不到文件"、沙箱启动失败、路径解析异常时的系统调试方法。

---

## 目录

- [何时使用](#何时使用)
- [核心方法论](#核心方法论)
  - [第 0 步：建立约束矩阵](#第-0-步建立约束矩阵)
  - [第 1 步：日志先行](#第-1-步日志先行)
  - [第 2 步：路径分析](#第-2-步路径分析)
  - [第 3 步：通过约束排除选择方案](#第-3-步通过约束排除选择方案)
  - [第 4 步：NTFS 硬链接详解](#第-4-步ntfs-硬链接详解)
  - [第 5 步：增量验证](#第-5-步增量验证)
- [反死循环框架](#反死循环框架)
  - [规则 1：15 分钟红线](#规则-115-分钟红线)
  - [规则 2：约束排除法](#规则-2约束排除法)
  - [规则 3：两击重审](#规则-3两击重审)
  - [规则 4：不越界](#规则-4不越界)
  - [规则 5：错误变化 = 进展](#规则-5错误变化--进展)
- [案例复盘：Claude Desktop Cowork VM](#案例复盘claude-desktop-cowork-vm)
- [MSIX 虚拟化速查](#msix-虚拟化速查)
- [调试工具箱](#调试工具箱)
- [参考资料](#参考资料)

---

## 何时使用

当问题满足以下特征时触发：

- **MSIX/AppX 打包应用**（Windows Store 安装或侧载）
- 错误路径中包含 `Packages\...\LocalCache\Roaming\` 或 `Packages\...\LocalCache\Local\`
- 你能确认文件在磁盘上存在，但应用报"找不到文件"
- 沙箱/VM/容器在打包应用内启动失败
- 目录交接点（junction）或符号链接方案失效

---

## 核心方法论

### 第 0 步：建立约束矩阵

**在尝试任何方案之前**，先列出所有不可变更的约束条件。把它们写下来。

**模板：**

```
约束矩阵
─────────────────────────────────────
权限        : [管理员 | 普通用户 | AppContainer]
目标进程    : [可杀 | 不可杀]
文件状态    : [已锁定 | 未锁定 | 虚拟化]
环境        : [MSIX | AppX | 原生 | WSL | Docker]
网络        : [直连 | 代理 | 镜像 | 无网络]
目标写入    : [可写入 | 只读]
```

**实战案例（Claude Desktop Cowork VM）：**

| 约束 | 值 | 影响 |
|------|----|------|
| 权限 | 非管理员 | 不能用 `fsutil hardlink`、VSS、`mklink /D` |
| 目标进程 | 不可杀 | 杀掉 Claude 桌面端同时会杀死调试会话 |
| 文件状态 | rootfs.vhdx（9.45GB）被锁定 | 不能复制或移动 |
| 环境 | MSIX 打包（Windows Store） | 路径重定向到 `Packages\...` |
| 网络 | DeepSeek API 代理 | 不能从 Anthropic 重新下载 bundle |
| 写入权限 | 可写入 Packages 路径 | 硬链接可行 |

### 第 1 步：日志先行

MSIX 打包应用的日志通常位于：

- `%LOCALAPPDATA%\Claude-3p\logs\`（Claude Desktop）
- `%LOCALAPPDATA%\Packages\<包名>\LocalCache\`（MSIX 重定向）
- `%APPDATA%\...`（漫游数据）

**提取精确错误：**

```powershell
# 查找所有错误
Select-String -Path "cowork_vm_node.log" -Pattern "error" | Select -First 20

# 按时间段筛选
Select-String -Path "cowork_vm_node.log" -Pattern "2026-05-03 16:" | Select -First 30
```

**从每条错误中提取：**

1. ✅ 完整错误信息（不是摘要）
2. ✅ 错误中提到的**确切文件路径**
3. ✅ 调用栈（显示哪个组件出错了）
4. ✅ 错误发生前的步骤名称（例如 `Configuring Windows VM service...`）

### 第 2 步：路径分析

**MSIX 应用有两个文件系统视图：**

| 用户看到的路径 | MSIX 应用看到的路径 |
|---|---|
| `C:\Users\用户名\AppData\Local\Claude-3p\` | `C:\Users\用户名\AppData\Local\Packages\<包名>\LocalCache\Roaming\Claude-3p\` |

这个重定向对于应用的 JavaScript/Node.js 代码是透明的（它们仍然使用逻辑路径），但**原生代码**（C++、Swift、Rust）调用 Windows API（如 `CreateFile` 或 `SHGetKnownFolderPath`）时，获取的是**重定向后的路径**。

**关键判断：** 当错误路径中包含 `Packages\...\LocalCache\Roaming\` 时——这就是 MSIX 重定向路径。原生代码要访问该文件，文件**必须物理存在于该路径**（或通过硬链接映射到该路径）。

### 第 3 步：通过约束排除选择方案

**方案速查表：**

| 技术 | 命令 | 需管理员？ | MSIX 内有效？ | 零拷贝？ | 说明 |
|---|---|---|---|---|---|
| 目录交接点 | `mklink /J` | 否 | ❌ | ✅ | MSIX 容器不跟随重解析点 |
| 文件符号链接 | `mklink` | 是* | 不确定 | ✅ | 需管理员或开发者模式 |
| **NTFS 硬链接** | **`mklink /H`** | **否** | **✅** | **✅** | **MSIX 场景最优——文件系统级，非重解析点** |
| 文件复制 | `copy` / `Copy-Item` | 否 | ✅ | ❌ | 源文件被锁定时失败 |
| VSS 卷影复制 | `diskshadow` | 是 | ✅ | ❌ | 绕过锁定，但需管理员 |
| 修改配置 | 编辑 JSON/注册表 | 视情况 | ✅ | N/A | 如果应用暴露了配置选项 |

**\* = Windows 10/11 开发者模式允许非管理员创建符号链接**

**选择流程：**

```
文件在 MSIX 重定向路径找不到
  ├─ 能否写入 Packages 路径？
  │   ├─ 能，文件未锁定 → 直接复制文件
  │   ├─ 能，文件已锁定 → NTFS 硬链接 (mklink /H)
  │   └─ 不能写入 → 能否修改应用配置？
  │       ├─ 能 → 修改 bundle 路径配置
  │       └─ 不能 → 尝试 VSS 卷影复制（需管理员）
  │
  确认修复后 → 检查下一个错误
      ├─ 错误变化了 → 继续修复下一个文件
      ├─ 错误没变 → 重新评估假设
      └─ 没有错误 → 成功
```

### 第 4 步：NTFS 硬链接详解

**为什么硬链接在 MSIX 中有效而交接点无效：**

```
交接点 (mklink /J):
  Packages\Claude-3p ──[重解析点]──> AppData\Local\Claude-3p
  MSIX 容器: ⛔ 不能跟随重解析点

硬链接 (mklink /H):
  Packages\...\rootfs.vhdx ──[同一 MFT 条目]──> AppData\...\rootfs.vhdx
  MSIX 容器: ✅ 透明——不同的目录条目，同一份数据
```

**批量创建硬链接的脚本：**

```powershell
$src = "C:\Users\用户名\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle"
$dst = "C:\Users\用户名\AppData\Local\Packages\Claude_pkg\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle"

$files = @("vmlinuz", "initrd", "smol-bin.vhdx", "vmlinuz.zst", "initrd.zst", "rootfs.vhdx.zst", "rootfs.vhdx")
foreach ($f in $files) {
    $sf = Join-Path $src $f
    $df = Join-Path $dst $f
    if (Test-Path $sf) {
        cmd.exe /c "mklink /H `"$df`" `"$sf`""
        Write-Host "$f - OK"
    }
}
```

**⚠️ 重要：创建硬链接前必须先删除交接点，否则 `mklink /H` 会因为源和目标指向同一文件（通过交接点解析）而拒绝创建。**

```powershell
# 删除交接点（重解析点）
fsutil reparsepoint delete "C:\Users\用户名\AppData\Local\Packages\...\Claude-3p"

# 或者通过 cmd（如果 fsutil 失败）
cmd.exe /c "rmdir C:\Users\用户名\AppData\Local\Packages\...\Claude-3p"

# 创建硬链接
mklink /H <packages_path>\rootfs.vhdx <appdata_path>\rootfs.vhdx
```

### 第 5 步：增量验证

**黄金法则：修复一个错误 → 检查下一个错误 → 重复直到全部修复。**

```
初始状态:  "VHDX file not found: ...rootfs.vhdx"
  ↓ 修复 rootfs.vhdx 硬链接
下一个状态: "kernel not found: ...vmlinuz"           ← 进展！
  ↓ 修复 vmlinuz 硬链接
下一个状态: "initrd not found: ...initrd"            ← 进展！
  ↓ 修复 initrd 硬链接
最终状态:  SUCCESS                                   ← 完成
```

**每个新错误都是进展，不是失败。** 如果修复后错误不变，说明修复没生效——重新评估。

---

## 反死循环框架

### 规则 1：15 分钟红线

**任何一个方向，15 分钟没有新信息或错误进展，立即放弃换方案。**

死循环信号：
- 用微小变化反复测试同一假设
- "让我再验证一次..."
- 结果和最近 3 次尝试完全一样
- 在研究"本应能用的东西为什么不行"

*在 Cowork 案例中，junction 被反复测试了 4-5 次，结果完全一样。*

### 规则 2：约束排除法

> **不要问"什么方案能用"——而是问"什么方案不能被排除"。**

1. 列出所有可能的方案
2. 用约束条件逐条排除
3. 唯一没被排除的方案就是答案，即使它看起来不直观

*硬链接在 Cowork 案例中是不直观的答案——没人会想到"文件系统元数据技巧"能解决 VM 沙箱问题。*

### 规则 3：两击重审

**如果连续两个方案都走不通，你的问题模型是错的。**

不要尝试第三个方案。而是：
1. 重新阅读原始错误信息
2. 从头检查日志
3. 质疑你的假设："如果 X 实际上是 Y 会怎样？"
4. 寻找你之前忽略的环境因素

*Junction 失败 → 复制失败（文件锁定）。正确的反应不是"更努力地尝试 junction"——而是"我处理路径解析的方法从根本上错了"。*

### 规则 4：不越界

**如果错误是关于文件路径的，不要去碰网络。如果是关于 MSIX 的，不要去碰 WSL。**

花在错误领域之外的每一分钟都是浪费。采取任何行动之前，问自己："这直接解决了日志中的错误吗？"

### 规则 5：错误变化 = 进展

```
❌ "还是不行，错误变了..."
✅ "错误变了！我们在前进！"
```

一个新错误意味着：
- 上一个修复生效了
- 你揭开了下一个被阻塞的步骤
- 你离解决方案更近了

---

## 案例复盘：Claude Desktop Cowork VM

> 完整双语案例见 [`cases/claude-cowork-vm.md`](cases/claude-cowork-vm.md)

**原始错误：**

```
[VM:start] Startup failed: Error: failed to set VHDX path: VHDX file not found:
C:\Users\fanch\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\
Claude-3p\vm_bundles\claudevm.bundle\rootfs.vhdx
```

**关键发现：**
1. `bundlePath` 日志显示 `AppData\Local\Claude-3p\...`（非重定向路径）
2. 错误路径包含 `Packages\...\LocalCache\Roaming\`（MSIX 重定向路径）
3. Node.js 代码使用非重定向路径（正常工作）
4. 原生 VM Swift 代码通过 MSIX 重定向解析路径（失败）

**根因：**
VM 服务（通过 `load_swift_api` 加载的原生 Swift 代码）调用返回 MSIX 重定向路径的 Windows API，然后尝试 `CreateFile` 访问重定向路径。该路径上的目录交接点不能被 MSIX AppContainer 进程跟随。

**修复：**
```powershell
# 步骤 1：删除交接点
fsutil reparsepoint delete "C:\Users\fanch\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude-3p"

# 步骤 2：为所有 7 个 bundle 文件创建硬链接
mklink /H <packages_path>\rootfs.vhdx      <appdata_path>\rootfs.vhdx
mklink /H <packages_path>\vmlinuz           <appdata_path>\vmlinuz
mklink /H <packages_path>\initrd            <appdata_path>\initrd
mklink /H <packages_path>\smol-bin.vhdx     <appdata_path>\smol-bin.vhdx
mklink /H <packages_path>\vmlinuz.zst       <appdata_path>\vmlinuz.zst
mklink /H <packages_path>\initrd.zst        <appdata_path>\initrd.zst
mklink /H <packages_path>\rootfs.vhdx.zst   <appdata_path>\rootfs.vhdx.zst
```

**验证过程：**
- 错误 #1：`rootfs.vhdx not found` → 修复 → 错误变为 ↓
- 错误 #2：`vmlinuz not found` → 修复 → 无更多错误 → ✅ VM 启动成功

---

## MSIX 虚拟化速查

| 概念 | 详情 |
|---|---|
| 什么是 MSIX？ | Windows 应用打包格式。应用在轻量容器中运行，注册表和文件系统被虚拟化。 |
| 文件系统重定向 | `%APPDATA%` → `Packages\{身份}\LocalCache\Roaming\` |
| | `%LOCALAPPDATA%` → `Packages\{身份}\LocalCache\Local\` |
| | `%PROGRAMFILES%\WindowsApps\{身份}\`（应用安装目录） |
| 注册表重定向 | `HKCU\Software\{身份}` → 隔离的注册表配置单元 |
| 进程类型 | "完全信任" MSIX 应用以用户身份运行，但经过过滤器驱动 |
| **Junction 限制** | **MSIX 过滤器驱动不跟随重解析点/junction** |
| 硬链接兼容性 | NTFS 硬链接透明工作（文件系统级，非过滤器级） |
| Known Folders API | `SHGetKnownFolderPath` 在 MSIX 内返回重定向路径 |

---

## 调试工具箱

```powershell
# 检查路径是否为重解析点（junction/符号链接）
(Get-Item "C:\path").Attributes -match "ReparsePoint"

# 查看 junction 目标
(Get-Item "C:\path").Target

# 删除重解析点
fsutil reparsepoint delete "C:\path"

# 检查文件锁定
try { $f = [System.IO.File]::Open("C:\path", 'Open', 'Read', 'None'); $f.Close(); "未锁定" }
catch { "已锁定: $_" }

# 创建硬链接
cmd.exe /c "mklink /H target.lnk source.dat"

# 检查链接数（硬链接文件应为 2+）
(Get-Item "C:\path\file.dat").LinkType  # "HardLink" 表示已硬链接

# Volume Shadow Copy（需管理员权限）
# 用于不停止进程复制锁定文件
diskshadow.exe
> set context persistent
> begin backup
> add volume C: alias shadow
> create
> expose %shadow% X:
> end backup
> exit
# 然后从 X:\Users\用户名\...\锁定文件 复制
```

---

## 参考资料

- [MSIX 官方文档](https://learn.microsoft.com/zh-cn/windows/msix/)
- [MSIX AppContainer 能力](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations)
- [NTFS 硬链接](https://learn.microsoft.com/zh-cn/windows/win32/fileio/hard-links-and-junctions)
- [Windows 应用包路径](https://learn.microsoft.com/zh-cn/windows/msix/desktop/desktop-to-uwp-behind-the-scenes)
