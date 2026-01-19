@echo off
REM FixZeroTierRoutes.bat - 修复ZeroTier路由配置
REM 需要管理员权限运行

REM 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 请以管理员身份运行此脚本！
    pause
    exit /b 1
)

echo 正在修复ZeroTier路由配置...
echo.

REM 1. 获取本地网关和ZeroTier网关信息
REM 这里使用PowerShell来获取网关信息，因为批处理获取路由信息较复杂
powershell -Command "& {
    # 检测 ZeroTier 是否启用了默认路由分流（/1 routes）
    # 网关地址由 ZeroTier 控制器动态分配
    # 特征：跃点数较高（>1000），或使用 /1 路由
    \$zeroTierGateway = \$null;
    \$zeroTierSplitRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
        (\$_.DestinationPrefix -eq '0.0.0.0/1' -or \$_.DestinationPrefix -eq '128.0.0.0/1') -and
        \$_.RouteMetric -gt 1000
    };

    if (\$zeroTierSplitRoutes) {
        \$zeroTierGateway = \$zeroTierSplitRoutes[0].NextHop;
        Write-Host '检测到 ZeroTier 默认路由分流模式' -ForegroundColor Cyan;
    } else {
        # 传统模式：查找 ZeroTier 默认路由
        # 特征：跃点数较高（>1000），或使用特殊的子网掩码 25.255.255.254
        \$ztDefaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object {
            \$_.RouteMetric -gt 1000 -or \$_.NextHop -like '25.255.255.254'
        } | Sort-Object RouteMetric -Descending | Select-Object -First 1;

        if (\$ztDefaultRoute) {
            \$zeroTierGateway = \$ztDefaultRoute.NextHop;
            Write-Host '检测到 ZeroTier 传统路由模式' -ForegroundColor Cyan;
        } else {
            Write-Host '警告: 未检测到 ZeroTier 网关，尝试通过接口名称识别...' -ForegroundColor Yellow;
            # 尝试通过接口名称识别
            \$ztAdapters = Get-NetAdapter | Where-Object { \$_.InterfaceDescription -like '*ZeroTier*' };
            if (\$ztAdapters) {
                \$interfaceIndex = \$ztAdapters[0].ifIndex;
                \$ztRoute = Get-NetRoute -InterfaceIndex \$interfaceIndex -ErrorAction SilentlyContinue | Where-Object { \$_.DestinationPrefix -eq '0.0.0.0/0' } | Select-Object -First 1;
                if (\$ztRoute) {
                    \$zeroTierGateway = \$ztRoute.NextHop;
                    Write-Host \"通过接口识别到 ZeroTier 网关: \$zeroTierGateway\" -ForegroundColor Cyan;
                }
            }
        }
    }

    \$localRoutes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Where-Object { \$_.NextHop -ne \$zeroTierGateway };
    if (\$localRoutes) {
        \$localGateway = \$localRoutes[0].NextHop;
        \$interfaceIndex = \$localRoutes[0].InterfaceIndex;
        Write-Host \"本地网关: \$localGateway\" -ForegroundColor Green;
        Write-Host \"接口索引: \$interfaceIndex\" -ForegroundColor Green;
        Write-Host \"ZeroTier网关: \$zeroTierGateway\" -ForegroundColor Cyan;

        # 输出到临时文件供批处理使用
        \"\$localGateway\" | Out-File -FilePath \"%TEMP%\\local_gateway.txt\";
        \"\$interfaceIndex\" | Out-File -FilePath \"%TEMP%\\interface_index.txt\";
        \"\$zeroTierGateway\" | Out-File -FilePath \"%TEMP%\\zt_gateway.txt\";
    } else {
        Write-Host \"错误: 无法找到本地网关！\" -ForegroundColor Red;
        exit 1;
    }
}"

if errorlevel 1 (
    echo 获取本地网关失败！
    pause
    exit /b 1
)

