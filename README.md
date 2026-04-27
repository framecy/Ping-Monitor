# PingMonitor

<p align="center">
  <img src="PingMonitor/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="PingMonitor Icon">
</p>

<p align="center">
  <strong>macOS 菜单栏网络延迟监控工具</strong><br>
  多主机监控 · Tailscale 集成 · 路由追踪 · 实时网速 · 桌面小组件
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/SwiftUI-6.0-orange" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-2.1.2--R12-brightgreen" alt="Version">
  <a href="https://github.com/framecy/Ping-Monitor/actions/workflows/ci.yml"><img src="https://github.com/framecy/Ping-Monitor/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  🌐 <strong><a href="https://ping.diswant.space">ping.diswant.space</a></strong>　·　
  📦 <strong><a href="https://github.com/framecy/Ping-Monitor/releases/latest">立即下载</a></strong>
</p>

---

## ✨ 功能一览

### 核心监控与可视化

- **侧边栏导航**：原生 macOS NavigationSplitView，配合 SF Symbols 图标快速切换七大功能模块
- **多主机监控**：自适应网格布局，支持连续 Ping（3/5/10/30 秒间隔）；绿/橙/红三色及呼吸灯动画展示延迟状态，卡片内嵌迷你趋势图
- **数据统计**：请求数、丢包率、流量统计；Bézier 延迟趋势曲线、3D 环形统计图及实时延迟排行榜
- **主机详情**：独立高刷延迟曲线、抖动值（Jitter）、标准差分析；支持导出单主机 Ping 日志

### 状态栏与网速监控

- **动态状态栏**：平均/最差/最快/首个主机多种显示策略，等宽数字字体对齐
- **实时网速**：上下行速率自动换算（KB/s、MB/s），字号与模块显隐可自由定制
- **流量深度分析**：1–10s 动态刷新活跃网卡；60 秒动态折线图与 7 天累积流量趋势

### 进阶网络工具

- **路由追踪**：逐跳展示 IP、延迟与丢包率；MTR 持续追踪模式；地图可视化本地→目标完整路径
- **Tailscale 集成**：自动发现私网节点、一键批量导入；Exit Node 切换与延迟批量测试；NAT 类型检测
- **特权管理器**：FIFO 持久化授权会话，彻底消除 Traceroute/MTR 的重复授权弹窗

### 服务快捷方式与定制

- **统一快捷面板**：为每台主机配置 Web/SSH/自定义服务跳转，支持 16 种 SF Symbols 图标
- **SSH 自动认证**：基于密钥或密码，支持自定义端口；expect 脚本绕过 AppleScript 授权限制
- **自定义显示规则**：延迟阈值标签（如 `<50ms → 直连`）；`{host}` 占位符自定义 Ping 命令
- **Keep-Alive 策略**：Passive/Intensive/Adaptive 三档，SSH 主机自动升频，空闲主机自动降频

### 更多特性

- **桌面小组件**：小/中/大三款尺寸，渐变背景，App Group 双向数据同步
- **多语言与通知**：中/英文运行时动态切换；系统通知 + Bark 远程推送
- **审计日志**：Debug/Info/Warning/Error 分级记录，支持按级别/主机检索并导出 `.txt`
- **网络质量评分**：多维评分（延迟/抖动/丢包/稳定性），实时质量事件流与历史趋势
- **无感自启**：ServiceManagement 框架开机自启，主窗口关闭时隐藏 Dock 图标

---

## 🛠 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI 6.0 |
| 最低系统 | macOS 14.0+ |
| 架构模式 | MVVM + @MainActor |
| 数据共享 | App Group (JSON) |
| 小组件 | WidgetKit |
| 自启动 | ServiceManagement |
| 多语言 | Dynamic Localization |
| 构建工具 | XcodeGen |

---

## 📁 项目结构

