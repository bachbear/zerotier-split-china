# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

这是一个用于 Windows 系统的 ZeroTier 路由分流工具。当 ZeroTier VPN 创建全局默认路由时，会导致国内网站访问变慢。本项目通过配置特定的路由规则，使中国大陆 IP 地址段和私有地址段走本地网关，其他流量继续通过 ZeroTier。

## 核心架构

### 路由分流原理

ZeroTier 提供两种路由模式，脚本会自动检测并适配：

**1. 默认路由分流模式（推荐，ZeroTier 1.8+）**
- ZeroTier 使用 `0.0.0.0/1` 和 `128.0.0.0/1` 两条路由劫持所有流量
- 利用最长前缀匹配原则：`/1` 比 `/0` 更具体，优先级更高
- 两条 `/1` 路由合起来覆盖整个 IPv4 地址空间

**2. 传统模式**
- ZeroTier 使用 `0.0.0.0/0` 路由，跃点数较高（>1000）
- 通过高跃点数实现低优先级，保留本地默认路由

**脚本核心逻辑**：
1. 自动检测 ZeroTier 网关（支持动态分配的网关地址）
2. 检测本地物理网卡的默认网关
3. 为中国 IP 段和私有地址段创建更高优先级的路由规则（利用最长前缀匹配）

### 网关自动识别策略

脚本按以下优先级检测 ZeroTier 网关（无需硬编码）：
1. 检测 `/1` 分流路由（`0.0.0.0/1` 和 `128.0.0.0/1`）
2. 查找高跃点数（>1000）的默认路由
3. 识别特殊子网掩码 `25.255.255.254`
4. 通过接口名称识别（包含 "ZeroTier" 字样的虚拟接口）

### 脚本版本体系

**推荐版本**：
- [deepseek_powershell_20260118_6f9dd1.ps1](deepseek_powershell_20260118_6f9dd1.ps1) - 中文版，功能完整

**其他版本**：
- [fix-zerotier-routes.ps1](fix-zerotier-routes.ps1) - 英文版标准实现
- [fix-zerotier-routes-fast.ps1](fix-zerotier-routes-fast.ps1) - 快速版
- [fix-zerotier-routes-ultra-fast.ps1](fix-zerotier-routes-ultra-fast.ps1) - 超快速版（使用 route.exe 批处理）
- [deepseek_batch_20260118_c2fb57.bat](deepseek_batch_20260118_c2fb57.bat) - 批处理版本

### IP 地址段分类

**私有地址段**（硬编码在脚本中）：
- `10.0.0.0/8` - A 类私有网络
- `172.16.0.0/12` - B 类私有网络
- `192.168.0.0/16` - C 类私有网络
- `169.254.0.0/16` - 链路本地地址
- `127.0.0.0/8` - 环回地址
- `224.0.0.0/4` - 组播地址
- `255.255.255.255/32` - 广播地址

**中国大陆 IP 段**：
- 从 [china-ip.txt](china-ip.txt) 文件读取（约 8,788 条 CIDR 记录）
- 使用正则验证格式：`^\d+\.\d+\.\d+\.\d+/\d+$`

## 使用方式

### PowerShell 脚本（推荐）
```powershell
# 以管理员身份运行
powershell -ExecutionPolicy Bypass -File .\deepseek_powershell_20260118_6f9dd1.ps1
```

### 批处理脚本
```batch
# 以管理员身份运行
deepseek_batch_20260118_c2fb57.bat
```

### 自动提权
PowerShell 脚本包含管理员权限检测，如果未以管理员身份运行，会自动请求 UAC 提权。

## 技术细节

### Windows 路由命令

脚本使用以下 PowerShell cmdlet：
- `Get-NetRoute` - 查询路由表
- `New-NetRoute` - 添加新路由（使用 `-PolicyStore ActiveStore` 使路由立即生效但不持久化）
- `Remove-NetRoute` - 删除路由
- `Get-NetIPConfiguration` - 获取网络配置信息
- `Get-NetAdapter` - 获取网络适配器信息

### 路由优先级规则

Windows 根据以下规则选择路由：
1. **最长前缀匹配**（更具体的路由优先）：如 `1.0.1.0/24` 优先于 `0.0.0.0/1`
2. **跃点数**（Route Metric，越小越优先）
3. **路由来源优先级**
4. **路由添加顺序**

**针对 ZeroTier /1 分流的最长前缀匹配示例**：
```
1.0.1.0/24  (前缀长度 24)  → 本地网关  ← 优先级最高
0.0.0.0/1   (前缀长度 1)   → ZeroTier   ← 优先级较低
0.0.0.0/0   (前缀长度 0)   → 本地网关  ← 优先级最低（兜底）
```

### 冲突处理机制

当发现目标 IP 段已存在指向 ZeroTier 网关的路由时，脚本会：
1. 先删除指向 ZeroTier 的冲突路由
2. 再添加指向本地网关的新路由
3. 使用 `-PolicyStore ActiveStore` 确保路由立即生效

## 文件依赖

- **china-ip.txt** - 中国 IP 地址段列表（必需，与脚本同目录）
- 如果文件不存在，脚本会警告但继续处理私有地址段

## 重要注意事项

1. **管理员权限必需**：路由配置需要管理员权限
2. **非持久化路由**：使用 `-PolicyStore ActiveStore` 添加的路由在重启后会丢失，需要重新运行脚本
3. **ZeroTier 网关动态识别**：脚本不再硬编码网关地址，支持 ZeroTier 控制器动态分配的网关
4. **文件依赖**：确保 [china-ip.txt](china-ip.txt) 文件存在于脚本同目录下

## 故障排除

### 查看当前路由表
```powershell
route print -4
# 或
Get-NetRoute -AddressFamily IPv4 | Format-Table
```

### 检查特定路由
```powershell
Get-NetRoute -DestinationPrefix "1.0.1.0/24"
```

### 查看默认路由
```powershell
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Format-Table
```

### 查看 /1 分流路由
```powershell
Get-NetRoute | Where-Object { $_.DestinationPrefix -match "/1$" } | Format-Table
```

### 删除特定路由
```powershell
Remove-NetRoute -DestinationPrefix "1.0.1.0/24" -Confirm:$false
```

## 参考文档

- [zerotier-route-analysis.md](zerotier-route-analysis.md) - 详细的技术分析和优化说明