REM 读取本地网关、接口索引和ZeroTier网关
set /p LOCAL_GATEWAY=<"%TEMP%\local_gateway.txt"
set /p INTERFACE_INDEX=<"%TEMP%\interface_index.txt"
set /p ZT_GATEWAY=<"%TEMP%\zt_gateway.txt"

echo 本地网关: %LOCAL_GATEWAY%
echo ZeroTier网关: %ZT_GATEWAY%
echo.

REM 2. 处理私有地址段
echo 正在配置私有地址路由...

REM 私有地址段列表
set PRIVATE_RANGES=10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 127.0.0.0/8

for %%R in (%PRIVATE_RANGES%) do (
    echo 添加路由: %%R -> %LOCAL_GATEWAY%
    route add %%R %LOCAL_GATEWAY% IF %INTERFACE_INDEX% >nul 2>&1
    if errorlevel 1 (
        route delete %%R >nul 2>&1
        route add %%R %LOCAL_GATEWAY% IF %INTERFACE_INDEX% >nul 2>&1
    )
)

REM 3. 处理中国大陆IP地址段
if exist "china-ip.txt" (
    echo.
    echo 正在从 china-ip.txt 读取中国大陆IP地址段...

    REM 使用PowerShell处理文件读取和路由添加
    powershell -Command "& {
        \$chinaRanges = Get-Content 'china-ip.txt' | Where-Object { \$_ -match '^\\d+\\.\\d+\\.\\d+\\.\\d+/\\d+\$' };
        \$localGateway = '%LOCAL_GATEWAY%';
        \$interfaceIndex = %INTERFACE_INDEX%;
        \$zeroTierGateway = '%ZT_GATEWAY%';

        Write-Host \"找到 \$(\$chinaRanges.Count) 个中国大陆IP地址段\" -ForegroundColor Green;

        foreach (\$range in \$chinaRanges) {
            try {
                # 检查是否已存在
                \$existingRoute = Get-NetRoute -DestinationPrefix \$range -ErrorAction SilentlyContinue | Where-Object {
                    \$_.NextHop -eq \$localGateway -and \$_.InterfaceIndex -eq \$interfaceIndex
                };

                if (-not \$existingRoute) {
                    # 删除可能冲突的路由（指向ZeroTier网关的）
                    \$conflictingRoutes = Get-NetRoute -DestinationPrefix \$range -ErrorAction SilentlyContinue | Where-Object {
                        \$_.NextHop -eq \$zeroTierGateway
                    };

                    if (\$conflictingRoutes) {
                        foreach (\$cr in \$conflictingRoutes) {
                            Remove-NetRoute -DestinationPrefix \$range -NextHop \$cr.NextHop -InterfaceIndex \$cr.InterfaceIndex -Confirm:\$false -ErrorAction SilentlyContinue;
                        }
                    }

                    # 添加新路由
                    New-NetRoute -DestinationPrefix \$range -NextHop \$localGateway -InterfaceIndex \$interfaceIndex -PolicyStore ActiveStore -ErrorAction Stop;
                    Write-Host \"已添加路由: \$range -> \$localGateway\" -ForegroundColor Green;
                } else {
                    Write-Host \"路由已存在: \$range\" -ForegroundColor Gray;
                }
            }
            catch {
                Write-Host \"添加路由失败: \$range\" -ForegroundColor Red;
            }
        }
    }"
) else (
    echo.
    echo 警告: 未找到 china-ip.txt 文件，跳过中国大陆IP地址段配置
)

REM 4. 显示路由表
echo.
echo 路由配置完成！
echo ========================
echo 本地网关: %LOCAL_GATEWAY%
echo ZeroTier网关: %ZT_GATEWAY%
echo ========================
echo.
echo 当前默认路由:
route print | findstr "0.0.0.0"

echo.
echo 按任意键退出...
pause >nul

REM 清理临时文件
del "%TEMP%\local_gateway.txt" 2>nul
del "%TEMP%\interface_index.txt" 2>nul
del "%TEMP%\zt_gateway.txt" 2>nul