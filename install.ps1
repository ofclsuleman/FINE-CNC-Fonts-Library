<#
.SYNOPSIS
    FINE CNC Fonts Library - installer (Windows 7 SP1 (PowerShell 5.1 ke saath) se Windows 11 tak).

.DESCRIPTION
    Repo ke andar ki tamam .ttf / .otf / .ttc fonts ko system-wide install karta hai
    (C:\Windows\Fonts + registry). Default mode GUI hai: fonts ki list dikhti hai,
    tick karke install karein. -NoGui se sab fonts console mein bina poochhe install hoti hain.

.PARAMETER SourceDir
    Agar repo pehle se local folder mein extract ho chuka hai to uska path dein.
    Na dein to script GitHub se repo ka ZIP download karega.

.PARAMETER NoGui
    GUI band karke console mein install karein.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -SourceDir "C:\Downloads\FINE-CNC-Fonts-Library-main" -NoGui
#>
param(
    [string]$SourceDir = '',
    [switch]$NoGui
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ----------------------------------------------------------------------------
# Settings (agar repo ki default branch "master" hai to $Branch ko "master" karein)
# ----------------------------------------------------------------------------
$RepoOwner = 'ofclsuleman'
$RepoName  = 'FINE-CNC-Fonts-Library'
$Branch    = 'main'
$ScriptUrl = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch/install.ps1"
$ZipUrl    = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"
$FontExts  = @('.ttf', '.otf', '.ttc')
$FontsDir  = Join-Path $env:WINDIR 'Fonts'
$FontRegKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$script:TempRoot = $null

# ----------------------------------------------------------------------------
# 1. PowerShell version check (Win 7 par PowerShell 2.0 hota hai, usay 5.1 chahiye)
# ----------------------------------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "PowerShell 5.1 ya usse upar chahiye. Aap ka version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "Windows 7 par Windows Management Framework 5.1 (Microsoft ki site se) install karein, phir dobara chalayein."
    Read-Host 'Enter dabayein to band karein' | Out-Null
    exit 1
}

# ----------------------------------------------------------------------------
# 2. Administrator check. Agar admin nahi to UAC ke saath khud ko dobara chalata hai.
# ----------------------------------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    if (-not $PSCommandPath) {
        Write-Host 'Is script ko file ki shakl mein chalayein (install.ps1), direct paste karke nahi.' -ForegroundColor Yellow
        Read-Host 'Enter dabayein' | Out-Null
        exit 1
    }
    $argList = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($NoGui)     { $argList += ' -NoGui' }
    if ($SourceDir) { $argList += ' -SourceDir "' + $SourceDir + '"' }
    Write-Host 'Administrator rights chahiye. UAC prompt par "Yes" dabayein...'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    exit
}

# ----------------------------------------------------------------------------
# 3. Win32 API: font ko current session mein load karna + apps ko notify karna
# ----------------------------------------------------------------------------
$fontApiSrc = @'
using System;
using System.Runtime.InteropServices;
public static class FontApi {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResource(string lpszFilename);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam,
        IntPtr lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
}
'@
if (-not ('FontApi' -as [type])) {
    Add-Type -TypeDefinition $fontApiSrc
}

function Send-FontChange {
    # WM_FONTCHANGE (0x1D) ko sab windows ko broadcast karta hai, taake apps naye fonts dekh len
    $r = [UIntPtr]::Zero
    [void][FontApi]::SendMessageTimeout([IntPtr]0xFFFF, 0x1D, [UIntPtr]::Zero, [IntPtr]::Zero, 0x0002, 1000, [ref]$r)
}

