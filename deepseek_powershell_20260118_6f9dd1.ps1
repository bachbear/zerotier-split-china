# FixZeroTierRoutes.ps1 - 修复ZeroTier路由，保持国内和私有IP走本地网关

# 以管理员权限运行检查
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "请以管理员身份运行此脚本！" -ForegroundColor Red
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "正在修复ZeroTier路由配置..." -ForegroundColor Green

# 1. 获取本地网关和ZeroTier网关
$localGateway = $null
$zeroTierGateway = $null
$localInterfaceIndex = $null
$zeroTierInterfaceIndex = $null

# 检测 ZeroTier 是否启用了默认路由分流（/1 routes）
# ZeroTier 使用 0.0.0.0/1 和 128.0.0.0/1 两条路由劫持所有流量
# 网关地址通常是 ZeroTier 网络中的控制器分配的（常见为 10.x.x.1 或类似格式）
# 特征：子网掩码为 25.255.255.254 (特殊值) 或使用 /1 路由
$zeroTierSplitRoutes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
    ($_.DestinationPrefix -eq "0.0.0.0/1" -or $_.DestinationPrefix -eq "128.0.0.0/1") -and
    $_.RouteMetric -gt 1000  # ZeroTier 路由跃点数通常较高
}

if ($zeroTierSplitRoutes) {
    # 启用了 default route override
    $zeroTierGateway = $zeroTierSplitRoutes[0].NextHop
    $zeroTierInterfaceIndex = $zeroTierSplitRoutes[0].InterfaceIndex
    Write-Host "检测到 ZeroTier 默认路由分流模式" -ForegroundColor Cyan
    Write-Host "ZeroTier 网关: $zeroTierGateway (接口索引: $zeroTierInterfaceIndex)" -ForegroundColor Cyan
} else {
    # 传统模式：查找 ZeroTier 默认路由
    # 特征：跃点数较高（>1000），或使用特殊的子网掩码 25.255.255.254
    $ztDefaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Where-Object {
        $_.RouteMetric -gt 1000 -or $_.NextHop -like "25.255.255.254"
    } | Sort-Object RouteMetric -Descending | Select-Object -First 1

    if ($ztDefaultRoute) {
        $zeroTierGateway = $ztDefaultRoute.NextHop
        $zeroTierInterfaceIndex = $ztDefaultRoute.InterfaceIndex
        Write-Host "检测到 ZeroTier 传统路由模式" -ForegroundColor Cyan
        Write-Host "ZeroTier 网关: $zeroTierGateway (接口索引: $zeroTierInterfaceIndex)" -ForegroundColor Cyan
    } else {
        Write-Host "警告: 未检测到 ZeroTier 网关，尝试通过接口名称识别..." -ForegroundColor Yellow
        # 尝试通过接口名称识别（ZeroTier 虚拟接口通常包含 "ZeroTier" 字样）
        $ztAdapters = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*ZeroTier*" }
        if ($ztAdapters) {
            $zeroTierInterfaceIndex = $ztAdapters[0].ifIndex
            # 查找该接口上的路由
            $ztRoute = Get-NetRoute -InterfaceIndex $zeroTierInterfaceIndex -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" } | Select-Object -First 1
            if ($ztRoute) {
                $zeroTierGateway = $ztRoute.NextHop
                Write-Host "通过接口识别到 ZeroTier 网关: $zeroTierGateway" -ForegroundColor Cyan
            }
        }
    }
}

# 获取本地默认网关（非ZeroTier的接口）
$localRoutes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne $zeroTierGateway }

if ($localRoutes) {
    $localGateway = $localRoutes[0].NextHop
    $localInterfaceIndex = $localRoutes[0].InterfaceIndex
    Write-Host "找到本地网关: $localGateway (接口索引: $localInterfaceIndex)" -ForegroundColor Green
} else {
    Write-Host "警告: 未找到本地默认网关，尝试其他方法查找..." -ForegroundColor Yellow
    
    # 尝试通过其他方法获取本地网关
    $networkAdapters = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway }
    foreach ($adapter in $networkAdapters) {
        if ($adapter.IPv4DefaultGateway.NextHop -ne $zeroTierGateway) {
            $localGateway = $adapter.IPv4DefaultGateway.NextHop
            $localInterfaceIndex = $adapter.InterfaceIndex
            Write-Host "找到备用本地网关: $localGateway (接口索引: $localInterfaceIndex)" -ForegroundColor Green
            break
        }
    }
}

if (-not $localGateway) {
    Write-Host "错误: 无法找到本地网关！" -ForegroundColor Red
    pause
    exit 1
}

# 2. 定义需要走本地网关的IP段
# 私有IP地址段
$privateRanges = @(
    "10.0.0.0/8",      # 10.0.0.0 - 10.255.255.255
    "172.16.0.0/12",   # 172.16.0.0 - 172.31.255.255
    "192.168.0.0/16",  # 192.168.0.0 - 192.168.255.255
    "169.254.0.0/16",  # 链路本地地址
    "127.0.0.0/8",     # 环回地址
    "224.0.0.0/4",     # 组播地址
    "255.255.255.255/32" # 广播地址
)

