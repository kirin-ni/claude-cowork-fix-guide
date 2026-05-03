<#
.SYNOPSIS
    Batch-create NTFS hardlinks for MSIX bundle files.
    Use when an MSIX-packaged app can't access files through directory junctions.

.DESCRIPTION
    Creates hardlinks from an MSIX redirect path (Packages\...\LocalCache\Roaming\...)
    to the actual file location (AppData\Local\...). Run this AFTER removing any
    existing directory junction at the target.

.PARAMETER SourcePath
    The directory where files actually exist (e.g., AppData\Local\...)

.PARAMETER DestPath
    The MSIX redirect path where files need to appear (Packages\...\LocalCache\Roaming\...)

.PARAMETER Files
    Array of filenames to hardlink. Default covers Claude VM bundle files.

.EXAMPLE
    # Create hardlinks for Claude VM bundle
    .\create-hardlinks.ps1 `
        -SourcePath "C:\Users\fanch\AppData\Local\Claude-3p\vm_bundles\claudevm.bundle" `
        -DestPath   "C:\Users\fanch\AppData\Local\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude-3p\vm_bundles\claudevm.bundle"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$DestPath,

    [string[]]$Files = @(
        "rootfs.vhdx",
        "vmlinuz",
        "initrd",
        "smol-bin.vhdx",
        "vmlinuz.zst",
        "initrd.zst",
        "rootfs.vhdx.zst"
    )
)

# Validate source directory
if (-not (Test-Path $SourcePath)) {
    Write-Error "Source path does not exist: $SourcePath"
    exit 1
}

# Ensure destination directory exists
if (-not (Test-Path $DestPath)) {
    Write-Host "Creating destination directory: $DestPath"
    New-Item -ItemType Directory -Path $DestPath -Force | Out-Null
}

$created = 0
$skipped = 0
$failed = 0

foreach ($f in $Files) {
    $srcFile = Join-Path $SourcePath $f
    $dstFile = Join-Path $DestPath $f

    if (-not (Test-Path $srcFile)) {
        Write-Warning "Source not found, skipping: $srcFile"
        $skipped++
        continue
    }

    if (Test-Path $dstFile) {
        # Check if it's already a hardlink (same file)
        $srcItem = Get-Item $srcFile
        $dstItem = Get-Item $dstFile
        if ($srcItem.LinkType -eq "HardLink" -and $dstItem.LinkType -eq "HardLink") {
            Write-Host "[SKIP] Already hardlinked: $f" -ForegroundColor Yellow
            $skipped++
            continue
        }

        Write-Warning "Destination exists but is not a hardlink: $dstFile"
        Write-Warning "Remove the junction first: fsutil reparsepoint delete `"$DestPath`""
        $failed++
        continue
    }

    $result = cmd.exe /c "mklink /H `"$dstFile`" `"$srcFile`"" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK]   $f" -ForegroundColor Green
        $created++
    } else {
        Write-Host "[FAIL] $f : $result" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "Summary: $created created, $skipped skipped, $failed failed" -ForegroundColor Cyan

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Tip: If you see 'file already exists' errors, there may be a directory" -ForegroundColor Yellow
    Write-Host "junction at the destination. Remove it first:" -ForegroundColor Yellow
    Write-Host "  fsutil reparsepoint delete `"$DestPath`"" -ForegroundColor Yellow
    Write-Host "  # OR" -ForegroundColor Yellow
    Write-Host "  cmd.exe /c rmdir `"$DestPath`"" -ForegroundColor Yellow
}
