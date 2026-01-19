# ZeroTier 路由分析与脚本优化总结

## 一、背景说明

ZeroTier 提供了一个 "Override Default Route" 选项，启用后会创建特殊的路由配置来接管系统流量。本文档分析了启用该选项前后的路由变化，并优化了相应的路由分流脚本。

## 二、路由表变化分析

### 2.1 启用前的路由状态

**关键默认路由：**
```
目标网络        子网掩码          网关         接口        跃点数
0.0.0.0          0.0.0.0      192.168.1.1    192.168.1.108     35
0.0.0.0          0.0.0.0   25.255.255.254    10.121.22.242  10034
0.0.0.0          0.0.0.0   25.255.255.254    10.121.21.242  10034
... (多个 ZeroTier 接口)
```

**特征：**
- 本地默认路由：`0.0.0.0/0` → `192.168.1.1`（跃点数 35，优先级高）
- ZeroTier 默认路由：`0.0.0.0/0` → `25.255.255.254`（跃点数 10034，优先级低）
- 流量优先走本地网关，只有本地不可达时才走 ZeroTier

### 2.2 启用后的路由状态

**新增的关键路由：**
```
目标网络        子网掩码          网关         接口        跃点数
0.0.0.0        128.0.0.0    10.121.19.217    10.121.19.242    291
128.0.0.0        128.0.0.0    10.121.19.217    10.121.19.242    291
```

**技术原理 - 默认路由分流（Route Splitting）：**

ZeroTier 使用了一种特殊的路由劫持技术：

| 路由条目 | 覆盖范围 | 说明 |
|---------|---------|------|
| `0.0.0.0/1` | 0.0.0.0 - 127.255.255.255 | 覆盖整个 IP 地址空间的前一半 |
| `128.0.0.0/1` | 128.0.0.0 - 255.255.255.255 | 覆盖整个 IP 地址空间的后一半 |

**为什么使用 /1 路由而不是 /0？**

1. **最长前缀匹配原则**：`/1` 比 `/0` 更具体，优先级更高
2. **保留原有路由**：不会删除原有的 `0.0.0.0/0` 路由，便于恢复
3. **实现全网劫持**：两条 `/1` 路由合起来覆盖了整个 IPv4 地址空间

**流量走向变化：**
```
启用前：所有流量 → 本地网关（优先）
启用后：所有流量 → ZeroTier 网关（被 /1 路由劫持）
```

## 三、脚本优化方案

### 3.1 核心优化点

#### 3.1.1 自动检测 ZeroTier 路由模式

脚本现在可以自动识别两种模式：

```powershell
# 检测 /1 分流路由
$zeroTierSplitRoutes = Get-NetRoute | Where-Object {
    ($_.DestinationPrefix -eq "0.0.0.0/1" -or $_.DestinationPrefix -eq "128.0.0.0/1") -and
    $_.NextHop -match "^10\.121\.\d+\.217$"
}

if ($zeroTierSplitRoutes) {
    # 检测到默认路由分流模式
} else {
    # 传统默认路由模式
}
```

#### 3.1.2 动态网关识别

不再硬编码 ZeroTier 网关地址，而是：
- 自动检测 `10.121.x.217` 格式的网关
- 支持多个 ZeroTier 虚拟接口
- 适应不同的网络配置

#### 3.1.3 路由冲突处理增强

```powershell
# 删除所有指向 ZeroTier 网关的冲突路由
$conflictingRoutes = Get-NetRoute -DestinationPrefix $range | Where-Object {
    $_.NextHop -eq $zeroTierGateway
}

foreach ($cr in $conflictingRoutes) {
    Remove-NetRoute -DestinationPrefix $range -NextHop $cr.NextHop -InterfaceIndex $cr.InterfaceIndex
}
```

### 3.2 最长前缀匹配的应用

针对 ZeroTier 的 `/1` 路由分流，我们添加的中国 IP 路由（如 `1.0.1.0/24`）会自动优先于 `/1` 路由：

```
优先级比较：
1.0.1.0/24  (前缀长度 24)  → 本地网关  ← 优先级最高
0.0.0.0/1   (前缀长度 1)   → ZeroTier   ← 优先级较低
0.0.0.0/0   (前缀长度 0)   → 本地网关  ← 优先级最低（兜底）
```

## 四、使用方式

### 4.1 PowerShell 脚本（推荐）

```powershell
# 以管理员身份运行
powershell -ExecutionPolicy Bypass -File .\deepseek_powershell_20260118_6f9dd1.ps1
```

**优势：**
- 自动检测并适应两种路由模式
- 彩色输出，易于识别
- 详细的执行统计

### 4.2 批处理脚本

```batch
# 以管理员身份运行
deepseek_batch_20260118_c2fb57.bat
```

**优势：**
- 兼容性更好
- 可以在任务计划程序中使用

## 五、执行效果

### 5.1 预期输出

