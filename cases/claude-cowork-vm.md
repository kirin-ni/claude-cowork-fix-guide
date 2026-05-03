# Claude Desktop Cowork 工作空间修复：完整案例 / Case Study

> 从"工作空间正在启动"到正常运行的完整调试记录。

[ZH] Claude Desktop Cowork 工作的 MSIX 文件系统虚拟化调试——从症状到根因到修复的完整记录。
[EN] Debugging MSIX file system virtualization in Claude Desktop's Cowork feature — a full walkthrough from symptom to root cause to fix.

---

## Symptom 症状

[EN] Cowork shows: "Workspace still starting. The isolated Linux environment is booting in the background (usually 10–30 seconds). Try again shortly." — and never succeeds.

[ZH] Cowork 提示："工作空间正在启动。隔离的 Linux 环境正在后台启动……"——永远卡在这里。

## Environment 环境

| Factor 因素 | Value 值 |
|---|---|
| App 应用 | Claude Desktop v1.5354.0.0 (MSIX Store package) |
| OS 系统 | Windows 11 Home 23H2 (22631.3593) |
| Package ID 包标识 | `Claude_pzs8sxrjxfjjc` |
| VM Bundle 组件 | rootfs.vhdx (9.45GB), vmlinuz, initrd, smol-bin.vhdx |
| API Backend 后端 | DeepSeek via `ANTHROPIC_BASE_URL` |
| Proxy 代理 | Clash Verge (port 7897) |

## Investigation Process 排查过程

### Step 1: Log Location 定位日志

[EN] Found `cowork_vm_node.log` at `%LOCALAPPDATA%\Claude-3p\logs\`.

[ZH] 在 `%LOCALAPPDATA%\Claude-3p\logs\` 找到 `cowork_vm_node.log`。

### Step 2: First Error 第一条错误

```
2026-05-03 00:00:35 [info] [VM:start] Beginning startup, bundlePath=
  C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle

2026-05-03 00:00:35 [info] [VM:start] Copying smol-bin.x64.vhdx to bundle...
  smol-bin.x64.vhdx copied successfully

2026-05-03 00:00:35 [info] [VM:start] Configuring Windows VM service...

2026-05-03 00:00:35 [error] [VM:start] Startup failed: Error: failed to set VHDX path:
  VHDX file not found: C:\Users\fanch\AppData\Local\Packages\
  Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude-3p\vm_bundles\
  claudevm.bundle\rootfs.vhdx
```

[EN] **Key observation:** The `bundlePath` is `AppData\Local\Claude-3p\...` but the error path is `Packages\...\LocalCache\Roaming\Claude-3p\...`. The file physically exists at the first path but the native VM code is looking at the second path (MSIX-redirected).

[ZH] **关键发现：** `bundlePath` 是 `AppData\Local\Claude-3p\...` 但错误路径是 `Packages\...\LocalCache\Roaming\Claude-3p\...`。文件物理存在于第一个路径，但原生 VM 代码在第二个路径（MSIX 重定向路径）中查找。

### Step 3: Failed Fix #1 — Directory Junction 失败的修复 #1 — 目录交接点

[EN] Created a junction to make the bundle visible from the redirected path:

[ZH] 创建交接点使 bundle 在重定向路径下可见：

```powershell
mklink /J "C:\Users\fanch\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude-3p"
       "C:\Users\fanch\AppData\Local\Claude-3p"
```

[EN] ✅ Directory listing works — `dir` shows the bundle files through the junction.
[EN] ❌ VM startup STILL fails — MSIX filter driver does not traverse reparse points.

[ZH] ✅ 目录列表能工作——`dir` 通过 junction 能看到文件。
[ZH] ❌ VM 启动仍然失败——MSIX 过滤器驱动不跟随重解析点。

### Step 4: Failed Fix #2 — File Copy 失败的修复 #2 — 文件复制

[EN] Tried to copy rootfs.vhdx to the Packages path, but the file is locked by the running Claude Desktop process. Tried killing Claude processes → killed the debugging session too (the Claude Desktop instance serving this conversation).

[ZH] 尝试复制 rootfs.vhdx 到 Packages 路径，但文件被运行中的 Claude Desktop 锁定。尝试杀掉 Claude 进程 → 一起杀掉了调试会话本身。

### Step 5: Successful Fix — NTFS Hardlinks 成功的修复 — NTFS 硬链接

[EN] Remove the junction and create hardlinks instead:

[ZH] 删除交接点，改用硬链接：

```powershell
# Remove junction
fsutil reparsepoint delete "C:\Users\fanch\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude-3p"

