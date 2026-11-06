@echo off
chcp 65001 >nul
title DuckDNS 动态域名更新程序
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DuckDNS.ps1"
if errorlevel 1 (
    echo.
    echo 程序已退出，请检查上面的错误信息。
    pause
)
