# PingMonitor

<p align="center">
  <img src="PingMonitor/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="PingMonitor Icon">
</p>

<p align="center">
  <strong>macOS 菜单栏网络延迟监控工具</strong><br>
  多主机监控 · Tailscale 集成 · 服务快捷方式 · 实时统计 · 桌面小组件
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/SwiftUI-6.0-orange" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-2.1.2--R2-brightgreen" alt="Version">
</p>

<p align="center">
  🚀 <strong>Official Site: <a href="https://ping.diswant.space">ping.diswant.space</a></strong>
</p>

## ✨ 功能一览

### 核心监控与可视化

- **侧边栏导航**：原生 macOS NavigationSplitView 侧边栏，配合 SF Symbols 图标，快速切换七大功能模块。
- **多主机监控**：自适应网格布局，支持连续 Ping（3/5/10/30 秒间隔）。通过绿/橙/红三色及呼吸灯动画直观展示延迟状态，卡片内嵌迷你趋势图。
- **数据统计**：涵盖请求数、丢包率与流量统计。内置平滑 Bézier 延迟趋势曲线、3D 环形占比统计图及实时延迟排行榜。
- **主机详情视图**：提供独立高刷延迟曲线、抖动值 (Jitter)、标准差分析，并支持导出当前主机的专项操作与 Ping 延迟日志。

### 状态栏扩展与网速监控

- **动态状态栏**：支持平均延迟/最差/最快/首个主机多种显示策略，数字字体等宽对齐。
- **实时网速**：直观显示上下行速率（自动换算 KB/s、MB/s），支持 6-18 字号及模块显隐的高自由度定制。
- **流量深度分析**：1s-10s 动态刷新活跃网卡，提供按应用/网卡分类的 60 秒动态折线图，及跨度达 7 天的累积流量趋势统计。

### 进阶网络工具

- **路由追踪 (Traceroute)**：直观展示每一跳 IP、延迟与丢包率。支持持续追踪的 MTR 模式。
- **地图追踪**：自动获取本地公网 IP 作为起点，在地图上完整绘制并连线至目标地址的地理路径。
- **Tailscale 集成**：自动检测 CLI 并发现私有网络节点，支持一键批量导入监控。实时展示 VPN 状态与本机 IP。

### 服务快捷方式与定制

- **统一快捷面板**：为每个主机配置 Web、SSH 或自定义服务跳转入口。支持 16 种 SF Symbols 图标。
- **SSH 自动认证**：支持自定义端口，提供基于密钥与密码的自动登录模式。
- **自定义显示规则**：灵活设置延迟阈值标签（如 `<50ms -> 直连`）。支持使用 `{host}` 占位符自定义 Ping 命令。

### 更多特性

- **桌面小组件**：提供小/中/大三款尺寸，渐变背景设计，支持系统级实时状态刷新。
- **多语言与通知**：中英文无缝动态切换；支持超限/断连时的系统级通知与 Bark 远程推送。
- **审计日志**：分级记录（Debug/Info/Warning/Error）操作与状态变更，支持按级别/主机检索并导出为 `.txt`。
- **无感自启**：基于 ServiceManagement 框架实现开机自启，纯净驻留菜单栏（主窗口关闭时隐藏 Dock 图标）。

## 技术栈

| **组件**     | **技术选项**                   |
| ------------ | ------------------------------ |
| **UI 框架**  | SwiftUI 6.0                    |
| **最低系统** | macOS 14.0+                    |
| **架构模式** | MVVM                           |
| **数据存储** | File-based Data Sharing (JSON) |
| **小组件**   | WidgetKit                      |
| **自启动**   | ServiceManagement              |
| **多语言**   | Localization (Dynamic)         |
| **构建工具** | XcodeGen                       |

## 项目结构

Plaintext

```
PingMonitor/
├── PingMonitor/
│   ├── PingMonitorApp.swift      # 应用入口、数据模型、ViewModel
│   ├── MainView.swift            # 主视图与标签页
│   ├── DashboardView.swift       # 统计仪表盘（3D 饼图、趋势卡片）
│   ├── SidebarView.swift         # 自定义侧边栏导航
│   ├── EditableHostCard.swift    # 主机卡片组件
│   ├── Components.swift          # 通用 UI 组件
│   ├── Theme.swift               # 设计系统（颜色、字体、布局）
│   ├── LanguageManager.swift     # 中英多语言管理
│   ├── Info.plist
│   ├── PingMonitor.entitlements
│   └── Assets.xcassets/          # 应用图标
├── PingMonitorWidget/
│   ├── PingMonitorWidget.swift   # 桌面小组件（小/中/大）
│   └── Info.plist
├── project.yml                   # XcodeGen 工程配置
└── build.sh                      # 自动化打包脚本
```

## 编译与安装

**环境要求**：macOS 14.0+ | Xcode 16+ | XcodeGen (`brew install xcodegen`)

**一键打包**：

Bash

```
chmod +x build.sh
./build.sh
```

打包将输出至 `~/Desktop/PingMonitor-v{version}.dmg`，默认自动递增版本号。若需关闭自动递增，请将 `build.sh` 中的 `AUTO_VERSION` 设置为 `false`。

**安装步骤**：

1. 双击打开生成的 DMG 文件。
2. 将 PingMonitor 拖入 Applications 文件夹。
3. 首次打开时，请在系统偏好设置中允许安全提示。

## 使用指南

- **添加监控主机**：导航至「主机管理」→ 点击「添加」→ 输入名称与地址（IP 或域名）。也可通过预设库快速导入 DNS。
- **查看数据统计**：切换至「统计」页面，通过顶部概览卡片掌握全局状态，或选中特定主机查看深度图表。
- **配置状态栏与语言**：在「设置」中调整状态栏延迟显示策略；点击顶部菜单栏右上角（中/EN）即时切换语言。
- **管理报警通知**：进入「设置」→「通知」，勾选系统通知，或填入 Bark URL 以启用移动端远程推送。

## 版本动态

最新核心版本：`v2.1.1`

- **Refactor**: 深度性能优化，重构渲染链路与数据同步逻辑，大幅降低内存消耗。
- **Feature**: 新增 Tailscale 快捷面板、监控主机拖拽排序及深浅色模式深度适配。
- **Fix**: 彻底解决 Widget 通讯异常与组件沙盒限制，修复核心 UI 组件的排版错位。
- [查看完整更新日志](https://www.google.com/search?q=./CHANGELOG.md)

## 开源协议与致谢

本项目基于 **MIT License** 开源。

特别感谢以下项目与框架的支持：

- **XcodeGen**：卓越的 Xcode 工程生成工具。
- **Apple Developer**：SwiftUI / WidgetKit / ServiceManagement 等原生底层框架。