# 3. 从文件读取中国大陆IP地址段
$chinaRanges = @()
$chinaFilePath = "china-ip.txt"

if (Test-Path $chinaFilePath) {
    $chinaRanges = Get-Content $chinaFilePath | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+/\d+$' }
    Write-Host "从 $chinaFilePath 读取了 $($chinaRanges.Count) 个中国大陆IP地址段" -ForegroundColor Green
} else {
    Write-Host "警告: 未找到 $chinaFilePath 文件，将只处理私有地址段" -ForegroundColor Yellow
}

# 4. 合并所有需要处理的地址段
$allRanges = $privateRanges + $chinaRanges

Write-Host "总共需要处理 $($allRanges.Count) 个地址段" -ForegroundColor Green
Write-Host "开始配置路由..." -ForegroundColor Yellow

# 5. 配置路由
$routesAdded = 0
$routesSkipped = 0
$routesDeleted = 0

# 如果 ZeroTier 使用了 /1 分流路由，需要为所有中国IP添加比 /1 更具体的路由
# 因为 /1 路由的优先级低于具体路由（最长前缀匹配原则）
$useSpecificRoutes = $zeroTierSplitRoutes -ne $null

if ($useSpecificRoutes) {
    Write-Host "检测到 ZeroTier /1 路由分流，将添加具体的路由规则进行覆盖" -ForegroundColor Yellow
}

foreach ($range in $allRanges) {
    # 检查是否已存在相同的路由
    $existingRoute = Get-NetRoute -DestinationPrefix $range -ErrorAction SilentlyContinue | Where-Object { 
        $_.NextHop -eq $localGateway -and $_.InterfaceIndex -eq $localInterfaceIndex 
    }
    
    if ($existingRoute) {
        Write-Host "路由已存在: $range -> $localGateway" -ForegroundColor Gray
        $routesSkipped++
        continue
    }
    
    # 尝试删除可能冲突的路由（指向ZeroTier网关的）
    $conflictingRoutes = Get-NetRoute -DestinationPrefix $range -ErrorAction SilentlyContinue | Where-Object {
        $_.NextHop -eq $zeroTierGateway
    }

    if ($conflictingRoutes) {
        foreach ($cr in $conflictingRoutes) {
            Remove-NetRoute -DestinationPrefix $range -NextHop $cr.NextHop -InterfaceIndex $cr.InterfaceIndex -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "已删除冲突路由: $range -> $($cr.NextHop)" -ForegroundColor Yellow
            $routesDeleted++
        }
    }

    # 特殊处理：如果 ZeroTier 使用了 /1 路由，也要检查并删除可能的冲突
    if ($useSpecificRoutes) {
        # 对于 /1 分流模式，不需要额外操作，因为我们添加的是更具体的路由
        # 最长前缀匹配原则会确保我们的路由优先于 /1 路由
    }
    
    # 添加新路由
    try {
        New-NetRoute -DestinationPrefix $range -NextHop $localGateway -InterfaceIndex $localInterfaceIndex -PolicyStore ActiveStore -ErrorAction Stop
        Write-Host "已添加路由: $range -> $localGateway" -ForegroundColor Green
        $routesAdded++
    }
    catch {
        Write-Host "添加路由失败: $range - $_" -ForegroundColor Red
    }
}

# 6. 显示总结
Write-Host "`n路由配置完成！" -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "本地网关: $localGateway (接口索引: $localInterfaceIndex)" -ForegroundColor White
if ($zeroTierGateway) {
    Write-Host "ZeroTier网关: $zeroTierGateway (接口索引: $zeroTierInterfaceIndex)" -ForegroundColor White
    Write-Host "ZeroTier模式: $(if ($useSpecificRoutes) { '默认路由分流 (/1)' } else { '传统模式' })" -ForegroundColor White
}
Write-Host "处理地址段总数: $($allRanges.Count)" -ForegroundColor White
Write-Host "新增路由: $routesAdded" -ForegroundColor Green
Write-Host "跳过路由: $routesSkipped" -ForegroundColor Yellow
if ($routesDeleted -gt 0) {
    Write-Host "删除冲突路由: $routesDeleted" -ForegroundColor Yellow
}
Write-Host "------------------------" -ForegroundColor Cyan
Write-Host "现在中国大陆IP和私有IP将走本地网关，其他流量通过ZeroTier。" -ForegroundColor Green

# 7. 可选：显示当前路由表摘要
Write-Host "`n当前路由表摘要：" -ForegroundColor Cyan
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Select-Object InterfaceAlias, DestinationPrefix, NextHop, RouteMetric | Format-Table -AutoSize

pause