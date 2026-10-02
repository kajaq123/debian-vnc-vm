@echo off
rem ===========================================================================
rem  vnc-tunnel.cmd -- one-click VNC access to the Debian 12 VM from Windows 10
rem
rem  Two modes:
rem    --plink  Tunnel VNC over SSH with PuTTY's plink.exe, then open the
rem             VNC viewer against the tunnel. Use when the VNC port is not
rem             exposed directly (user-mode networking, firewall, Tailscale).
rem    --direct Open the VNC viewer straight at host:port. Use when the VM's
rem             VNC port is reachable on the LAN.
rem
rem  Examples:
rem    vnc-tunnel.cmd --plink --host 192.168.188.45
rem    vnc-tunnel.cmd --plink --host 100.116.52.61 --user kamil
rem    vnc-tunnel.cmd --direct --host 192.168.188.45 --port 5901
rem
rem  Requires: PuTTY (plink.exe) for --plink mode; any VNC viewer
rem  (TigerVNC, TightVNC, or RealVNC) for the viewer step. If plink is
rem  missing:  winget install PuTTY.PuTTY   (or choco install putty)
rem ===========================================================================
setlocal enabledelayedexpansion

set "HOST=192.168.188.45"
set "USER=kamil"
set "PORT=5901"
set "LOCAL_PORT=15901"
set "MODE=plink"

:parse
if "%~1"=="" goto :run
if /i "%~1"=="--plink"   set "MODE=plink"   & shift & goto :parse
if /i "%~1"=="--direct"  set "MODE=direct"  & shift & goto :parse
if /i "%~1"=="--host"    set "HOST=%~2"     & shift & shift & goto :parse
if /i "%~1"=="--user"    set "USER=%~2"     & shift & shift & goto :parse
if /i "%~1"=="--port"    set "PORT=%~2"     & shift & shift & goto :parse
if /i "%~1"=="--local-port" set "LOCAL_PORT=%~2" & shift & shift & goto :parse
if /i "%~1"=="/?"        goto :usage
if /i "%~1"=="--help"    goto :usage
echo Unknown option: %~1
goto :usage

:run
echo [vnc-tunnel] mode=%MODE% host=%HOST% user=%USER% vnc-port=%PORT%

if /i "%MODE%"=="plink" (
  where plink.exe >nul 2>nul
  if errorlevel 1 (
    echo [vnc-tunnel] plink.exe not found. Install PuTTY:
    echo   winget install PuTTY.PuTTY     or     choco install putty
    exit /b 1
  )
  echo [vnc-tunnel] opening SSH tunnel: plink -N -L %LOCAL_PORT%:127.0.0.1:%PORT% %USER%@%HOST%
  start "plink vnc tunnel" /min plink.exe -N -L %LOCAL_PORT%:127.0.0.1:%PORT% %USER%@%HOST%
  set "TARGET=127.0.0.1:%LOCAL_PORT%"
) else (
  set "TARGET=%HOST%:%PORT%"
)

echo [vnc-tunnel] connecting VNC viewer to %TARGET%
call :open_viewer "%TARGET%"
exit /b 0

:open_viewer
set "VIEWER="
for %%V in (vncviewer.exe vncviewer64.exe vncviewer32.exe) do (
  where %%V >nul 2>nul
  if not errorlevel 1 set "VIEWER=%%V"
)
if not defined VIEWER (
  if exist "%ProgramFiles%\TigerVNC\vncviewer.exe" set "VIEWER=%ProgramFiles%\TigerVNC\vncviewer.exe"
)
if not defined VIEWER (
  if exist "%ProgramFiles%\TightVNC\tvnjviewer.exe" set "VIEWER=%ProgramFiles%\TightVNC\tvnjviewer.exe"
)
if not defined VIEWER (
  if exist "%ProgramFiles(x86)%\TightVNC\tvnjviewer.exe" set "VIEWER=%ProgramFiles(x86)%\TightVNC\tvnjviewer.exe"
)
if defined VIEWER (
  echo [vnc-tunnel] launching %VIEWER% %~1
  start "" "%VIEWER%" "%~1"
) else (
  echo [vnc-tunnel] no VNC viewer found in PATH. Open %~1 with your VNC client.
  start "vnc" "vnc://%~1"
)
exit /b 0

:usage
echo.
echo Usage: vnc-tunnel.cmd [--plink ^| --direct] [--host HOST] [--user USER]
echo        [--port PORT] [--local-port PORT]
echo.
echo   --plink        Tunnel VNC over SSH via plink (default)
echo   --direct       Connect directly to host:port
echo   --host HOST    192.168.188.45 (LAN) or 100.116.52.61 (Tailscale)
echo   --user USER    SSH user (default kamil)
echo   --port PORT    VNC port on the VM/host (default 5901)
echo   --local-port   Local tunnel endpoint for --plink (default 15901)
exit /b 2