```
PingMonitor/
├── PingMonitor/
│   ├── PingMonitorApp.swift        # 应用入口、数据模型、ViewModel、StatusBarController
│   ├── MainView.swift              # 主视图路由与侧边栏导航
│   ├── DashboardView.swift         # 统计仪表盘（3D 饼图、趋势卡片）
│   ├── EditableHostCard.swift      # 主机卡片组件
│   ├── HostDetailView.swift        # 主机详情页（图表、丢包、流量、日志导出）
│   ├── SidebarView.swift           # 侧边栏导航组件
│   ├── ServicesTab.swift           # 服务快捷方式面板
│   ├── NetworkSpeedManager.swift   # 网速监控（接口/进程级）
│   ├── NetworkSpeedTab.swift       # 网速 Tab UI
│   ├── TracerouteManager.swift     # 路由追踪逻辑与地理定位
│   ├── TracerouteView.swift        # 路由追踪 UI（地图、跳点表）
│   ├── TailscaleManager.swift      # Tailscale VPN 集成
│   ├── TailscaleTab.swift          # Tailscale Tab UI
│   ├── WidgetDataManager.swift     # Widget 数据同步（三级回退策略）
│   ├── ConfigManager.swift         # 统一配置存储管理
│   ├── KeepAliveManager.swift      # Keep-Alive 探测策略
│   ├── PrivilegedManager.swift     # FIFO 持久化特权命令会话
│   ├── FolderMonitor.swift         # 文件系统变更监听
│   ├── Components.swift            # 通用 UI 组件（ModernCard 等）
│   ├── Theme.swift                 # 设计系统（颜色、字体、布局）
│   └── Localization.swift          # 中英多语言管理
├── PingMonitorWidget/
│   └── PingMonitorWidget.swift     # 桌面小组件（小/中/大）
├── PingMonitorTests/
│   └── QualityEngineTests.swift    # 网络质量引擎单元测试
├── docs/                           # GitHub Pages 落地页
├── scripts/
│   └── bump_build.sh               # 自动版本号递增脚本
├── project.yml                     # XcodeGen 工程配置
└── build.sh                        # 一键打包脚本（生成 DMG）
```

---

## 🚀 编译与安装

**环境要求**：macOS 14.0+ | Xcode 16+ | XcodeGen

```bash
brew install xcodegen
git clone https://github.com/framecy/Ping-Monitor.git
cd Ping-Monitor
./build.sh
```

打包输出至 `~/Desktop/PingMonitor-v{version}.dmg`，脚本自动递增构建号。

**安装步骤**：
1. 打开 DMG，将 PingMonitor 拖入 Applications 文件夹
2. 首次启动时在「系统设置 → 隐私与安全性」中允许运行

---

## 📖 使用指南

- **添加主机**：「主机管理」→「添加」→ 输入名称与地址；或通过预设库快速导入
- **查看统计**：「统计」页面顶部概览卡片掌握全局，点击主机查看深度图表
- **配置状态栏**：「设置」→ 调整延迟显示策略与网速样式
- **切换语言**：点击菜单栏窗口右上角「中/EN」即时切换
- **通知推送**：「设置」→「通知」→ 填入 Bark URL 启用移动端推送

---

## 📋 版本历史

| 版本 | 更新内容 |
|------|---------|
| **v2.1.2 R12**<br>质量引擎 & 特权管理 | 探针诊断框架（ProbeFailureReason / ProbePathKind / HostProbeDiagnostic）；网络质量多维评分（延迟/抖动/丢包/稳定性）；PrivilegedManager FIFO 持久化授权，彻底消除重复弹窗；KeepAliveManager 三档策略（Passive/Intensive/Adaptive）；ConfigManager 统一配置；FolderMonitor 文件系统监听；TracerouteManager NSLookup 集成与接口优先级路由；Tailscale Exit Node 切换与路径诊断 |
| **v2.1.1 R9**<br>性能优化 | 缓存 NSRegularExpression / DateFormatter / ByteCountFormatter 静态实例，消除高频路径重复创建；Widget 同步 5s 防抖节流，减少 90%+ 无效文件 IO；Ping 主机追踪改为 UUID 查找，消除索引错位风险；MainView.swift（2444 行）拆分为 5 个独立 Tab 文件 |
| **v2.1.1 R1–R6**<br>UI 与 Widget 修复 | 主机拖拽排序；Tailscale 快捷命令面板与 Exit Node 状态标识；浅/深色模式设计系统；规则编辑器布局修复；Widget App Group 双向通讯打通；图表阶梯式警示色（<100ms 绿 / 100–300ms 橙 / >300ms 红） |
| **v2.1.0**<br>Traceroute & 状态栏 | Traceroute/MTR 路由追踪地图可视化；全新状态栏（网速仪表盘、固定宽度防抖）；SSH 安全连接；ServiceShortcutsRibbon 常驻面板；网速折线图贝塞尔曲线渐变 |
| **v2.0.51–v2.0.55**<br>Tailscale & 服务集成 | Tailscale 自动发现与一键导入；服务快捷方式全局面板；NAT 类型检测；WidgetDataManager 三级回退策略 |
| **v2.0.20–v2.0.40**<br>基础建设 | 连续 ping 与聚合统计；响应式网格 UI；中英国际化；3D 饼图；小组件首版；侧边栏导航 |

---

## 📄 开源协议

MIT License © 2026 framecy

## 🙏 致谢

- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — Xcode 工程生成工具
- Apple SwiftUI / WidgetKit / ServiceManagement 框架
