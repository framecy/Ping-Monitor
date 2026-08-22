# PingMonitor

<p align="center">
  <img src="PingMonitor/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" alt="PingMonitor Icon">
</p>

<p align="center">
  <strong>macOS 菜单栏网络延迟监控工具</strong><br>
  多主机监控 · 六维质量评分 · 路由追踪 · Tailscale 集成 · 实时网速 · 桌面小组件
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/SwiftUI-6.0-orange" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-2.5.0-brightgreen" alt="Version">
  <a href="https://github.com/framecy/Ping-Monitor/actions/workflows/ci.yml"><img src="https://github.com/framecy/Ping-Monitor/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  🌐 <strong><a href="https://ping.diswant.space">ping.diswant.space</a></strong>　·　
  📦 <strong><a href="https://github.com/framecy/Ping-Monitor/releases/latest">立即下载</a></strong>
</p>

---

## ✨ 功能一览

### 核心监控与质量评分

- **多主机并发探测**：自适应网格布局，支持 ICMP Ping（3/5/10/30 秒间隔）；绿/橙/红三色及呼吸灯动画实时反映延迟状态
- **六维质量评分**：延迟、稳定性、路径、带宽、DNS 解析、叠加层六个维度综合计算 0–100 分，4096 样本环形缓冲保障评估精度
- **评分降级告警**：分数跌破 40 时触发 Critical 事件，单次 5 轮批次内降幅 ≥20 分触发 Warning 事件
- **数据统计仪表盘**：P99 延迟、丢包率、抖动值（Jitter）；Bézier 延迟趋势曲线（含抖动趋势徽章）、3D 环形图及实时排行榜
- **主机详情**：独立高刷延迟曲线、标准差分析；质量事件流与历史趋势；支持导出单主机 Ping 日志

### 状态栏与网速监控

- **动态状态栏**：平均/最差/最快/首个主机多种显示策略，等宽数字字体防抖对齐；标签规则无匹配时自动回退 `●` 防止条目坍缩
- **实时网速**：上下行速率自动换算（KB/s、MB/s），字号与模块显隐可自由定制
- **流量深度分析**：并行采集接口与进程流量，睡眠/唤醒基准重置；60 秒动态折线图与 7 天累积趋势

### 进阶网络工具

- **路由追踪**：逐跳展示 IP、延迟与丢包率；MTR 持续追踪模式；地图可视化本地→目标完整路径
- **Tailscale 深度集成**：CGNAT 地址段（100.64.0.0/10）即时识别、子网路由匹配；Exit Node 切换；节点延迟批量测试；NAT 类型检测；探针在节点列表延迟加载后自动升级为 Tailscale Ping
- **特权管理器**：FIFO 持久化授权会话，彻底消除 Traceroute/MTR 的重复授权弹窗

### 服务快捷方式与定制

- **快速访问功能区**：可折叠展开、状态持久化；每台主机横向滚动快捷操作列
- **统一快捷面板**：为每台主机配置 Web/SSH/自定义服务跳转，支持 16 种 SF Symbols 图标
- **SSH 自动认证**：基于密钥或密码，支持自定义端口；expect 脚本绕过 AppleScript 授权限制
- **自定义显示规则**：延迟阈值标签（如 `<50ms → 直连`）；`{host}` 占位符自定义 Ping 命令
- **Keep-Alive 策略**：Passive/Intensive/Adaptive 三档，SSH 主机自动升频，空闲主机自动降频

### 更多特性

- **桌面小组件**：小/中/大三款尺寸，渐变背景，三级回退数据同步（App Group → 容器文件 → 共享目录）
- **多语言与通知**：中/英文运行时动态切换；系统通知 + Bark 远程推送
- **审计日志**：Debug/Info/Warning/Error 分级记录，支持按级别/主机检索并导出 `.txt`
- **无感自启**：ServiceManagement 框架开机自启，主窗口关闭时隐藏 Dock 图标

---

## 🛠 技术栈

| 组件 | 技术 |
|------|------|
| UI 框架 | SwiftUI 6.0 |
| 最低系统 | macOS 14.0+ |
| 架构模式 | MVVM + @MainActor · Swift 6 严格并发 |
| 数据共享 | JSON 文件（~/Library/Application Support/PingMonitor/）|
| 小组件 | WidgetKit |
| 自启动 | ServiceManagement |
| 多语言 | 运行时动态切换（Localization.swift）|
| 构建工具 | XcodeGen |

---

## 📁 项目结构

