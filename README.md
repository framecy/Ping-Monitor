# PingMonitor

<p align="center">
  <img src="PingMonitor/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="PingMonitor Icon">
</p>

<p align="center">
  <strong>macOS 菜单栏网络延迟监控工具</strong><br>
  多主机监控 · 实时统计 · 可视化图表 · 智能通知 · 桌面小组件
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/SwiftUI-6.0-orange" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-2.0.26-brightgreen" alt="Version">
</p>

---

## ✨ 功能一览

### 🖥 侧边栏导航

原生 macOS `NavigationSplitView` 侧边栏，配合 SF Symbols 图标，快速切换五大模块：监控、统计、主机管理、日志、设置。

### 📡 多主机监控

- 同时监控多个网络地址，自适应网格布局
- 实时连续 Ping 模式，可配置 3/5/10/30 秒间隔
- 绿（<50ms）/ 橙（<100ms）/ 红（>100ms）三色延迟状态
- 每张主机卡片内嵌 **迷你趋势图**，一眼掌握近期波动
- 呼吸灯动画状态指示 + 悬浮放大交互效果

### 📊 数据统计

- **概览卡片** — 请求数、成功率、丢包率、发送/接收流量、运行时长
- **延迟趋势图** — Bézier 平滑曲线 + Y 轴标签 + 50/100ms 阈值参考线 + 脉冲端点指示
- **详细指标** — 单主机或全部主机的最小/最大/平均延迟
- 数值变化过渡动画，数据更新更直观

### 🏷 自定义显示规则

为每个主机设置延迟阈值规则，满足条件时在状态栏和卡片上显示自定义标签：

```
<50ms  → 直连       # 延迟低于 50ms 显示「直连」
>100ms → 转发       # 延迟高于 100ms 显示「转发」
```

### 🔔 智能通知

- 延迟超过阈值或连接失败时自动推送
- 支持 **系统通知** 和 **Bark 远程推送** 两种方式

### 📋 日志系统

- 分级日志（Debug / Info / Warning / Error）
- 按级别筛选，支持导出为文本文件
- 彩色圆点指示器，快速区分日志级别

### 🧩 桌面小组件

三种尺寸（小 / 中 / 大），渐变背景设计，实时显示延迟状态：

| 尺寸 | 显示内容 |
|------|---------|
| 小 | 延迟数值 + 状态图标 + 主机地址 |
| 中 | 延迟数值 + 主机名 + 运行状态 |
| 大 | 完整面板：图标 + 延迟 + 主机 + 状态 + 更新时间 |

### ⚙️ 更多特性

- **状态栏显示策略** — 平均延迟 / 最差主机 / 最快主机 / 首个主机
- **主机预设库** — 内置常用 DNS 和服务器，快速添加
- **自定义 Ping 命令** — 使用 `{host}` 占位符自定义命令
- **开机自启动** — 基于 ServiceManagement 框架
- **菜单栏图标** — 等宽数字字体，运行时实时更新延迟数值

---

## 🛠 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI 6.0 |
| 最低系统 | macOS 14.0+ |
| 架构模式 | MVVM |
| 数据存储 | UserDefaults (App Groups) |
| 小组件 | WidgetKit |
| 自启动 | ServiceManagement |
| 构建工具 | XcodeGen |

---

## 📁 项目结构

```
PingMonitor/
├── PingMonitor/
│   ├── PingMonitorApp.swift      # 应用入口、数据模型、ViewModel
│   ├── MainView.swift            # 全部 UI 视图
│   ├── Info.plist
│   ├── PingMonitor.entitlements
│   └── Assets.xcassets/          # 应用图标
├── PingMonitorWidget/
│   ├── PingMonitorWidget.swift   # 桌面小组件（小/中/大）
│   └── Info.plist
├── project.yml                   # XcodeGen 工程配置
└── build.sh                      # 自动化打包脚本
```

---

## 🚀 编译与安装

### 环境要求

- macOS 14.0+
- Xcode 16+
- XcodeGen：`brew install xcodegen`

### 一键打包

```bash
chmod +x build.sh
./build.sh
```

打包输出至 `~/Desktop/PingMonitor-v{version}-r{build}.dmg`，默认自动递增版本号。

如需关闭自动版本递增，编辑 `build.sh`：

```bash
AUTO_VERSION=false
```

### 安装

1. 双击打开 DMG 文件
2. 将 PingMonitor 拖入 Applications 文件夹
3. 首次打开时允许系统安全提示

---

## 📖 使用指南

### 添加监控主机

1. 进入「主机管理」→ 点击「添加」
2. 输入名称和地址（IP 或域名）
3. 可选：自定义 ping 命令，用 `{host}` 作为地址占位符
4. 或从预设库快速添加常用主机

### 查看统计

1. 切换至「统计」页面
2. 顶部概览卡片显示整体数据
3. 选择「全部主机」或单个主机查看延迟趋势图和详细指标

### 配置状态栏

进入「设置」→「状态栏显示」，选择延迟显示策略和是否显示规则标签。

### 配置通知

进入「设置」→「通知」，选择系统通知或填写 Bark URL 进行远程推送。

---

## 📋 版本历史

| 版本 | 构建 | 更新内容 |
|------|------|---------|
| v2.0.26 | r27 | 修复 macOS 15.7+ 小组件背景色崩溃问题，完善打包脚本 |
| v2.0.25 | r26 | UI 全面重构：侧边栏导航、Bézier 曲线图表、渐变卡片、迷你趋势图、小组件重新设计 |
| v2.0.24 | r25 | 美化卡片、悬浮效果、延迟图表、应用图标 |
| v2.0.22 | r23 | 响应式网格布局、聚合统计、延迟图表 |
| v2.0.20 | r21 | 连续 ping 模式、数据统计 |

---

## 📄 开源协议

MIT License

## 🙏 致谢

- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — 项目工程生成工具
- Apple SwiftUI / WidgetKit / ServiceManagement 框架
