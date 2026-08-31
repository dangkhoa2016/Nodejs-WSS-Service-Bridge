@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Nodejs-WSS-Service-Bridge - SSH Target
rem ============================================================
rem Nodejs-WSS-Service-Bridge v1.0.0
rem Generic Windows SSH launcher for named tunnel targets
rem
rem Usage:
rem   ssh-via-nodejs-wss-service-bridge.bat "%USERPROFILE%\.ssh\id_ed25519" "kaggle-1"
rem   ssh-via-nodejs-wss-service-bridge.bat "%USERPROFILE%\.ssh\id_ed25519" "colab-1"
rem
rem Optional local-port override:
rem   ssh-via-nodejs-wss-service-bridge.bat "%USERPROFILE%\.ssh\id_ed25519" "my-target" 22010
rem
rem Automatic port map:
rem   kaggle-1 -> 22001
rem   colab-1  -> 22002
rem   kaggle-2 -> 22003
rem   colab-2  -> 22004
rem   ...
rem ============================================================
set "SSH_KEY=%~1"
set "TUNNEL_ID=%~2"
set "LOCAL_PORT=%~3"
if not defined SSH_KEY (
    echo [ERROR] Missing SSH private-key path.
    goto :usage
)
if not exist "%SSH_KEY%" (
    echo [ERROR] SSH private key does not exist:
    echo         %SSH_KEY%
    exit /b 2
)
if not defined TUNNEL_ID (
    echo [ERROR] Missing TUNNEL_ID.
    goto :usage
)
rem ---------- Automatic local-port mapping ----------
if not defined LOCAL_PORT (
    for /f "delims=" %%P in ('powershell -NoProfile -Command ^
      "$id=$env:TUNNEL_ID; if($id -match '^kaggle-(\d+)$'){22000+([int]$Matches[1]*2-1)} elseif($id -match '^colab-(\d+)$'){22000+([int]$Matches[1]*2)} else {''}"') do set "LOCAL_PORT=%%P"
)
if not defined LOCAL_PORT (
    echo [ERROR] Cannot derive a local port from TUNNEL_ID "%TUNNEL_ID%".
    echo         Use kaggle-N / colab-N, or provide argument 3.
    echo.
    echo Example:
    echo   %~nx0 "%SSH_KEY%" "%TUNNEL_ID%" 22010
    exit /b 2
)
rem ---------- Deployment profile from environment ----------
if not defined AGENT_USERNAME if defined TUNNEL_USERNAME set "AGENT_USERNAME=%TUNNEL_USERNAME%"
if not defined RELAY_HOST (
    echo [ERROR] RELAY_HOST is not set.
    echo         Example: set "RELAY_HOST=tunnel.example.com"
    goto :fail
)
if not defined INSTALL_UUID (
    echo [ERROR] INSTALL_UUID is not set.
    goto :fail
)
if not defined AGENT_USERNAME (
    echo [ERROR] AGENT_USERNAME or TUNNEL_USERNAME is not set.
    goto :fail
)
set "TARGET_PORT=2222"
set "SSH_USER=tunneluser"
set "AGENT_DIR=%USERPROFILE%\nodejs-wss-service-bridge-agent"
set "DOWNLOAD_AGENT_URL=https://%RELAY_HOST%/%INSTALL_UUID%-tcp-agent.js"
set "DOWNLOAD_PACKAGE_URL=https://%RELAY_HOST%/%INSTALL_UUID%-tcp-agent-package.json"
rem Per-route state. This is critical on Windows because a running Node
rem process keeps its redirected log file open.
set "PID_FILE=%AGENT_DIR%\agent-%LOCAL_PORT%.pid"
set "LOG_FILE=%AGENT_DIR%\agent-%LOCAL_PORT%.log"
set "ERR_FILE=%AGENT_DIR%\agent-%LOCAL_PORT%.err.log"
set "KEYSCAN_FILE=%TEMP%\nodejs-wss-keyscan-%LOCAL_PORT%.txt"
echo.
echo ============================================================
echo  Nodejs-WSS-Service-Bridge - SSH Target
echo ============================================================
echo  Relay      : %RELAY_HOST%
echo  Target ID  : %TUNNEL_ID%
echo  Local port : %LOCAL_PORT%
echo  Target port: %TARGET_PORT%
echo  SSH user   : %SSH_USER%
echo  SSH key    : %SSH_KEY%
echo ============================================================
echo.
rem ---------- Resolve Node / npm ----------
set "NODE_EXE="
set "NPM_CMD="
for /f "delims=" %%N in ('where node 2^>nul') do if not defined NODE_EXE set "NODE_EXE=%%N"
if not defined NODE_EXE (
    where mise >nul 2>&1
    if not errorlevel 1 (
        pushd "%~dp0"
        for /f "usebackq delims=" %%N in (`mise which node 2^>nul`) do set "NODE_EXE=%%N"
        popd
    )
)
if not defined NODE_EXE (
    echo [ERROR] Node.js was not found in PATH and mise could not resolve it.
    echo         Install Node.js 20+ or configure mise, then retry.
    goto :fail
)
if not exist "%NODE_EXE%" (
    echo [ERROR] Resolved Node executable does not exist:
    echo         %NODE_EXE%
    goto :fail
)
for /f "delims=" %%N in ('where npm.cmd 2^>nul') do if not defined NPM_CMD set "NPM_CMD=%%N"
if not defined NPM_CMD (
    for %%D in ("%NODE_EXE%") do set "NODE_DIR=%%~dpD"
    if exist "%NODE_DIR%npm.cmd" set "NPM_CMD=%NODE_DIR%npm.cmd"
)
if not defined NPM_CMD (
    echo [ERROR] npm.cmd was not found.
    goto :fail
)
where ssh >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Windows OpenSSH Client was not found.
    goto :fail
)
where ssh-keyscan >nul 2>&1
if errorlevel 1 (
    echo [ERROR] ssh-keyscan was not found.
    goto :fail
)
where ssh-keygen >nul 2>&1
if errorlevel 1 (
    echo [ERROR] ssh-keygen was not found.
    goto :fail
)
echo [OK] Node:
"%NODE_EXE%" --version
echo [OK] npm:
call "%NPM_CMD%" --version
echo [OK] SSH:
ssh -V
echo.
rem ---------- Agent workspace ----------
if not exist "%AGENT_DIR%" (
    echo [INFO] Creating agent directory:
    echo        %AGENT_DIR%
    mkdir "%AGENT_DIR%"
    if errorlevel 1 goto :fail
)
rem ---------- Download artifacts once ----------
if not exist "%AGENT_DIR%\tcp-agent.js" (
    echo [INFO] Downloading tcp-agent.js...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $env:DOWNLOAD_AGENT_URL -OutFile (Join-Path $env:AGENT_DIR 'tcp-agent.js')"
    if errorlevel 1 goto :download_fail
) else (
    echo [OK] tcp-agent.js already exists.
)
if not exist "%AGENT_DIR%\package.json" (
    echo [INFO] Downloading package.json...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri $env:DOWNLOAD_PACKAGE_URL -OutFile (Join-Path $env:AGENT_DIR 'package.json')"
    if errorlevel 1 goto :download_fail
) else (
    echo [OK] package.json already exists.
)
if not exist "%AGENT_DIR%\node_modules" (
    echo [INFO] Installing tcp-agent dependencies...
    pushd "%AGENT_DIR%"
    call "%NPM_CMD%" install --omit=dev
    if errorlevel 1 (
        popd
        echo [ERROR] npm install failed.
        goto :fail
    )
    popd
) else (
    echo [OK] node_modules already exists.
)
rem ---------- Stop stale/previous route on THIS local port only ----------
set "OLD_PID="
if exist "%PID_FILE%" set /p OLD_PID=<"%PID_FILE%"
if defined OLD_PID (
    tasklist /FI "PID eq %OLD_PID%" 2>nul | findstr /R /C:" %OLD_PID% " >nul 2>&1
    if not errorlevel 1 (
        echo [INFO] Stopping previous route on port %LOCAL_PORT% ^(PID %OLD_PID%^)...
        taskkill /PID %OLD_PID% /T /F >nul 2>&1
        timeout /t 1 /nobreak >nul
    )
    del "%PID_FILE%" >nul 2>&1
)
rem Refuse to kill an unrelated listener.
set "PORT_PID="
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:"127\.0\.0\.1:%LOCAL_PORT% .*LISTENING"') do set "PORT_PID=%%P"
if defined PORT_PID (
    echo.
    echo [ERROR] 127.0.0.1:%LOCAL_PORT% is already LISTENING by PID %PORT_PID%.
    echo         This process is not owned by this route state file:
    echo         %PID_FILE%
    echo.
    echo If it is an older bridge from a previous BAT version, stop it once:
    echo   taskkill /PID %PORT_PID% /T /F
    echo.
    goto :fail
)
rem ---------- Tunnel password ----------
if not defined AGENT_PASSWORD (
    echo.
    echo Enter the tunnel password used by the relay.
    echo The password will not be displayed and is not written to disk.
    for /f "delims=" %%P in ('powershell -NoProfile -Command ^
      "$s=Read-Host 'Tunnel password' -AsSecureString; $b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try {[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)} finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}"') do set "AGENT_PASSWORD=%%P"
)
if not defined AGENT_PASSWORD (
    echo [ERROR] Tunnel password was empty.
    goto :fail
)
rem ---------- Agent environment ----------
set "TUNNEL_SERVER_URL=wss://%RELAY_HOST%/tcp"
set "AGENT_BIND_HOST=127.0.0.1"
set "AGENT_ROUTES=%LOCAL_PORT%=%TUNNEL_ID%:%TARGET_PORT%"
echo.
echo [INFO] Starting tcp-agent...
echo        Route    : %AGENT_ROUTES%
echo        Log      : %LOG_FILE%
echo        Error log: %ERR_FILE%
del "%LOG_FILE%" >nul 2>&1
del "%ERR_FILE%" >nul 2>&1
pushd "%AGENT_DIR%"
start "" /b "%NODE_EXE%" "tcp-agent.js" 1>"%LOG_FILE%" 2>"%ERR_FILE%"
set "START_RC=%ERRORLEVEL%"
popd
if not "%START_RC%"=="0" (
    echo [ERROR] Failed to launch tcp-agent.
    goto :show_logs_fail
)
echo [INFO] Waiting for 127.0.0.1:%LOCAL_PORT%...
for /L %%I in (1,1,20) do (
    set "AGENT_PID="
    for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:"127\.0\.0\.1:%LOCAL_PORT% .*LISTENING"') do set "AGENT_PID=%%P"
    if defined AGENT_PID goto :agent_ready
    timeout /t 1 /nobreak >nul
)
echo [ERROR] tcp-agent did not listen on port %LOCAL_PORT% within 20 seconds.
goto :show_logs_fail
:agent_ready
> "%PID_FILE%" echo %AGENT_PID%
set "AGENT_PASSWORD="
echo [OK] tcp-agent PID: %AGENT_PID%
echo [OK] Listening: 127.0.0.1:%LOCAL_PORT%
timeout /t 1 /nobreak >nul
findstr /C:"connected" "%LOG_FILE%" >nul 2>&1
if errorlevel 1 (
    echo [WARN] Local listener is ready but relay connection is not confirmed yet.
    echo        Current log:
    type "%LOG_FILE%"
    echo.
)
rem ---------- Remote fingerprint ----------
del "%KEYSCAN_FILE%" >nul 2>&1
ssh-keyscan -T 5 -p %LOCAL_PORT% 127.0.0.1 >"%KEYSCAN_FILE%" 2>nul
if exist "%KEYSCAN_FILE%" (
    for %%Z in ("%KEYSCAN_FILE%") do if %%~zZ GTR 0 (
        echo.
        echo [INFO] SSH host fingerprints for "%TUNNEL_ID%":
        ssh-keygen -lf "%KEYSCAN_FILE%"
        echo.
        echo Verify the ED25519 fingerprint against the target notebook
        echo before accepting a new or changed host key.
    )
)
rem ---------- SSH ----------
echo.
echo [INFO] Connecting to "%TUNNEL_ID%"...
echo        ssh -i "%SSH_KEY%" -p %LOCAL_PORT% %SSH_USER%@127.0.0.1
echo.
ssh -i "%SSH_KEY%" -p %LOCAL_PORT% %SSH_USER%@127.0.0.1
set "SSH_RC=%ERRORLEVEL%"
echo.
echo [INFO] SSH exited with code %SSH_RC%.
echo [INFO] Stopping route "%TUNNEL_ID%" on local port %LOCAL_PORT%...
if defined AGENT_PID taskkill /PID %AGENT_PID% /T /F >nul 2>&1
del "%PID_FILE%" >nul 2>&1
del "%KEYSCAN_FILE%" >nul 2>&1
echo [OK] Route closed.
endlocal
exit /b %SSH_RC%
:show_logs_fail
set "AGENT_PASSWORD="
echo.
echo ==================== %LOG_FILE% ====================
if exist "%LOG_FILE%" type "%LOG_FILE%"
echo.
echo ==================== %ERR_FILE% ====================
if exist "%ERR_FILE%" type "%ERR_FILE%"
echo.
if defined AGENT_PID taskkill /PID %AGENT_PID% /T /F >nul 2>&1
del "%PID_FILE%" >nul 2>&1
goto :fail
:download_fail
echo [ERROR] Failed to download tcp-agent artifacts.
goto :fail
:usage
echo.
echo Usage:
echo   %~nx0 "%USERPROFILE%\.ssh\id_ed25519" "kaggle-1"
echo   %~nx0 "%USERPROFILE%\.ssh\id_ed25519" "colab-1"
echo.
exit /b 2
:fail
set "AGENT_PASSWORD="
echo.
echo [FAILED] SSH bridge did not complete.
endlocal
exit /b 1