```
PingMonitor/
├── PingMonitor/
│   ├── PingMonitorApp.swift        # 应用入口、ViewModel、探针流水线、质量引擎
│   ├── MainView.swift              # 主视图路由、侧边栏、统计 Tab、质量趋势卡片
│   ├── DashboardView.swift         # 统计仪表盘（3D 饼图、趋势卡片）
│   ├── EditableHostCard.swift      # 主机卡片组件
│   ├── HostDetailView.swift        # 主机详情页（图表、丢包、流量、日志导出）
│   ├── SidebarView.swift           # 侧边栏导航组件
│   ├── ServicesTab.swift           # 服务快捷方式面板
│   ├── NetworkSpeedManager.swift   # 网速监控（接口/进程级，并行采集）
│   ├── NetworkSpeedTab.swift       # 网速 Tab UI
│   ├── TracerouteManager.swift     # 路由追踪逻辑与地理定位
│   ├── TracerouteView.swift        # 路由追踪 UI（地图、跳点表）
│   ├── TailscaleManager.swift      # Tailscale VPN 深度集成
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
│   ├── QualityEngineTests.swift    # 网络质量引擎单元测试
│   └── NetworkSpeedManagerTests.swift  # 网速采集单元测试（34 个用例）
├── docs/                           # GitHub Pages 落地页 (ping.diswant.space)
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
- **查看质量评分**：每张主机卡片实时显示综合评分，「统计」→「质量」Tab 查看六维详细分解与趋势
- **配置状态栏**：「设置」→ 调整延迟显示策略、网速样式与标签规则
- **Tailscale 集成**：「Tailscale」Tab → 一键发现并导入私网节点，支持 Exit Node 切换
- **切换语言**：点击菜单栏窗口右上角「中/EN」即时切换
- **通知推送**：「设置」→「通知」→ 填入 Bark URL 启用移动端推送

---

## 📋 版本历史

| 版本 | 更新内容 |
|------|---------|
| **v2.2.1**<br>状态栏自定义宽度 | 重构状态栏（MenuBar）渲染架构：图标、延迟、规则标签、网速均使用独立且可自定义宽度的 [NSTextAttachment](apple-reference://NSTextAttachment) 渲染，从根本上解决网速/延迟文字变化导致状态栏宽度抖动挤压的问题；在设置界面提供 4 个组件的独立自定义宽度控制，并增加 Combine 属性变化订阅，实现设置更改在状态栏的**秒级实时更新响应**；优化停止监控及全部隐藏时的状态栏收缩排版，加入安全降级微圆点。 |
| **v2.2.0**<br>质量引擎精化 | 修复 resolutionScore 上限不对称（85→100）；修复 <5 样本时 spikeRate 误报；提取 trendPoints 公共 helper 消除 ~80 行重复；趋势评分引入抖动惩罚项；新增 detectScoreDegradation()：分数跌破 40 触发 Critical、单批降幅 ≥20 触发 Warning；质量趋势卡片新增抖动趋势徽章；统计页新增 P99 延迟格；趋势折线颜色统一为固定 accentBlue |
| **v2.1.2-R16**<br>Tailscale CGNAT 检测 | 100.64.0.0/10 地址段即时识别无需等待异步节点列表；匹配 PrimaryRoutes 广播子网路由内 IP；节点列表延迟加载后自动重启探针升级为 Tailscale Ping；切换 tailscale ping 为非 JSON 模式简化延迟解析 |
| **v2.1.2-R14**<br>状态栏 & 网速稳定性 | 标签规则无匹配时显示 `●` 防止状态栏条目坍缩至零宽；并行执行 parseLsof + fetchProcessTraffic 将进程列表刷新耗时减半；新增 isFetchingStats 并发保护防止网速采集重叠；提取 aggregateTotals，修复睡眠唤醒基准重置（Bug #3）与流量计数器回绕（Bug #4）；NetworkSpeedManagerTests 34 个用例全部覆盖 |
| **v2.1.2-R13**<br>快速访问功能区 | 快速访问面板改为可折叠条带；展开时每台主机独立行，固定 110px 名称列 + 横向滚动快捷操作；状态通过 @AppStorage 持久化，默认展开 |
| **v2.1.2-R12**<br>质量引擎 & 特权管理 | 探针诊断框架（ProbeFailureReason / ProbePathKind / HostProbeDiagnostic）；六维网络质量评分引擎（延迟/稳定性/路径/带宽/DNS 解析/叠加层）；PrivilegedManager FIFO 持久化授权，彻底消除重复弹窗；KeepAliveManager 三档策略；ConfigManager 统一配置；FolderMonitor 文件系统监听 |
| **v2.1.1 R1–R9**<br>性能与架构优化 | 缓存 NSRegularExpression / DateFormatter / ByteCountFormatter 静态实例；Widget 同步 5s 防抖节流；MainView.swift 拆分为 5 个独立 Tab 文件；主机拖拽排序；Tailscale 快捷命令面板与 Exit Node 状态标识；浅/深色模式设计系统 |
| **v2.1.0**<br>Traceroute & 状态栏 | Traceroute/MTR 路由追踪地图可视化；全新状态栏（网速仪表盘、固定宽度防抖）；SSH 安全连接；ServiceShortcutsRibbon 常驻面板；网速折线图贝塞尔曲线渐变 |
| **v2.0.x**<br>基础建设 | Tailscale 自动发现与一键导入；服务快捷方式全局面板；NAT 类型检测；WidgetDataManager 三级回退策略；连续 ping 与聚合统计；响应式网格 UI；中英国际化；3D 饼图；小组件首版 |

---

## 📄 开源协议

MIT License © 2026 framecy

## 🙏 致谢

- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — Xcode 工程生成工具
- Apple SwiftUI / WidgetKit / ServiceManagement 框架