```
正在修复ZeroTier路由配置...
检测到 ZeroTier 默认路由分流模式
ZeroTier 网关: 10.121.19.217 (接口索引: 37)
找到本地网关: 192.168.1.1 (接口索引: 27)
从 china-ip.txt 读取了 8192 个中国大陆IP地址段
总共需要处理 8199 个地址段
开始配置路由...
检测到 ZeroTier /1 路由分流，将添加具体的路由规则进行覆盖
已添加路由: 1.0.1.0/24 -> 192.168.1.1
已添加路由: 1.0.2.0/23 -> 192.168.1.1
...

路由配置完成！
------------------------
本地网关: 192.168.1.1 (接口索引: 27)
ZeroTier网关: 10.121.19.217 (接口索引: 37)
ZeroTier模式: 默认路由分流 (/1)
处理地址段总数: 8199
新增路由: 8199
跳过路由: 0
------------------------
现在中国大陆IP和私有IP将走本地网关，其他流量通过ZeroTier。
```

### 5.2 验证方法

```powershell
# 查看中国 IP 的路由
Get-NetRoute -DestinationPrefix "1.0.1.0/24"

# 应该看到 NextHop 指向本地网关（如 192.168.1.1）
# 而非 ZeroTier 网关（如 10.121.19.217）
```

## 六、注意事项

### 6.1 路由持久性

- 使用 `-PolicyStore ActiveStore` 添加的路由在系统重启后会丢失
- 建议将脚本配置为开机自动运行（任务计划程序）
- 或使用 `-PolicyStore PersistentStore` 使路由持久化（需谨慎测试）

### 6.2 网关地址自动识别

脚本采用多种方法自动识别 ZeroTier 网关，无需手动配置：

1. **/1 路由检测**：检测 `0.0.0.0/1` 和 `128.0.0.0/1` 路由（默认路由分流模式）
2. **跃点数识别**：查找跃点数大于 1000 的默认路由（ZeroTier 特征）
3. **特殊子网掩码**：识别使用 `25.255.255.254` 的路由
4. **接口名称识别**：通过 "ZeroTier" 虚拟接口名称识别

这种设计适应各种 ZeroTier 网络配置，网关地址由 ZeroTier 控制器动态分配。

### 6.3 文件依赖

脚本期望以下文件存在：
- `china-ip.txt` - 中国 IP 地址段列表（必需，放在脚本同目录下）
- 如果文件不存在，脚本会警告但继续处理私有地址段

## 七、故障排除

### 7.1 常见问题

**问题 1：脚本运行后没有效果**

解决：检查是否有管理员权限，查看脚本输出的错误信息

**问题 2：检测不到 ZeroTier 网关**

解决：
- 确认 ZeroTier 已连接
- 运行 `Get-NetRoute -AddressFamily IPv4` 或 `route print -4` 查看实际的路由表
- 检查是否有 /1 路由（`0.0.0.0/1` 和 `128.0.0.0/1`）
- 如果检测失败，脚本会尝试多种方法自动识别

**问题 3：某些中国网站仍然走 ZeroTier**

解决：
- 检查 `china-ip.txt` 是否完整
- 确认目标 IP 是否在列表中
- 使用 `Get-NetRoute -DestinationPrefix "x.x.x.x/y"` 验证路由

### 7.2 调试命令

```powershell
# 查看所有路由
Get-NetRoute -AddressFamily IPv4 | Format-Table

# 查看特定目标的路由
Get-NetRoute -DestinationPrefix "1.0.1.0/24" | Format-List

# 查看默认路由
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Format-Table

# 查看 /1 分流路由
Get-NetRoute | Where-Object { $_.DestinationPrefix -match "/1$" } | Format-Table
```

## 八、技术参考

### 8.1 Windows 路由优先级

Windows 路由选择顺序：
1. **最长前缀匹配**（Longest Prefix Match）
2. **跃点数**（Route Metric，越小越优先）
3. **路由来源优先级**
4. **路由添加顺序**

### 8.2 相关 PowerShell Cmdlet

| Cmdlet | 用途 |
|--------|------|
| `Get-NetRoute` | 查询路由表 |
| `New-NetRoute` | 添加新路由 |
| `Remove-NetRoute` | 删除路由 |
| `Get-NetIPConfiguration` | 获取网络配置信息 |

### 8.3 ZeroTier 官方文档

- ZeroTier Route Management: https://docs.zerotier.com/route-management
- Default Route Override 是 ZeroTier 1.8+ 版本的功能

## 九、更新日志

### 2026-01-18 - v2.0

**新功能：**
- 自动检测 ZeroTier 默认路由分流模式（/1 routes）
- 动态识别 ZeroTier 网关地址（支持控制器动态分配）
- 增强的路由冲突处理
- 多种网关检测方法（跃点数、接口名称、特殊路由）

**改进：**
- 更详细的输出信息
- 支持多种网络配置
- 更好的错误处理
- 文件名统一为 `china-ip.txt`

**修复：**
- 修复硬编码网关地址导致的问题
- 修复传统路由模式下的兼容性问题
