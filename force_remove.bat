@echo off
rem HibtDesk Force Removal Script
rem This script authenticates with the admin API before removing HibtDesk and its data.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject("Shell.Application") > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

    echo.
    echo ==========================================
    echo      HibtDesk Secure Uninstaller
    echo ==========================================
    echo.
    echo Please authenticate to proceed.
    echo.

    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$api = 'http://38.181.2.76:3000/api/admin/login'; " ^
        "$u = Read-Host -Prompt 'Admin Username'; " ^
        "$p = Read-Host -Prompt 'Admin Password' -AsSecureString; " ^
        "$pPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p); " ^
        "$pass = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($pPtr); " ^
        "[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pPtr); " ^
        "try { " ^
        "  $body = @{username=$u; password=$pass} | ConvertTo-Json; " ^
        "  $res = Invoke-RestMethod -Uri $api -Method Post -Body $body -ContentType 'application/json'; " ^
        "  if ($res.success) { exit 0 } else { Write-Host 'Error: ' + $res.message; exit 1 } " ^
        "} catch { Write-Host 'Authentication Failed or Network Error'; exit 1 }"

    if %errorlevel% neq 0 (
        echo.
        echo [FAILED] Authentication refused. Uninstallation aborted.
        pause
        exit
    )

    echo.
    echo [SUCCESS] Authentication verified.
    echo Uninstalling HibtDesk...
    timeout /t 2 >nul

    echo Stopping HibtDesk...
    sc stop "HibtDesk"
    sc delete "HibtDesk"
    taskkill /F /IM HibtDesk.exe
    taskkill /F /IM "HibtDesk Tray.exe"
    taskkill /F /IM ffmpeg.exe

    echo Cleaning up Configuration...
    rd /s /q "%APPDATA%\HibtDesk"
    rd /s /q "%SystemDrive%\Windows\ServiceProfiles\LocalService\AppData\Roaming\HibtDesk"

    echo Scheduling deletion...
    start /b "" cmd /c "ping 127.0.0.1 -n 3 > nul & rd /s /q \"%~dp0\" & exit"
    exit
