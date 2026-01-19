# ZeroTier 路由分流工具

> 让中国大陆 IP 和私有 IP 走本地网关，其他流量通过 ZeroTier VPN

![GitHub](https://img.shields.io/badge/GitHub-bachbear-zerotier--split--china-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Windows-lightgrey)

## 📖 项目简介

当 ZeroTier VPN 启用 **Override Default Route**（覆盖默认路由）功能时，所有网络流量都会通过 ZeroTier，导致访问中国大陆网站变慢。本工具通过配置特定的路由规则，使中国大陆 IP 地址段和私有地址段走本地网关，其他流量继续通过 ZeroTier。

> **⚠️ 注意**：本工具需要管理员权限运行。路由配置是临时的，系统重启后会自动恢复原始配置。

## 🚀 快速开始

### 方式一：在线执行（推荐，无需下载）

直接在 PowerShell（管理员）中运行以下命令：

```powershell
# 添加路由 - 使中国 IP 走本地网关
irm https://raw.githubusercontent.com/bachbear/zerotier-split-china/main/released/fix-routes-simple.ps1 | iex

# 清理路由 - 恢复所有流量通过 ZeroTier
irm https://raw.githubusercontent.com/bachbear/zerotier-split-china/main/released/cleanup-routes-simple.ps1 | iex
```

### 方式二：下载后执行

```bash
# 下载完整压缩包
wget https://github.com/bachbear/zerotier-split-china/archive/refs/heads/main.zip

# 或克隆仓库
git clone https://github.com/bachbear/zerotier-split-china.git
cd zerotier-split-china/released

# 双击运行批处理文件
# fix-routes.bat      - 添加路由
# cleanup-routes.bat  - 清理路由
```

### 方式三：单独下载文件

| 文件 | 下载链接 |
|------|----------|
| fix-routes.bat | [下载](https://raw.githubusercontent.com/bachbear/zerotier-split-china/main/released/fix-routes.bat) |
| cleanup-routes.bat | [下载](https://raw.githubusercontent.com/bachbear/zerotier-split-china/main/released/cleanup-routes.bat) |
| fix-routes-simple.ps1 | [下载](https://raw.githubusercontent.com/bachbear/zerotier-split-china/main/released/fix-routes-simple.ps1) |
| cleanup-routes-simple.ps1 | [下载](https://raw.githubusercontent.com/bachbear/zerotier-split-china/main/released/cleanup-routes-simple.ps1) |
| china-ip.txt | [下载](https://raw.githubusercontent.com/bachbear/zerotier-split-china/main/released/china-ip.txt) |

## 💡 功能说明

### 添加路由（fix-routes.bat）

- ✅ 自动检测 ZeroTier 网关和本地网关
- ✅ 为私有 IP 段添加本地路由
- ✅ 为约 **8,789** 个中国大陆 IP 段添加本地路由
- ✅ 支持 ZeroTier 的两种路由模式（默认路由分流模式和传统模式）

### 清理路由（cleanup-routes.bat）

- 🗑️ 删除所有指向本地网关的中国 IP 路由
- 🗑️ 删除所有指向本地网关的私有 IP 路由
- 🔄 恢复所有流量通过 ZeroTier
- ⚠️ 执行前会要求用户确认

## 📋 路由规则说明

### 私有 IP 地址段（硬编码）

| IP 段 | 说明 |
|-------|------|
| 10.0.0.0/8 | A 类私有网络 |
| 172.16.0.0/12 | B 类私有网络 |
| 192.168.0.0/16 | C 类私有网络 |
| 169.254.0.0/16 | 链路本地地址 |
| 127.0.0.0/8 | 环回地址 |
| 224.0.0.0/4 | 组播地址 |

### 中国大陆 IP 段

从 `china-ip.txt` 文件读取，包含约 **8,789** 个 CIDR 格式的 IP 地址段。数据来源：APNIC、CNNIC 等官方机构发布的 IP 地址分配信息。

## 🔧 技术原理

### ZeroTier 两种路由模式

**默认路由分流模式（推荐，ZeroTier 1.8+）**

ZeroTier 使用 `0.0.0.0/1` 和 `128.0.0.0/1` 两条路由劫持所有流量。利用**最长前缀匹配**原则，我们添加的中国 IP 路由（如 `1.0.1.0/24`）会自动优先于 `/1` 路由。

**传统模式**

ZeroTier 使用 `0.0.0.0/0` 路由，跃点数较高（>1000）。通过高跃点数实现低优先级，保留本地默认路由。

### Windows 路由优先级规则

1. **最长前缀匹配**（更具体的路由优先）：如 `1.0.1.0/24` 优先于 `0.0.0.0/1`
2. **跃点数**（Route Metric，越小越优先）
3. **路由来源优先级**
4. **路由添加顺序**

## ✅ 执行效果

### 添加路由后

| 目标 | 路由方式 |
|------|----------|
| 中国大陆 IP | 本地网关（快速访问） |
| 私有 IP | 本地网关 |
| 其他国际 IP | ZeroTier VPN |

### 清理路由后

- ✅ 所有流量 → ZeroTier VPN

## 🛠️ 故障排除

### 查看当前路由表

```powershell
route print -4
```

### 检查特定路由

```powershell
Get-NetRoute -DestinationPrefix "1.0.1.0/24"
```

### 查看默认路由

```powershell
Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Format-Table
```

### 常见问题

| 问题 | 解决方案 |
|------|----------|
| 脚本运行后没有效果 | 检查是否有管理员权限，查看脚本输出的错误信息 |
| 检测不到 ZeroTier 网关 | 确认 ZeroTier 已连接，运行 `route print -4` 查看路由表 |
| 某些中国网站仍然走 ZeroTier | 检查 `china-ip.txt` 是否完整，确认目标 IP 在列表中 |

## 📁 文件清单

| 文件名 | 说明 |
|--------|------|
| fix-routes.bat | 添加路由的批处理文件（推荐使用） |
| cleanup-routes.bat | 清理路由的批处理文件（推荐使用） |
| fix-routes-simple.ps1 | 添加路由的 PowerShell 脚本 |
| cleanup-routes-simple.ps1 | 清理路由的 PowerShell 脚本 |
| china-ip.txt | 中国大陆 IP 地址段列表（8,789 条） |

## ⚠️ 注意事项

- **管理员权限必需**：路由配置需要管理员权限
- **非持久化路由**：使用 `route.exe` 添加的路由在系统重启后会丢失，需要重新运行脚本
- **文件依赖**：确保 `china-ip.txt` 文件存在于脚本同目录下
- **网络环境**：不同网络环境的 ZeroTier 网关地址可能不同，脚本会自动检测

## 📞 技术支持

如有问题或建议，请通过以下方式联系：

- 📧 **邮箱**：[csc@xiaov.co](mailto:csc@xiaov.co)
- 🐛 **GitHub Issues**：[提交问题](https://github.com/bachbear/zerotier-split-china/issues)
- 📚 **ZeroTier 官方文档**：[https://docs.zerotier.com/](https://docs.zerotier.com/)

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [ZeroTier](https://www.zerotier.com/) - 优秀的 SD-WAN 网络解决方案
- [APNIC](https://www.apnic.net/) - 亚太网络信息中心提供的 IP 地址分配数据

---

**ZeroTier 路由分流工具 v1.0** | 更新日期：2026-01-19

> 本工具仅供学习交流使用，请遵守当地法律法规
