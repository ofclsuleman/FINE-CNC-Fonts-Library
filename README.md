# FINE CNC Fonts Library

A collection of fonts with a one-command Windows installer. Run one PowerShell command on any PC and every font in this repository is installed system-wide, with a GUI to pick which ones you want.

## Repository structure

```
FINE-CNC-Fonts-Library/
├── install.ps1                       # installer (must stay in the root)
├── README.md
└── Fine CNC Font/
    ├── Font Families/                # one folder per font family, containing the complete family
    │   └── <Family Name>/
    ├── Single Fonts/                 # individual font files
    └── Unclassified Fonts/           # fonts that don't belong to a family
```

The installer scans every folder recursively, so it works regardless of how deep the fonts are nested.

## Quick install (one command)

Open **PowerShell** and paste this:

```powershell
$f = "$env:TEMP\fine-cnc-install.ps1"; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/ofclsuleman/FINE-CNC-Fonts-Library/main/install.ps1', $f); powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

What happens next:
1. The installer asks for administrator permission (UAC). Click **Yes**. Fonts are installed into `C:\Windows\Fonts`, so admin rights are required.
2. A window opens listing every font, grouped by folder. Tick the fonts you want (or use **Select all**).
3. Click **Install selected**. The log shows the result of each font.

Restart any open apps (Word, Photoshop, CorelDRAW, etc.) so they can see the new fonts.

## Requirements

| Windows version | Requirement |
|---|---|
| Windows 11 / 10 | Nothing extra. PowerShell 5.1 is built in. |
| Windows 8.1 | Nothing extra. PowerShell 5.1 is built in. |
| Windows 7 SP1 | Install **Windows Management Framework 5.1** (includes PowerShell 5.1) and .NET Framework 4.5 or newer from Microsoft before running the installer. |

- An administrator account (or an admin password for UAC).
- Internet access for the online install. The offline method below does not need it.

## Other install methods

### Offline / manual (ZIP download)

1. On the GitHub page, click **Code → Download ZIP** and extract it.
2. Open PowerShell and run (adjust the path to where you extracted the folder):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Downloads\FINE-CNC-Fonts-Library-main\install.ps1" -SourceDir "C:\Downloads\FINE-CNC-Fonts-Library-main"
```

### Console mode (no GUI, installs everything)

Add `-NoGui` to any command above:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Downloads\FINE-CNC-Fonts-Library-main\install.ps1" -SourceDir "C:\Downloads\FINE-CNC-Fonts-Library-main" -NoGui
```

## Supported font formats

| Extension | Type | Installed |
|---|---|---|
| `.ttf` | TrueType | Yes |
| `.otf` | OpenType | Yes |
| `.ttc` | TrueType / OpenType collection | Yes |
| `.woff`, `.woff2` | Web fonts | No (these are for websites, not Windows) |
| `.fon`, `.pfb`, `.pfm` | Legacy bitmap / Type 1 | No |

## How the installer handles duplicates

- If the exact same font file is already installed, it is skipped and reported as **Already installed**.
- If two different files have the same name (for example, `Regular.ttf` in two different families), the second one is installed with its folder name as a prefix so both can coexist.
- Running the installer again is safe.

## Troubleshooting

| Problem | Fix |
|---|---|
| "Running scripts is disabled on this system" | Use the commands above. They pass `-ExecutionPolicy Bypass` for that one run only and don't change your system settings. |
| `FAILED ... being used by another process` | Close the app that uses the font (Office, Photoshop, CorelDRAW, etc.) and run the installer again. |
| Font is installed but not visible in an app | Restart the app. If it still doesn't show, restart the PC. |
| Installer closes immediately on Windows 7 | Install Windows Management Framework 5.1 first (see Requirements). |
| Download fails on Windows 7 | Make sure .NET Framework 4.5+ is installed, then try again. |

## Uninstalling a font

Delete the font file from `C:\Windows\Fonts` and remove its entry under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts` (Registry Editor). Then restart the PC.

## Maintainers

- `install.ps1` must stay in the **root** of the repository, because the one-line install command points to it.
- If the default branch is not `main`, update `$Branch` in `install.ps1` and the URLs in this README.
- The repository must be **public** for the one-line install to work without a GitHub login.

## License

Each font keeps the license of its original author. Before distributing fonts publicly, make sure you have the right to redistribute them.
