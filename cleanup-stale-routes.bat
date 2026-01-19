@echo off
REM ZeroTier 失效路由快速清理工具启动器
REM 用途: 删除指向失效网关的中国 IP 地址段路由规则

REM 切换到脚本所在目录
cd /d "%~dp0"

REM 以管理员权限调用 PowerShell 包装脚本
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0cleanup-stale-routes-wrapper.ps1"
