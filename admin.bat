@echo off
setlocal

set GODOT="D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set PROJECT="C:\Users\Dexto\Documents\phantasia-revival"

if "%~1"=="" (
    echo.
    echo ========================================
    echo Phantom Badlands Admin Tool
    echo ========================================
    echo.
    echo Usage: admin ^<command^> [args]
    echo.
    echo Commands:
    echo   admin list                         - List all accounts
    echo   admin info ^<username^>              - Show account details
    echo   admin reset ^<username^> ^<password^>  - Reset account password
    echo.
    goto :eof
)

%GODOT% --headless --path %PROJECT% --script admin_tool.gd -- %*
