<#
.SYNOPSIS
  vnc-tunnel.ps1 -- one-click VNC access to the Debian 12 VM from Windows 10.

.DESCRIPTION
  Two modes:
    -plink   Tunnel VNC over SSH with PuTTY's plink.exe, then open the VNC
             viewer against the local tunnel endpoint. Best for user-mode
             networking, firewalled LANs, or Tailscale (100.116.52.61).
    -Direct  Open the VNC viewer straight at host:port.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File vnc-tunnel.ps1 -Hostname 192.168.188.45
  powershell -ExecutionPolicy Bypass -File vnc-tunnel.ps1 -Hostname 100.116.52.61 -Port 5901
#>
[CmdletBinding()]
param(
    [string]$Hostname = '192.168.188.45',
    [string]$User = 'kamil',
    [int]$Port = 5901,
    [int]$LocalPort = 15901,
    [ValidateSet('plink', 'direct')]
    [string]$Mode = 'plink',
    [switch]$Passive
)

$ErrorActionPreference = 'Stop'

Write-Host "[vnc-tunnel] mode=$Mode host=$Hostname user=$User vnc-port=$Port"

$target = ''
if ($Mode -eq 'plink') {
    if (-not (Get-Command plink.exe -ErrorAction SilentlyContinue)) {
        Write-Host "[vnc-tunnel] plink.exe not found. Install PuTTY:" -ForegroundColor Yellow
        Write-Host "  winget install PuTTY.PuTTY     or     choco install putty"
        exit 1
    }

    $plinkArgs = @('-N', '-L', "$LocalPort`:$Hostname`:$Port", "$User@$Hostname")
    Write-Host "[vnc-tunnel] starting plink: plink $($plinkArgs -join ' ')"
    if ($Passive) {
        Start-Process -WindowStyle Hidden -FilePath 'plink.exe' -ArgumentList $plinkArgs
    } else {
        Start-Process -WindowStyle Minimized -FilePath 'plink.exe' -ArgumentList $plinkArgs
    }
    Start-Sleep -Seconds 2
    $target = "127.0.0.1:$LocalPort"
} else {
    $target = "$Hostname`:$Port"
}

$viewer = $null
foreach ($candidate in @('vncviewer.exe', 'vncviewer64.exe', 'vncviewer32.exe')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $viewer = $candidate
        break
    }
}
if (-not $viewer) {
    foreach ($path in @(
        "$env:ProgramFiles\TigerVNC\vncviewer.exe",
        "$env:ProgramFiles\TightVNC\tvnjviewer.exe",
        "${env:ProgramFiles(x86)}\TightVNC\tvnjviewer.exe"
    )) {
        if (Test-Path $path) { $viewer = $path; break }
    }
}

if ($viewer) {
    Write-Host "[vnc-tunnel] launching $viewer $target"
    Start-Process -FilePath $viewer -ArgumentList $target
} else {
    Write-Host "[vnc-tunnel] no VNC viewer found; open $target with your VNC client."
    Start-Process "vnc://$target"
}