# Create hardlinks for all bundle files
mklink /H <packages_path>\rootfs.vhdx      <appdata_path>\rootfs.vhdx
mklink /H <packages_path>\vmlinuz           <appdata_path>\vmlinuz
mklink /H <packages_path>\initrd            <appdata_path>\initrd
mklink /H <packages_path>\smol-bin.vhdx     <appdata_path>\smol-bin.vhdx
mklink /H <packages_path>\vmlinuz.zst       <appdata_path>\vmlinuz.zst
mklink /H <packages_path>\initrd.zst        <appdata_path>\initrd.zst
mklink /H <packages_path>\rootfs.vhdx.zst   <appdata_path>\rootfs.vhdx.zst
```

### Step 6: Error Progression 错误演进

| Attempt | Error | Status |
|---------|-------|--------|
| Before fix | `VHDX file not found: rootfs.vhdx` | ❌ |
| After rootfs.vhdx hardlink | `kernel not found: vmlinuz` | ✅ **Progress!** 进展！ |
| After vmlinuz hardlink | `initrd not found: initrd` | ✅ **Progress!** 进展！ |
| After all hardlinks | **No error — VM started** | ✅ **Success!** |

### Step 7: Verification 验证

[EN] Cowork workspace successfully started. Linux environment ready. Python 3.10.12, Node.js v22.22.0, file system writable.

[ZH] Cowork 工作空间成功启动。Linux 环境就绪。Python 3.10.12、Node.js v22.22.0、文件系统可写。

---

## Root Cause Summary 根因总结

```
MSIX redirect:
  %APPDATA%\Claude-3p\vm_bundles\...\rootfs.vhdx
  → Packages\{id}\LocalCache\Roaming\Claude-3p\vm_bundles\...\rootfs.vhdx

Junction:
  Packages\...\Roaming\Claude-3p ──[reparse point]──> AppData\Local\Claude-3p
  MSIX filter driver: ⛔ don't follow

Hardlink:
  Packages\...\rootfs.vhdx ──[same NTFS MFT entry]──> AppData\...\rootfs.vhdx
  MSIX filter driver: ✅ transparent
```

## Anti-Patterns Documented 踩过的坑

| Anti-pattern 反模式 | Why it's wrong 为什么错 |
|---|---|
| Debugging WSL instead of fixing Cowork | Didn't listen to the user's priority; changed the problem scope |
| 去折腾 WSL 而不是修 Cowork | 没听用户的优先级；改变了问题范围 |
| Setup-cowork skill flow mid-debug | Irrelevant process that asked role questions instead of fixing |
| 调试中触发 setup-cowork 技能流程 | 无关流程问用户角色而不是修复问题 |
| Re-testing junction 4-5 times | Didn't recognize MSIX limitation; should have switched after 1st failure |
| 反复测试 junction 4-5 次 | 没认识到 MSIX 限制；第一次失败后就应该换方案 |
| Killing Claude process | Killed the debugging session too; lose-lose |
| 杀 Claude 进程 | 同时杀掉了调试会话；双输 |
| Spending time on proxy/WSL config | Entirely unrelated to file path errors |
| 花时间配代理和 WSL | 与文件路径错误毫无关系 |

---

## Timeline 时间线

```
2026-05-02 18:00  First error logged (VHDX not found)
2026-05-03 00:00  Repeated failures (auto-retry loop)
2026-05-03 10:00  User reports issue; debugging begins
2026-05-03 14:57  Network errors appear (auto-reinstall attempted)
2026-05-03 16:10  Junction fix attempted → fails
2026-05-03 16:34  Kernel error appears → Hardlinks working!
2026-05-03 16:35  All hardlinks created
2026-05-03 16:36  VM starts successfully
2026-05-03 16:45  Cowork fully operational
```

---

## Lessons Learned 经验教训

1. **Logs first** — Always read the log before forming a hypothesis.
   **日志先行** — 形成假设前先看日志。
2. **Constraint elimination** — Don't hunt for solutions; eliminate what can't work.
   **约束排除法** — 不要找"什么能用"，而是排除"什么不能用"。
3. **Error change = progress** — A new error means your fix worked at the previous layer.
   **错误变化 = 进展** — 新错误意味着上一层已修复。
4. **MSIX + junction = fail** — AppContainer processes can't traverse reparse points.
   **MSIX + junction = 无效** — AppContainer 不跟随重解析点。
5. **Hardlinks are the MSIX silver bullet** — Filesystem-level, zero-copy, no admin needed.
   **硬链接是 MSIX 的银弹** — 文件系统级、零拷贝、无需管理员。
