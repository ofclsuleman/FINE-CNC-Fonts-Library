
# ============================================================
# FINE-CNC FONTS LIBRARY
# Automatic Online Font Installer
# Maintained by: ofclsuleman
# Supports: Windows 10 / Windows 11
# Formats: TTF, OTF, TTC
# ============================================================

[CmdletBinding()]
param(
    [string]$Owner = "ofclsuleman",
    [string]$Repository = "FINE-CNC-Fonts-Library",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

# Enable secure HTTPS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ApiHeaders = @{
    "User-Agent" = "FINE-CNC-Fonts-Library-Installer"
    "Accept" = "application/vnd.github+json"
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       FINE-CNC FONTS INSTALLER" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Maintained by: ofclsuleman" -ForegroundColor Gray
Write-Host "Connecting to GitHub..." -ForegroundColor Yellow

# Get latest repository commit
$BranchUrl = "https://api.github.com/repos/$Owner/$Repository/branches/$Branch"

try {
    $BranchInfo = Invoke-RestMethod -Uri $BranchUrl -Headers $ApiHeaders
    $CommitSHA = $BranchInfo.commit.sha
    $TreeSHA = $BranchInfo.commit.commit.tree.sha
}
catch {
    Write-Host "ERROR: Cannot connect to GitHub repository." -ForegroundColor Red
    Write-Host $_.Exception.Message
    return
}

# Get complete repository file list
$TreeUrl = "https://api.github.com/repos/$Owner/$Repository/git/trees/$TreeSHA?recursive=1"

try {
    $TreeResponse = Invoke-RestMethod -Uri $TreeUrl -Headers $ApiHeaders

    if ($TreeResponse.truncated -eq $true) {
        throw "GitHub repository tree is too large to scan completely."
    }
}
catch {
    Write-Host "ERROR: Cannot read repository files." -ForegroundColor Red
    Write-Host $_.Exception.Message
    return
}

# Find supported font files
$FontFiles = @(
    $TreeResponse.tree | Where-Object {
        $_.type -eq "blob" -and
        $_.path -match '(?i)\.(ttf|otf|ttc)$'
    }
)

if ($FontFiles.Count -eq 0) {
    Write-Host ""
    Write-Host "No font files found in the repository." -ForegroundColor Yellow
    Write-Host "Please upload TTF, OTF or TTC files first."
    return
}

Write-Host ""
Write-Host "Total fonts found: $($FontFiles.Count)" -ForegroundColor Green

# Windows current-user font installation directory
$FontDirectory = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"

$RegistryPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

New-Item -ItemType Directory -Path $FontDirectory -Force | Out-Null
New-Item -Path $RegistryPath -Force | Out-Null

# Temporary download folder
$TempDirectory = Join-Path $env:TEMP (
    "FINE-CNC-Fonts-" + [guid]::NewGuid().ToString("N")
)

New-Item -ItemType Directory -Path $TempDirectory -Force | Out-Null

# Native Windows font notification functions
if (-not ("FINECNCLibraryNative" -as [type])) {

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class FINECNCLibraryNative
{
    [DllImport("gdi32.dll", EntryPoint="AddFontResourceW",
        CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern int AddFontResource(string fileName);

    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd,
        uint Msg,
        UIntPtr wParam,
        IntPtr lParam,
        uint flags,
        uint timeout,
        out UIntPtr result
    );
}
"@
}

$InstalledCount = 0
$SkippedCount = 0
$FailedCount = 0
$Index = 0

try {

    foreach ($Font in $FontFiles) {

        $Index++

        $OriginalName = [System.IO.Path]::GetFileName($Font.path)
        $Extension = [System.IO.Path]::GetExtension($OriginalName).ToLowerInvariant()
        $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($OriginalName)

        Write-Progress `
            -Activity "Installing FINE-CNC Fonts" `
            -Status "$OriginalName ($Index of $($FontFiles.Count))" `
            -PercentComplete (($Index / $FontFiles.Count) * 100)

        try {

            # Encode repository path safely for URL
            $EncodedPath = (
                ($Font.path -split '/') |
                ForEach-Object { [uri]::EscapeDataString($_) }
            ) -join '/'

            $RawURL = "https://raw.githubusercontent.com/$Owner/$Repository/$CommitSHA/$EncodedPath"

            # Download to temporary location
            $TempFile = Join-Path $TempDirectory (
                "font_{0:D5}{1}" -f $Index, $Extension
            )

            Invoke-WebRequest `
                -Uri $RawURL `
                -OutFile $TempFile `
                -UseBasicParsing `
                -TimeoutSec 120

            if (-not (Test-Path -LiteralPath $TempFile)) {
                throw "Font download failed."
            }

            if ((Get-Item -LiteralPath $TempFile).Length -eq 0) {
                throw "Downloaded font file is empty."
            }

            # Calculate SHA256 hash
            $SourceHash = (Get-FileHash -LiteralPath $TempFile -Algorithm SHA256).Hash

            # Make filename safe for Windows
            $SafeBaseName = $BaseName

            foreach ($InvalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
                $SafeBaseName = $SafeBaseName.Replace([string]$InvalidChar, "_")
            }

            if ($SafeBaseName.Length -gt 120) {
                $SafeBaseName = $SafeBaseName.Substring(0, 120)
            }

            $TargetName = "$SafeBaseName$Extension"
            $TargetPath = Join-Path $FontDirectory $TargetName

            # Avoid overwriting different fonts with the same filename
            if (Test-Path -LiteralPath $TargetPath) {

                $ExistingHash = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash

                if ($ExistingHash -ne $SourceHash) {

                    $TargetName = "${SafeBaseName}_$($SourceHash.Substring(0,8))$Extension"
                    $TargetPath = Join-Path $FontDirectory $TargetName

                    if (Test-Path -LiteralPath $TargetPath) {

                        $ExistingHash = (Get-FileHash -LiteralPath $TargetPath -Algorithm SHA256).Hash

                        if ($ExistingHash -ne $SourceHash) {
                            throw "A filename collision occurred."
                        }
                    }
                }
            }

            # Install font if not already present
            if (Test-Path -LiteralPath $TargetPath) {

                $SkippedCount++

            }
            else {

                Copy-Item `
                    -LiteralPath $TempFile `
                    -Destination $TargetPath `
                    -ErrorAction Stop

                $InstalledCount++

            }

            # Register font for current Windows user
            $FontDisplayName = [System.IO.Path]::GetFileNameWithoutExtension($TargetName)

            switch ($Extension) {
                ".ttf" { $FontType = "TrueType" }
                ".otf" { $FontType = "OpenType" }
                ".ttc" { $FontType = "TrueType Collection" }
            }

            $RegistryName = "$FontDisplayName ($FontType)"

            New-ItemProperty `
                -Path $RegistryPath `
                -Name $RegistryName `
                -PropertyType String `
                -Value $TargetPath `
                -Force | Out-Null

            # Notify Windows about the newly registered font
            [void][FINECNCLibraryNative]::AddFontResource($TargetPath)

            Write-Host "[OK] $OriginalName" -ForegroundColor Green

        }
        catch {

            $FailedCount++

            Write-Host "[FAILED] $OriginalName" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor DarkRed

        }
    }

    # Notify Windows applications that fonts have changed
    try {

        $Result = [UIntPtr]::Zero

        [void][FINECNCLibraryNative]::SendMessageTimeout(
            [IntPtr]0xffff,
            0x001D,
            [UIntPtr]::Zero,
            [IntPtr]::Zero,
            0x0002,
            1000,
            [ref]$Result
        )

    }
    catch {
        Write-Warning "Windows font notification could not be sent."
    }

}
finally {

    Write-Progress -Activity "Installing FINE-CNC Fonts" -Completed

    # Remove temporary downloaded files
    if (Test-Path -LiteralPath $TempDirectory) {
        Remove-Item -LiteralPath $TempDirectory -Recurse -Force
    }

}

# Final installation report
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "          INSTALLATION COMPLETED" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

Write-Host "Total fonts found : $($FontFiles.Count)" -ForegroundColor White
Write-Host "Newly installed   : $InstalledCount" -ForegroundColor Green
Write-Host "Already installed : $SkippedCount" -ForegroundColor Yellow
Write-Host "Failed            : $FailedCount" -ForegroundColor Red

Write-Host ""
Write-Host "Fonts location:" -ForegroundColor Cyan
Write-Host $FontDirectory -ForegroundColor Gray

Write-Host ""
Write-Host "FINE-CNC Fonts Library" -ForegroundColor Green
Write-Host "Maintained by: ofclsuleman" -ForegroundColor Gray
Write-Host ""
Write-Host "Restart your design applications to use the fonts."
Write-Host ""