# ----------------------------------------------------------------------------
# 4. Repo ka folder hasil karna (local -SourceDir ya GitHub ZIP download)
# ----------------------------------------------------------------------------
function Get-FontRoot {
    if ($SourceDir) {
        if (-not (Test-Path -LiteralPath $SourceDir)) { throw "SourceDir nahi mila: $SourceDir" }
        return (Resolve-Path -LiteralPath $SourceDir).Path.TrimEnd('\')
    }

    $tmp = Join-Path $env:TEMP ('FineCNC_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $script:TempRoot = $tmp
    $zip = Join-Path $tmp 'repo.zip'

    Write-Host "Repo download ho raha hai..."
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force

    $inner = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    if (-not $inner) { throw 'ZIP extract nahi hui.' }
    return $inner.FullName.TrimEnd('\')
}

# ----------------------------------------------------------------------------
# 5. Repo ke andar tamam font files (kisi bhi depth tak) dhoondna
# ----------------------------------------------------------------------------
function Get-FontList {
    param([string]$Root)

    $files = Get-ChildItem -LiteralPath $Root -Recurse -File |
        Where-Object { $FontExts -contains $_.Extension.ToLower() } |
        Sort-Object FullName

    $list = @()
    foreach ($f in $files) {
        $rel   = $f.FullName.Substring($Root.Length).TrimStart('\')
        $parts = $rel.Split('\')

        if ($parts.Length -gt 1) { $folder = $parts[$parts.Length - 2] } else { $folder = 'root' }
        $safe = ($folder -replace '[^A-Za-z0-9]+', '_').Trim('_')
        if (-not $safe) { $safe = 'font' }

        $list += [pscustomobject]@{
            Label  = $rel
            Path   = $f.FullName
            Name   = $f.Name
            Ext    = $f.Extension.ToLower()
            Prefix = $safe
        }
    }
    return $list
}

# ----------------------------------------------------------------------------
# 6. Ek font install karna
#    - Fonts folder mein copy (same file pehle se ho to skip)
#    - Agar naam pe alag font pehle se ho to folder ka naam prefix laga kar copy
#    - Registry entry (Windows ke liye zaroori)
#    - Current session mein load + apps ko notify
# ----------------------------------------------------------------------------
function Install-OneFont {
    param($Item)
    try {
        $srcHash = (Get-FileHash -LiteralPath $Item.Path -Algorithm SHA256).Hash
        $target  = $Item.Name
        $dest    = Join-Path $FontsDir $target
        $counter = 0

        while ((Test-Path -LiteralPath $dest) -and ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $srcHash)) {
            $counter++
            if ($counter -eq 1) {
                $target = $Item.Prefix + '_' + $Item.Name
            } else {
                $target = $Item.Prefix + '_' + $counter + '_' + $Item.Name
            }
            $dest = Join-Path $FontsDir $target
        }

        $already = Test-Path -LiteralPath $dest
        if (-not $already) {
            Copy-Item -LiteralPath $Item.Path -Destination $dest -Force
        }

        $base = [IO.Path]::GetFileNameWithoutExtension($target)
        if ($Item.Ext -eq '.otf') { $kind = 'OpenType' } else { $kind = 'TrueType' }
        New-ItemProperty -Path $FontRegKey -Name ("$base ($kind)") -Value $target -PropertyType String -Force | Out-Null

        [void][FontApi]::AddFontResource($dest)

        if ($already) { return "Already installed: $($Item.Name)" }
        return "Installed: $target"
    }
    catch {
        return "FAILED: $($Item.Label) -> $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------------------------
# 7. Main
# ----------------------------------------------------------------------------
try {
    $root  = Get-FontRoot
    $fonts = @(Get-FontList -Root $root)

    if ($fonts.Count -eq 0) {
        Write-Host 'Koi font file nahi mili (.ttf / .otf / .ttc).' -ForegroundColor Yellow
    }
    elseif ($NoGui) {
        # ---- Console mode: sab fonts install ----
        $ok = 0; $skip = 0; $fail = 0
        Write-Host "Total fonts mili: $($fonts.Count). Install shuru..."
        foreach ($f in $fonts) {
            $res = Install-OneFont $f
            Write-Host $res
            if ($res -like 'Installed*')    { $ok++ }
            elseif ($res -like 'Already*')  { $skip++ }
            else                            { $fail++ }
        }
        Send-FontChange
        Write-Host ''
        Write-Host "Done. Installed: $ok | Already installed: $skip | Failed: $fail" -ForegroundColor Green
        Write-Host 'Agar fonts kisi app mein nazar na aayein to app ko restart karein.'
        Read-Host 'Enter dabayein to band karein' | Out-Null
    }
    else {
        # ---- GUI mode ----
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        [System.Windows.Forms.Application]::EnableVisualStyles()

        $form = New-Object System.Windows.Forms.Form
        $form.Text            = 'FINE CNC Fonts Installer'
        $form.Size            = New-Object System.Drawing.Size(780, 640)
        $form.StartPosition   = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox     = $false

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text     = "Install karne wale fonts tick karein, phir 'Install selected' dabayein.   Total fonts: $($fonts.Count)"
        $lbl.Location = New-Object System.Drawing.Point(12, 12)
        $lbl.AutoSize = $true
        $form.Controls.Add($lbl)

        $clb = New-Object System.Windows.Forms.CheckedListBox
        $clb.Location        = New-Object System.Drawing.Point(12, 38)
        $clb.Size            = New-Object System.Drawing.Size(740, 330)
        $clb.CheckOnClick    = $true
        $clb.HorizontalScrollbar = $true
        foreach ($f in $fonts) { [void]$clb.Items.Add($f.Label, $true) }
        $form.Controls.Add($clb)

        $btnAll = New-Object System.Windows.Forms.Button
        $btnAll.Text     = 'Select all'
        $btnAll.Location = New-Object System.Drawing.Point(12, 378)
        $btnAll.Size     = New-Object System.Drawing.Size(110, 30)
        $form.Controls.Add($btnAll)

        $btnNone = New-Object System.Windows.Forms.Button
        $btnNone.Text     = 'Clear all'
        $btnNone.Location = New-Object System.Drawing.Point(130, 378)
        $btnNone.Size     = New-Object System.Drawing.Size(110, 30)
        $form.Controls.Add($btnNone)

        $btnInstall = New-Object System.Windows.Forms.Button
        $btnInstall.Text     = 'Install selected'
        $btnInstall.Location = New-Object System.Drawing.Point(530, 378)
        $btnInstall.Size     = New-Object System.Drawing.Size(222, 30)
        $form.Controls.Add($btnInstall)

        $bar = New-Object System.Windows.Forms.ProgressBar
        $bar.Location = New-Object System.Drawing.Point(12, 418)
        $bar.Size     = New-Object System.Drawing.Size(740, 20)
        $bar.Minimum  = 0
        $form.Controls.Add($bar)

        $log = New-Object System.Windows.Forms.TextBox
        $log.Multiline  = $true
        $log.ReadOnly   = $true
        $log.ScrollBars = 'Vertical'
        $log.Location   = New-Object System.Drawing.Point(12, 446)
        $log.Size       = New-Object System.Drawing.Size(740, 140)
        $form.Controls.Add($log)

        $btnAll.Add_Click({
            for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $true) }
        })

        $btnNone.Add_Click({
            for ($i = 0; $i -lt $clb.Items.Count; $i++) { $clb.SetItemChecked($i, $false) }
        })

        $btnInstall.Add_Click({
            $picked = @()
            for ($i = 0; $i -lt $clb.Items.Count; $i++) {
                if ($clb.GetItemChecked($i)) { $picked += $fonts[$i] }
            }
            if ($picked.Count -eq 0) {
                [void][System.Windows.Forms.MessageBox]::Show('Koi font select nahi ki.', 'FINE CNC Fonts Installer')
                return
            }

            $btnInstall.Enabled = $false
            $bar.Maximum = $picked.Count
            $bar.Value   = 0
            $ok = 0; $skip = 0; $fail = 0

            foreach ($f in $picked) {
                $res = Install-OneFont $f
                $log.AppendText($res + [Environment]::NewLine)
                if ($res -like 'Installed*')   { $ok++ }
                elseif ($res -like 'Already*') { $skip++ }
                else                           { $fail++ }
                $bar.Value = $bar.Value + 1
                [System.Windows.Forms.Application]::DoEvents()
            }

            Send-FontChange
            $log.AppendText([Environment]::NewLine + "Done. Installed: $ok | Already installed: $skip | Failed: $fail" + [Environment]::NewLine)
            $log.AppendText('Agar fonts kisi app mein nazar na aayein to app ko restart karein.' + [Environment]::NewLine)
            $btnInstall.Enabled = $true
        })

        [void]$form.ShowDialog()
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Enter dabayein to band karein' | Out-Null
}
finally {
    # Downloaded temp files saaf karna
    if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
