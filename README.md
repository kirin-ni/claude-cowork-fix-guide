# Claude Desktop Cowork 工作空间启动失败修复指南

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Claude Desktop 的 Cowork 功能一直提示"工作空间正在启动"然后卡住不动？这个仓库记录了完整的排查和修复过程。

---

## 问题现象

Claude Desktop（Windows Store 版）开 Cowork 工作空间时，显示：

> Workspace still starting. The isolated Linux environment is booting in the background (usually 10–30 seconds). Try again shortly.

等了多久都没用，工作空间永远启动不了。

## 根本原因

Claude Desktop 是 **MSIX 打包应用**（从 Windows Store 安装的），它的文件系统是重定向的：

| 你以为的文件路径 | MSIX 实际看到的路径 |
|---|---|
| `AppData\Local\Claude-3p\...` | `Packages\Claude_...\LocalCache\Roaming\Claude-3p\...` |

Cowork 的 VM 启动时，原生代码（Swift）在这条**重定向后的路径**找 rootfs.vhdx、vmlinuz 这些文件。如果文件不在那里，它就报"找不到文件"。

传统的目录交接点（`mklink /J`）在这里**无效**——MSIX 容器不跟随重解析点。

**解法：NTFS 硬链接（`mklink /H`）。** 文件系统层面的映射，MSIX 容器能直接识别。

---

## 快速修复（照着做就行）

### 准备工作

- 保持 Claude Desktop **开着**（不要关）
- 以**普通权限**打开 PowerShell 或 cmd 就行（不需要管理员）

### 修复步骤

**第一步：找到你的 Claude 包路径**

每个人的包 ID 可能不同，先执行这条命令找到它：

```powershell
powershell -Command "Get-ChildItem 'C:\Users\fanch\AppData\Local\Packages\' -Directory -Filter 'Claude*' | Select-Object Name"
```

记下显示的包名（类似 `Claude_pzs8sxrjxfjjc`）。

**第二步：删除失效的目录交接点（如果有的话）**

```powershell
fsutil reparsepoint delete "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p"
```

**第三步：创建硬链接**

把下面命令里的 `你的包名` 替换成第一步看到的：

```powershell
# rootfs.vhdx 是最大的文件（9.45GB），硬链接是瞬间完成的
mklink /H "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle\rootfs.vhdx" "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle\rootfs.vhdx"

mklink /H "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle\vmlinuz" "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle\vmlinuz"

mklink /H "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle\initrd" "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle\initrd"

mklink /H "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle\smol-bin.vhdx" "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle\smol-bin.vhdx"

mklink /H "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle\vmlinuz.zst" "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle\vmlinuz.zst"

mklink /H "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle\initrd.zst" "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle\initrd.zst"

mklink /H "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle\rootfs.vhdx.zst" "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle\rootfs.vhdx.zst"
```

**第四步：验证**

回到 Claude Desktop，点 Cowork 新建一个工作空间。应该就能正常启动了。

### 一键修复脚本

也可以用仓库里带参数的 PowerShell 脚本自动完成，用法：

```powershell
.\scripts\create-hardlinks.ps1 -SourcePath "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle" -DestPath "C:\Users\fanch\AppData\Local\Packages\你的包名\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle"
```

---

## 仓库内容

| 文件 | 说明 |
|------|------|
| [`skill.zh.md`](skill.zh.md) | 完整方法论（中文） |
| [`skill.en.md`](skill.en.md) | Full methodology (English) |
| [`cases/claude-cowork-vm.md`](cases/claude-cowork-vm.md) | 完整案例复盘（中英双语） |
| [`scripts/create-hardlinks.ps1`](scripts/create-hardlinks.ps1) | 一键硬链接脚本 |

包含的内容：
- **排查方法论**：约束矩阵、决策树、方案速查表
- **反死循环框架**：5 条规则，防止 debug 绕弯路
- **MSIX 虚拟化速查**：路径重定向规则、硬链接 vs junction 区别
- **调试工具箱**：查文件锁、查重解析点、卷影复制等命令

---

## 适用场景

如果你用的是 **Windows Store 版的 Claude Desktop**，Cowork 工作空间无法启动，那这个仓库大概率能帮你解决。

如果你用的是其他 MSIX 打包的应用也遇到类似问题，这里的方法论同样适用。

## License

MIT
