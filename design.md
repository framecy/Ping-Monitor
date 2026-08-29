# PingMonitor 设计文档（design.md）

> 基于 v2.5.0 全量源码审查生成（Swift 侧约 1.8 万行 + 官网 docs 约 3 千行）。
> 逐文件统计所有界面元素、交互、组件、功能逻辑与设计常量。已由独立第三方审计代理逐条回验源码（约 130 条数值/命令/阈值声明），发现的错误与遗漏已全部修正。

---

## 1. 项目概览

| 项 | 值 |
|---|---|
| 产品 | macOS 菜单栏网络延迟监控工具 |
| UI 框架 | SwiftUI 6.0（macOS 14.0+），MVVM + @MainActor，Swift 6 严格并发 |
| 构建 | XcodeGen（project.yml），含 WidgetKit 桌面小组件 target 与测试 target |
| 多语言 | 运行时动态切换（zh / en），自研 Localization.swift，约 500+ 条 key |
| 官网 | docs/（GitHub Pages，ping.diswant.space） |

**架构要点**：无 `MenuBarExtra`、无传统菜单栏下拉。`NSStatusItem` 点击 → 弹出/创建 900×650 主窗口。App 为 agent 应用：窗口打开时 `NSApp.setActivationPolicy(.regular)`，关闭/最小化时切回 `.accessory`（隐藏 Dock 图标）；`windowShouldClose` 拦截红点只 `orderOut`。

**主文件地图**（2026-08-29 重构后，页面按一页一文件组织）：
- `PingMonitorApp.swift`（3082 行）：AppDelegate、全部数据模型、PingMonitorViewModel（探测+质量引擎）、StatusBarController
- `MainView.swift`（363 行）：主窗口框架（SidebarItem 路由 + Header + TailnetStatusPill + 侧边栏拖拽/窗口最小尺寸）
- 页面文件：`MonitorTab.swift`（监控页+快捷服务带+拖拽排序）、`HostManagementTab.swift`（主机管理+模板+模板编辑器）、`SettingsTab.swift`（设置页+OAuth 卡）、`LogsTab.swift`（日志页）、`HostEditorSheet.swift`（主机编辑器+规则行）、`DashboardView.swift`、`HostDetailView.swift`、`TracerouteView.swift`、`NetworkSpeedTab.swift`、`TailscaleTab.swift`、`ServicesTab.swift`、`SidebarView.swift`、`EditableHostCard.swift`
- 管理器：NetworkSpeedManager、TracerouteManager、TailscaleManager、TailscaleAPI、KeepAliveManager、PrivilegedManager、ConfigManager、KeychainStore、WidgetDataManager、LogManager（FolderMonitor 死代码已删除）

---

## 2. 设计体系（Theme.swift）

### 2.1 颜色（动态明暗适配）
| 名称 | 暗色 | 亮色 |
|---|---|---|
| background | #141414 | #F5F5F7 |
| cardBackground | #1F1F1F | white |
| sidebarBackground | #1A1A1A | #EBEBEB |
| onAccent | white | white |
| cardBorder | white 5% | black 6% |
| surfaceOverlay | white 4% | black 3% |
| hoverOverlay | white 9% | black 7% |
| chartGrid | white 6% | black 8% |
| text 系列 | 系统 labelColor 层级 | 同 |

**固定强调色**：accentBlue `#4b5cc4`、accentGreen `#34C759`、accentPurple `#AF52DE`、accentOrange `#FF9500`、accentRed `#FF3B30`、accentCyan `#32ADE6`、accentTeal `#30B0C7`、accentIndigo `#5856D6`、accentMint `#00C7BE`、accentPink `#FF2D55`。含 `Color(hex:)`/`NSColor(hex:)` 解析器（3/6/8 位，8 位按 **ARGB** 字节序）。

### 2.2 字体阶梯（Theme.Fonts.Size）
micro 9 / caption 10 / footnote 11 / body 12 / callout 13 / headline 15 / title 17 / display 22 / hero 28 / giant 40。
- `Fonts.ui`：中文 PingFang SC（bold/heavy/black 归一 semibold），英文 SF Pro Text；
- `Fonts.number`：等宽数字（monospaced design），用于所有延迟/速率数值；
- `Fonts.icon`：必须系统字体（保证 SF Symbols）。

### 2.3 圆角（Theme.Radius）
xs 4（徽标）/ sm 6（小控件、输入框）/ md 8（按钮、列表行）/ lg 12（卡片）/ xl 16（大面板）/ pill 999。

### 2.4 布局常量（Theme.Layout）
cardCornerRadius 12、cardPadding 16、gridSpacing 16、twoColumnMinWidth 280、hostGridMinWidth 260、narrowTableBreakpoint 540、sidebar 220（min 180 / max 360 / 拖拽热区 8）、detailMinWidth 672、tableCellPadding 10×8；`fitsTwoColumns(w) = w ≥ 280×2+16`。

### 2.5 语义状态色（Theme.Status）
- **延迟分档**：host（80/180）、hop（50/100）、overlay（50/150）→ <good 绿 / <warning 橙 / 否则红；
- **分数**：≥90 绿 / 75–89 蓝 / 40–74 橙 / <40 红；
- **severity**：info 蓝 / warning 橙 / critical 红；**path**：direct 绿 / relay 橙 / unknown·nil textTertiary；
- **service type**：web 蓝 / ssh 绿 / custom 橙；
- **ratio(good:warning:)**：成功率等阈值着色工具。

---

## 3. 通用组件（Components.swift）

| 组件 | 定义 |
|---|---|
| `ModernCard` | padding 16 + cardBackground + 圆角 12 + 1px cardBorder 描边 |
| `SectionHeader` | accentBlue 图标 + headline semibold 标题 + 可选 `arrow.clockwise` 刷新按钮 |
| `Badge` | caption bold 文字，color 20% 透明背景，H6/V2，圆角 4 |
| `CardSegmentedControl` | 统一分段切换控件：surfaceOverlay 滑轨 + accentBlue 滑动高亮（matchedGeometryEffect），等宽分段；网速页与主机管理页共用（此前两页各有一套不一致的私有实现） |
| `View.cardBar(topInset:bottomInset:)` | 页面顶部工具栏卡片化样式，与 ModernCard 同视觉语言，替代原通栏材质条 |

另有 Theme 内辅助：`ContainerWidthKey` PreferenceKey + `measureContainerWidth`（容器宽度实测）、`gridCell()`、`tableCellPadding()`。

---

## 4. 状态栏（StatusBarController，NSStatusItem）

**渲染**：图标/延迟/标签 3 段为 18px 高离屏 NSImage 文本附件，网速段为两行文本叠加、高度动态（`maxTextHeight×2+2`），依次拼接；全空时回退占位 `●`（16×18）防坍缩；**停止状态只渲染图标段**（延迟/标签整体隐藏）。字体 `monospacedDigitSystemFont`（默认 9pt），重绘同 runloop 合并（`statusBarUpdatePending`）；average 模式延迟段额外带"平均"文字前缀。

| 段 | 默认宽 | 内容 |
|---|---|---|
| 图标 | 22（范围 10–100 步 2） | 运行 `network.badge.shield.half.filled` / 停止 `network` |
| 延迟 | 40（20–200 步 5） | `12ms`，主机按 DisplayMode |
| 标签 | 40（20–200 步 5） | 首个命中的 DisplayRule 标签，无命中显示 "PING" |
| 网速 | 60（40–250 步 5） | 两行 `↑ x KB/s`（绿）/`↓ y KB/s`（蓝） |

**显示策略** `StatusBarDisplayMode`：average / worst / best / first（默认 first）。
**配色模式**：auto（labelColor + isTemplate）/ light（白）/ dark（黑）。
**监听**：共 17 个 Combine sink——16 个 @Published 变化触发重绘，第 17 个（appAppearance）单独更新外观；网速开启时另起 2.0s 定时器 + NetworkSpeedManager。状态栏无右键菜单、无拖拽，仅左键 toggleWindow。

---

## 5. 主窗口框架（MainView.swift）

### 5.1 布局
- 根 `HStack(spacing:0)`；900×650 为初始 contentRect 与**默认**最小尺寸——实际最小宽随侧边栏拖拽动态变化（侧边栏宽 + detailMinWidth 672，默认 220+672=892），`WindowMinSizeSetter` 同步 NSWindow，过窄时自动放大。窗口位置/大小经 `setFrameAutosaveName("PingMonitorMainWindow")` 持久化（首启居中）。
- 左列 `SidebarView`：宽度可拖拽（SidebarResizer，透明 8pt 热区 + resizeLeftRight 光标，DragGesture 持久化到 `@AppStorage("pm.sidebarWidth")`）。
- 右列：`VStack { headerView; detailContent }`，左缘自绘 1pt 发丝分隔线。
- **内容宽度标准（2026-08-29 统一）**：所有页面滚动列内容水平边距 = `Theme.Layout.cardPadding`(16)，卡片间距 = `Theme.Layout.gridSpacing`(16)——修复 SettingsTab 曾有的 ScrollView 双层 padding（内容 32pt，与 16pt 的页面头卡片错位）；各页卡片间距 20 → gridSpacing 统一。

### 5.2 侧边栏（SidebarView.swift）
- 品牌区：渐变图标（accentBlue→accentPurple `network.badge.shield.half.filled`）+ "PingMonitor"。
- 三个分区（`SidebarSectionHeader` 大写小字）：**概览**（监控/统计/路由跟踪/测速/条件 Tailscale）、**管理**（主机/服务/日志）、**配置**（设置）。
- `SidebarRow`：4×16pt 选中色竖条 + 20pt 图标 + 标题；选中 cardBackground 底 + 各自 activeColor。9 项路由及强调色：

| 项 | 视图 | 图标 | 强调色 |
|---|---|---|---|
| monitor | MonitorTab | waveform.path.ecg | Green |
| statistics | DashboardView | chart.bar.fill | Blue |
| traceroute | TracerouteView | point.topleft.down…curvepath | Cyan |
| netspeed | NetworkSpeedTab | chart.line.uptrend.xyaxis | Teal |
| tailscale | TailscaleTab（总闸控制，不可见时选中回退 monitor） | network | Indigo |
| services | ServicesTab | square.grid.2x2.fill | Mint |
| hosts | HostManagementTab | server.rack | Purple |
| logs | LogsTab | doc.text.fill | Orange |
| settings | SettingsTab | gearshape.fill | textSecondary |

- 底部：分隔线 + 32pt 圆形头像 + `NSFullUserName()` + `vX.Y` 版本号 + gear 进设置。

### 5.3 Header（卡片式页面头，2026-08-29 改版）
- **视觉**：不再是通栏材质条——呼吸灯/标题/副标题/EN 圆钮/TailnetStatusPill/启停胶囊整体置于浮动卡片（cardBackground + 12pt 圆角 + 1pt cardBorder，左右距窗缘 16pt），与页内 ModernCard 同一语言；语言圆钮底色改 surfaceOverlay 保持对比。
- 内容自左向右：
1. **呼吸状态灯**：24pt 绿圆 opacity 扩散动画（1.5s easeInOut repeatForever，scale 1.6→0）+ 中心 10pt 实心圆（运行绿带阴影 / 停止灰）；
2. 页标题 + 副标题（"Monitoring N hosts" / "Stopped"）；
3. **语言切换圆钮**（"EN"/"中"）；
4. **TailnetStatusPill**（条件）：只读胶囊，`online/total` 设备数或同步失败/Tailscale/未连接，颜色红/蓝/灰，点击跳 Tailscale 页；
5. **启停按钮**：运行=红底 `stop.fill`"停止"，停止=绿底 `play.fill`"开始"，背景 15% 透明。

---

## 6. 页面明细

### 6.1 监控页 MonitorTab
- 工具栏（**cardBar 卡片**）：标题"监控 (N)" + borderedProminent "+" 添加主机；空态 `ContentUnavailableView`。
- **QuickAccessServicesRibbon**（快捷服务带）：
  - 折叠头 36pt：`bolt.fill` 橙图标 + "快捷访问" + chevron（`@AppStorage("pm.quickAccessExpanded")` 持久化，spring 0.28/0.82）。
  - 每行：6pt 状态圆点 + 主机名（110pt 固定列）+ 水平滚动服务 chips（SF 图标 + 名称 + WEB/SSH/CMD pill）。点击打开：web/custom `NSWorkspace.open`；ssh 生成 `/tmp/pm_ssh_<8位>.command` 脚本（自删 + chmod +x，绕过 AppleScript 授权）。`.help` 显示目标预览；右键：打开 / 复制目标。
- **主机网格**：`LazyVGrid(adaptive minimum:280, spacing:12)`，项为 `EditableHostCard`；点击卡片 spring 打开 HostDetailView 侧滑覆盖层（move(edge:.trailing) + 背景 blur 2pt + 遮罩点击关闭）；**拖拽排序**：onDrag(NSItemProvider UUID) + HostDropDelegate（dropEntered 异步 moveHost）。

### 6.2 主机卡片 EditableHostCard
- **状态色**：未运行灰（**全局**总开关停止时所有卡片回灰）/ 暂停 textTertiary / 检测中蓝 / 不可达有历史红、无历史灰 / 可达：<100 绿 <300 橙 ≥300 红。hover 时边框 = statusColor 0.5。
- 元素自上而下：
  1. 头部：32pt 图标底（statusColor 0.15）+ `server.rack`；名称（暂停附 pause 小图标）+ 地址；右侧延迟大数字 / "超时"（红）/ "…"；
  2. **质量徽章**：胶囊描边，"分数+等级词"（90+优 / 75-90良 / 60-75中 / 40-60差 / <40危），样本 <5 显示"测量中…"；
  3. **四 compactMetric 小格**：可用率（good 99 / warning 95）、P95（蓝）、丢包率（>3% 红）、抖动（橙）；
  4. **三 infoPill**：路径（直连/中继）、成功率（`checkmark.shield`）、服务数；
  5. **迷你趋势图**：Charts 最近 20 点，LineMark 1.5pt + AreaMark 渐变（0.3→0），monotone，高 32pt；
  6. **页脚**：探测模式图标（TCP=`cable.connector`/ICMP=`waveform.path.ecg`）+ 标签 + 诊断文本（类别着色与图标：超时/DNS 失败/无路由/网络不可达/主机宕机/连接拒绝/权限不足/进程错误/未知共 **9 类**）；右侧 `checklist` 图标 + "N 条规则"（仅非空）；
  7. **hover 操作钮**：暂停/继续、编辑、删除（红）；hover 放大 1.01 + 状态色阴影（spring 0.3/0.7）；
  8. **右键菜单**：开始/停止｜编辑｜删除（destructive）。

### 6.3 统计页 DashboardView（当前路由指向）
- 布局：ScrollView + 容器宽度实测，≥576pt 双列 Grid（GridRow 等高），否则单列；时间窗 Picker（1m/5m/1h，默认 5m）。
- **QualityScoreCard**：巨型分数（giant bold，Theme.Status.score 着色）+ "/100"；P95 / 平均丢包 / 平均抖动三个 metricBlock；健康/劣化/严重主机数三个 statusPill（绿/橙/红）。
- **QualityDimensionsCard**：六维度行（8pt 高进度条）：延迟蓝 / 稳定性绿 / 路径健康橙 / 带宽压力紫 / 解析青 / overlay 红；"隧道占比"（>70% 变橙）。
- **QualityTrendCard**：趋势图（AreaMark 蓝渐变 0.28→0.02 + LineMark 2pt，Y 0–100，高 180pt）+ 底部分数/P95/丢包 summaryTag。
- **RecentEventsCard**：事件条目（8pt 严重度圆点 + 标题 + 时间 + 主机名 + 详情）。
- **HostHealthCard**：斑马纹 Grid 表格，宽度自适应 6/3/1 列（IP+主机名 / 分数 / P95 / 抖动 / 丢包 / 路径），主机名下追加最近失败原因一行。
- **TrafficContextCard**：物理流量（蓝）与隧道流量（紫）面板（↑↓ 速率）、隧道占比进度条、流量 Top1 进程。
- *旧统计页 StatisticsTab 已在 2026-08-29 重构中删除*（零调用点死代码，含 AggregatedStats/StatsRawMetricsCard 等 13 项原始指标卡实现；其"13 项指标"若需恢复可参见 git 历史）。

### 6.4 路由跟踪 TracerouteView
- 顶栏（**cardBar 卡片**）：主机输入框（320pt，onSubmit 开始）、**MTR 开关**（Toggle switch，运行时禁用）、Start/Stop 胶囊、NSLookup 按钮、复制按钮（成功 1.5s 变 ✓）、MTR 提示行。
- 空态：渐变大图标 + 3 个 QuickTarget（8.8.8.8 / 1.1.1.1 / baidu.com）+ 已监控主机网格（MonitoredHostCard 点击即追踪）。
- 结果态 **VSplitView**：
  - 上部 **TracerouteMapView**（MapKit）：逐跳地理坐标 MapPolyline 折线（蓝 2pt）+ 每跳 12pt latencyColor 圆标注 + 跳数标签；相机随 hops 自适应包围盒；仅 MapZoomStepper。
  - 下部：statusBar（ProgressView/checkmark + 进度文本 + 3 个 HopSummaryBadge：跳数/平均延迟/超时数）→ 路由上下文 3 个 RouteContextBadge（源地址〔隧道口橙/普通绿〕、接口、网关）→ NSLookup 卡片（DNS 服务器/记录/rawOutput）→ **逐跳表**。
- **逐跳表**列：`#`（左缘 3×20 latencyColor 色条）、IP（主机名+IP）、延迟 1/2/3、平均、丢包、Location（GeoIP 城市+ISP）；列宽 640pt 基准按容器等比缩放（下限 0.55）；超时显示 `* * *`；行 hover 高亮 + 偶数行斑马纹；MTR 模式下 sent/received/best/worst 累计。
- **TracerouteManager**：`/usr/sbin/traceroute -n -I -m 30 -q 3 -w 1`，并按路由上下文追加 `-i <接口>` 与 `-s <源地址>`（ICMP ECHO；`/usr/bin/script -q /dev/null` 包装骗 TTY）；追踪中的错误行（unreachable/no route/unknown host 等）实时显示在进度文本里；MTR = shell 每秒 1 轮循环 + 轮次合并（latencies 保留最近 3 次、滚动平均，逐跳表底部有 "..." 加载行）；`route -n get` 解析路由上下文（接口/网关/源地址，隧道接口智能回避）；GeoIP 走 ip-api.com（actor 缓存 + 私网跳过，Tailscale 100.x 与 IPv6 ULA `fd7a:115c:a1e0:` 前缀 hop 从节点表取 "Relay: x"）；NSLookup 解析 Server/CNAME/A 记录（空态页也可先解析后追踪，失败显示红色错误）；结果复制为对齐文本表。

### 6.5 测速页 NetworkSpeedTab
- 顶部**分段 Tab**（**cardBar 卡片**内，`CardSegmentedControl` 统一组件，等宽分段 + 滑动高亮）：接口 / 进程。
- **接口页 6 卡**：
  1. **speedOverviewCard**：上传（紫 hero 字号）/下载（青）大速率 + 累计字节；右侧刷新间隔 Picker（1/2/3/5/10s）+ 接口选择 Picker；"all" 时追加 Tunnel/VPN 行（隧道速率取 utun max 防重复计数，说明文字硬编码英文）。
  2. **speedChartCard**：60 秒折线（Upload 紫 / Download 青，Line+Area 渐变，高 120pt），历史容量 60 条。
  3. **topProcessesCard**：Top5 进程（名称 + PID + ↑↓ 速率，>1024 B/s 才显示）+ 右上"监控中主机"按钮（`monitor.title`）跳进程页。
  4. **trafficStatsCard**：区间合计（30min/1h/24h/7d Picker）：总下载/总上传/总流量三块。
  5. **trafficTrendCard**：7 天趋势图（140pt，7d 显示 MM/dd 否则 HH:mm）+ 导出 CSV（NSSavePanel）+ 重置（红 trash）。
  6. **interfaceDetailsCard**：按 InterfaceFamily 分组折叠（tunnel 族取成员 max，其他求和；默认展开 wifi/ethernet）；组行 chevron + 族图标 + 成员数徽章 + default_route 绿徽章 + 速率对；展开后每接口行：活动圆点 + Physical/Tunnel 徽章 + 错误数（橙）+ ↑↓ 速率与累计 + PKT 包数（K/M 缩写）；点击行切换全局选中接口（选中底色蓝 0.10）。
- **进程页 ProcessListView**：搜索栏（进程名/PID/用户/连接地址）+ 刷新按钮 + 计数摘要；进程卡：首字母色块（10 色 hash 调色板）+ 名称/PID/user + 速率（总速 >100 B/s 且各向 >10 B/s 才显示）+ 协议/连接数/EST 徽章 + **Kill 按钮**（红，Alert 确认 → SIGTERM，失败走 PrivilegedManager 提权 `kill -9`；结果 Toast 2s 自动消失，但**不校验提权结果，失败也提示已结束**）；展开**连接表**：协议（TCP 蓝/UDP 橙）/ 本地 / 远程 / 状态徽章（ESTABLISHED 绿 / LISTEN 蓝 / *_WAIT 橙 / SYN_* 青 / FIN_*、CLOSING 红）。
- **注意**：流量趋势卡的"重置"按钮**无二次确认**，点击即清历史（HostDetail 的"重置统计"同样无确认）。
- **NetworkSpeedManager**：接口字节 `netstat -bni`；速率 = delta/elapsed；**睡眠唤醒重置**（elapsed > 5×interval 丢弃增量重建 baseline）；默认路由 15s 刷新（`route -n get default`）；进程流量 2s 并发 `lsof -i -n -P` + `nettop -P -L 1` 按 PID 聚合；60s 快照持久化 `traffic_history.json`（保留 7 天）；区间统计按相邻快照单调增量累加；单位 1024 进制（B/s → GB/s）。
- 注：README 提到的"字号与模块显隐定制"在当前 NetworkSpeedTab 中**不存在**（定制项在设置页仅针对状态栏）；Jitter 定义为 max−min（非标准差）。

### 6.6 Tailscale 页 TailscaleTab（总闸 `pm.enableTailscale` + `pm.tailscaleAdminMode` 管理模式）
卡片流（Status → 清单 → Netcheck → 健康建议 → Quick Commands → DERP → 节点）：
1. **StatusCard**：刷新按钮 + 三列（状态圆点 Connected/Disconnected、我的 IP accentBlue、节点数）+ 错误条。
2. **清单卡**：导入全部在线设备 / 刷新按钮 + 管理模式橙 Badge；六个统计块（Total 蓝 / Online 绿 / Monitored 紫 / Update、Key Expiring 橙 / Unauthorized 红，条件显示）；设备行（在线圆点 + 标签徽章组 + IP/os/连接类型/lastSeen + 导入按钮）；管理模式 ellipsis 菜单：授权/取消授权（Alert 确认）、密钥过期开关、路由子菜单（`0.0.0.0/0` 与 `::/0` 均标 "(exit route)"，已启用带 ✓；执行中该行转 spinner 并禁用其他菜单）、编辑标签 sheet（自动补 `tag:` 前缀）、删除（Alert 确认）。
3. **Netcheck 卡**：NAT 类型（Easy 绿盾 / Symmetric 橙盾 / 其他红盾）+ Preferred DERP；6 协议徽章（UDP/IPv4/IPv6/UPnP/Hairpin/门户，✓绿/✗红）；全局 IPv4/IPv6。
4. **健康建议卡**：lightbulb 橙 + 文案条目（UDP 被封/对称 NAT 等 4 种）。
5. **Quick Commands**：Status / Netcheck / Ping All 三个终端风按钮。
6. **DERP 延迟卡**：前 10 区域水平条形图（归一化比例条 + ms 数值，overlay 阈值着色）。
7. **节点列表**：头部含独立的「导入全部在线节点」按钮；节点行为系统图标（osIcon：mac→laptopcomputer、win→desktopcomputer、linux→server.rack、ios→iphone、android→smartphone）+ Self 徽章 + 在线状态 + 连接类型徽章（P2P 绿 bolt / Relay 橙 / DERP 紫 cloud）+ **路径诊断按钮**（`tailscale ping --json --c=1`，仅在线非 Self 显示，诊断中转 spinner）+ Exit Node 紫色图标（仅状态展示，**无切换控件**）+ 导入监控按钮/已导入胶囊；lastPingResult 结果行（P2P 绿 / Error 红 / 其他橙）；离线节点整行 0.5 透明。页面 onAppear 自动触发 fetchStatus + fetchNetcheck + refreshInventory。
- **底层**：TailscaleManager 探测 CLI（/usr/local/bin、/opt/homebrew、App 包，失败再 `which tailscale` 兜底），`status --json` / `netcheck --format=json`，26 个 DERP 区域硬编码（纳秒→ms）；`TailscaleAPIClient`（actor，文件 TailscaleAPI.swift）：OAuth client_credentials（凭据存 KeychainStore `com.pingmonitor.app`）+ `/api/v2/tailnet/-/devices` + 设备授权/密钥/标签/路由/删除端点，token 缓存 401 重试，清单轮询 Timer（默认 60s，min 30s）。

### 6.7 服务页 ServicesTab
- 统计卡：标题 + "+ 添加"按钮 + 4 个可点过滤徽章（All / Web 蓝 / SSH 绿 / 自定义橙）。
- 按主机分组卡片：可达圆点 + 主机名 + 地址 + 单机 "+" + 计数胶囊；服务项网格（adaptive 200）：32pt 类型色图标块 + 名称 + `user@url`/url 副标题 + 类型大写徽章 + `arrow.up.right`；右键：打开/编辑/删除。
- **ShortcutEditorSheet**（宽 420）：主机选择 Picker、类型分段（切换时自动换图标/回填地址）、名称、URL/SSH 主机、SSH 专属区（用户名 + 端口 + 认证方式分段 key/password + SecureField）+ **等宽绿字命令预览**、**16 种图标选择网格**（globe、network、server.rack、desktopcomputer、externaldrive…、house.fill、film.fill、music.note、doc.text.fill、photo.fill、gamecontroller.fill、chart.bar.fill、lock.shield.fill、terminal.fill、cloud.fill、gear）；Cancel/Save（校验非空）。
- SSH 命令构造：`-p` 非默认端口、`-i` key 路径、密码模式内联 `expect -c 'spawn…send…interact'`（密码转义）。

### 6.8 主机管理页 HostManagementTab
- 分段控件已替换为 `CardSegmentedControl` 统一组件（"已保存 (N)" / "常用模板 (N)"，等宽分段 + 滑动高亮，置于 **cardBar 卡片**内）。
- **已保存**：`HostManagementCard` 网格（server.rack 蓝图标 + 名称 + 地址 + 规则 chips ≤3 条 + 探测模式行 + 命令行；hover 显编辑/删除圆钮 + 放大 1.01；右键：编辑/删除）。添加主机默认规则 `<50ms→Direct`、`>100ms→Relay`。
- **模板**：`PresetManagementCard`（bookmark 橙图标 + "+" 加入监控绿钮；右键：加入监控/编辑/删除；内置 8.8.8.8 / 1.1.1.1 / 百度 / 淘宝）+ PresetEditorSheet（宽 380：名称/地址/命令）。

### 6.9 日志页 LogsTab
- 工具栏（**cardBar 卡片**）：级别分段 Picker（全部/DEBUG/INFO/WARN/ERROR）+ 清空 + 导出（fileExporter，默认名 `PingMonitor_Logs_<时间戳>.txt`；单主机导出为 `<主机名>_Logs_<时间戳>.txt` 且行内不带主机名前缀）。
- 日志列表装入卡片容器（cardBackground + 12pt 圆角 + cardBorder 描边，`scrollContentBackground(.hidden)` 去掉 List 默认底色），行内水平 padding 12pt——2026-08-29 修复：此前 List 通栏裸排与卡片语言脱节。
- 列表卡顶部带**列对齐表头**（固定不滚动，surfaceOverlay 底）：圆点占位 / 时间（155pt）/ 级别（50pt）/ 主机（140pt）/ 内容（弹性），列宽由共享常量 `LogColumn` 定义，表头与行逐列对齐（`logs.header.*` key）——2026-08-29 补齐：原始设计就没有表头，非重构丢失。
- **表格化行布局**：LogRow 单行五列（圆点/时间/级别/主机/内容），主机与内容不再上下堆叠；斑马纹区分行（偶数行 surfaceOverlay 0.45）；内容超长单行截断 + `.help` 悬停看全文 + 可选中；列表用 ScrollView+LazyVStack 实现（List 的系统 row inset 会破坏表头对齐）。
- List 倒序行：6pt 级别色圆点 + 时间戳（130pt）+ 级别标签（50pt）+ 主机名 + 消息（可选中）。LogManager 上限 1000 条。

### 6.10 设置页 SettingsTab（MainView 内）
- **系统卡**：语言分段、外观分段（light/system/dark 顺序）、开机自启 Toggle（SMAppService）、版本行（"v2.5.0 (127)"）、Tailscale 总闸 Toggle（下方实时状态说明行：CLI 完整路径 / 控制面已配置 / 未检测到 / 已关闭；**每次打开设置页且总闸开启时自动重测 CLI**，装完 Tailscale 无需重启）。开启后追加 OAuth 卡：client id / secret SecureField（保存后 secret 立即清空不回显）、同步间隔 30s/60s/5m/15m、管理模式 Toggle、保存验证/清除、已配置绿色徽章（未配置时引导默认展开、配置后收起）、「打开 Tailscale 控制台」外链 + 复制链接按钮 + 橙色警告条、6 步引导折叠区（验证结果显示可见设备数/红色错误）。
- **显示卡（状态栏 & 小组件）**：显示模式 Picker（average/worst/best/first + 说明文字）；4 个菜单栏元素 Toggle（图标/延迟/标签/网速，**互斥约束：至少保留一项、至多三项**），各带宽度 Stepper（−/+ 圆钮 + 等宽数字）；字号 6–18 步 1；字重分段；配色模式；网速单位（auto/KB/MB）；Widget 模式（auto/specific + 主机 Picker）。
- **监控卡**：Ping 间隔分段（3/5/10/15/30s，改后热重启探测）、日志级别。
- **通知卡**：总 Toggle → 类型分段（系统 / Bark）→ Bark URL TextField。

---

## 7. 主机详情覆盖层 HostDetailView

- Header（**卡片式**，与主页面头同语言）：返回按钮 + 可达圆点 + 主机名/地址 + 实时延迟徽章（latencyColor 0.1 背景）；检测中显示 ProgressView + "检测中…"。内容区同用 `fitsTwoColumns` 做 2 列/单列响应式（宽度实测驱动）。
- 内容行序：〔状态卡 + 延迟统计卡〕→ 延迟图表卡（全宽）→〔包统计卡 + 流量卡〕→ 操作按钮行 →〔显示规则卡 + 服务快捷卡〕→〔记录卡 + 日志卡〕。
- **状态卡**：Online/Offline + Uptime（≥1h `dh dmm` 否则 `dm dss`）+ 诊断信息行（探测模式 / 质量分+P95+Loss / 最近结果 / 路径快照 / 最近检测时间 / 命令）。
- **延迟统计卡**：Current（latencyColor）/ Min（绿）/ Max（红）/ Avg（蓝）+ Jitter（橙，= max−min）。
- **延迟图表卡**：时间窗 1m/5m/1h Picker；LineMark **横向三色渐变**（蓝→青→绿，shadow 蓝 0.35）+ AreaMark；丢包样本 = 红色垂直虚线 RuleMark + 4pt 红点；平均线 = 橙虚线 + 顶部 ms 标注；Y 轴自适应上限 `max(10, min(max, max(200, avg×5)) × 1.1)`，虚线网格。
- **包统计卡**：Total/Success/Failed + 成功率进度条（动画 easeInOut，阈值 good 95 / warning 80）。
- **流量卡**：Sent（绿）/Received（蓝）/Total（ByteCountFormatter）。
- **显示规则卡**：每条规则行（激活圆点 + 名称 + 条件 + 启用 Capsule 徽章）。
- **服务快捷卡**："+" 添加 → ShortcutEditorSheet；网格项右键编辑/删除。
- **记录卡**（硬编码英文）：HostRecord 标题/日期/内容，RecordEditorSheet（400×350）。
- **日志卡**：本主机最近 50 条 + 导出按钮（Reveal in Finder）。
- 操作行：导出当前统计（CSV，NSSavePanel `ping_stats_*.csv`）/ 重置当前统计（红）。

---

## 8. 编辑表单汇总

| Sheet | 尺寸 | 字段 |
|---|---|---|
| HostEditorSheet | 420×500 | 基础：名称/地址/探测方式分段（ICMP/TCP）+ TCP 端口 Stepper（1–65535，默认 443）/自定义命令（支持 `$address` 与 `${address}` 占位；**不含占位符且地址未内联时自动在命令末尾追加地址**，执行间隔跟随全局 Ping）；规则：RuleEditorRow（启用 Toggle + 删除钮 + 条件分段 less/greater + 阈值 + 标签文本）+ AddRuleSheet（350pt，标签空则生成 `"< 100ms"`）；取消/保存（名称或地址空禁用） |
| ShortcutEditorSheet | 420 | 见 §6.7 |
| PresetEditorSheet | 宽 380 | 名称/地址/命令 |
| RecordEditorSheet | 400×350 | 标题/内容 TextEditor；支持编辑已有记录（回填并保留 createdAt）、右上 X 关闭、标题空禁用保存 |
| TagEditorSheet（Tailscale） | 内容区宽 360（sheet 本体无固定尺寸） | 标签 CSV 输入 + 橙色警告说明，自动补 `tag:` |

---

## 9. 桌面小组件（WidgetKit，StaticConfiguration，5s 刷新）

| 尺寸 | 元素 |
|---|---|
| Small | 标题（仅 auto 模式显示）+ 44px 状态色大圆环图标 + 大号延迟（20 rounded bold，numericText transition）+ 主机名 + 版本号 |
| Medium | 标题行 + 前 3 主机行（6pt 圆点 + 名称 + 右对齐等宽延迟 / "Stopped"） |
| Large | 头部（server.rack 紫 + 时间）+ 前 6 主机行（状态 Capsule + wifi 图标 + 延迟 / STOPPED 徽标，ultraThinMaterial） |

- 状态色：停止 gray / 超时 red / <50 green / <100 yellow / 其他 orange。
- **三级数据回退**：App Group `group.com.pingmonitor.shared`（key `widget_data_json`）→ Widget 容器 Documents `widget_data.json` → `~/Library/Application Support/PingMonitor/widget_data.json`；全失败显示调试视图。App 侧同步节流 5s，auto 模式取前 5 台（离线>高延迟排序）。

---

## 10. 数据模型与持久化

### HostConfig
`id UUID` / name / address / command（`$address`/`${address}` 占位，未含占位符时自动追加地址）/ lastLatency / isReachable / isChecking / displayRules（默认 `less:50→Direct`、`greater:100→Relay`）/ serviceShortcuts / isTailscaleNode / tailscaleHostname / isPaused / records / probeMode（icmp 默认）/ tcpPort 443。自定义 decode 全字段容错。首次启动无存档时自动创建默认主机 "Google DNS (8.8.8.8)"。

### 其他
- `DisplayRule`：condition("less"/"greater") + threshold + label + enabled。
- `HostPreset`：内置 4 条默认模板。`ServiceShortcut`：9 字段 + `sshCommand` 计算属性（expect 包裹）。`HostRecord`、`HostStats`（4096 上限样本、latencyHistory 60 点、+64B/包流量估算、packetLossRate/successRate 计算属性）。
- **持久化**：`~/Library/Application Support/PingMonitor/` 下 hosts.json / presets.json / stats.json / settings.json（原子写）+ UserDefaults 二次备份（settings.json 的 23 个 key + 旧持久化 key `hosts`/`presets`/`hostStats`/`isRunning`，共 27 个）+ 首启迁移逻辑；语言偏好存 App Group `@AppStorage("appLanguage")`（唯一不在 `pm.*` 命名空间的设置项）；Tailscale OAuth 凭据仅存 Keychain。

---

## 11. 核心引擎

### 11.1 探测（PingMonitorViewModel）
- ICMP：`/bin/sh -c "exec ping -i <interval> <addr>"`（exec 防孤儿）；Tailscale 节点升级为 `tailscale ping --c=1` + `while kill -0 <appPID>` 看门狗循环。升级为 Tailscale 探测的判定：`isTailscaleNode` 标记、地址落在 **100.64.0.0/10 CGNAT 段**、或命中节点 primaryRoutes 子网路由——节点表首次加载 / 总闸翻转时热重启相关探测。
- TCP：NWConnection 主队列 DispatchSourceTimer（间隔 max(pingInterval,1)s，超时 min(interval,3)s）。
- 批处理 1.0s 合并 UI 刷新；失败分类 9 类（timeout/dnsFailure/noRoute/…正则解析）；连续失败 ≥3 判离线；样本保留 2h。改 Ping 间隔只重启"跟随设置"的主机，**自定义命令主机不被打断**（`applyPingIntervalChange()`）。

### 11.2 质量评分引擎
窗口 1m(bucket 5s)/5m(15s)/1h(60s)。**六维度与权重**：
| 维度 | 权重 | 主要规则 |
|---|---|---|
| latency | 0.30 | p95 分档 100/85/65/40/15；jitter>25 −20；spikeRate>15% −20 |
| stability | 0.30 | 可用率分档；丢包>5% −35；连败≥3 封顶 45 |
| path | 0.15 | direct 100 / relay 60 / unknown 75；路径抖动 ≥2 次 −15；noRoute/networkUnreachable 失败 −20 |
| bandwidth | 0.10 | 隧道占比>0.7 降分；>50MB/s →70 |
| resolution | 0.05 | DNS 失败率分档 100/65/35 |
| overlay | 0.10 | Tailscale direct 92 / relay 60；普通 relay 65 |

封顶：连败≥3 →≤49；可用率<90 →≤59；**非纯 IP 主机**（地址非 `^[0-9\.:]+$`）出现 DNS 失败 →≤45。总分 = round(加权) 0–100。
**事件**（保留 120 条）：恢复 info / 探测失败 critical（DNS warning）/ 路径切换 info / relay 化 warning / 每 5s 降分检测：跌破 40 → critical、单窗口降 ≥20 → warning。全局快照 = 加权均值×0.8 + 最差 20% 均值×0.2。

### 11.3 其他管理器
- **KeepAliveManager**（5s）：规则 {interface 前缀、strategy passive/intensive/adaptive、idleThreshold 300s}，空闲进入 keep-alive（0.5s 间隔）、有流量退出，发通知让 ViewModel 重启 Tailscale 节点探测。
- **PrivilegedManager**：osascript 提权常驻 root shell + FIFO（`NSTemporaryDirectory()/pingmonitor.<UUID>/priv.fifo`，目录 0700、umask 077 防 TOCTOU——旧实现 `/tmp/pingmonitor_priv_fifo` 已废弃，CLAUDE.md 描述过时）；全库**唯一调用点是网速页 killProcess 的提权 `kill -9`**，Traceroute/MTR 不经提权。
- **FolderMonitor**：DispatchSource 监听目录，500ms 防抖。
- **通知**：启动即请求系统通知授权（.alert/.sound）；延迟 >100ms → "⚠️ Poor"；连续失败 ≥3 → "❌ Failed"；系统 UNUserNotificationCenter 或 Bark GET 推送（URL 路径百分号编码）。

---

## 12. 交互与动画总表

| 类型 | 清单 |
|---|---|
| 点击 | 侧边栏路由、启停、卡片开详情、服务 chip、Tailnet 胶囊跳页、折叠带、双 Tab、过滤徽章、分组折叠、Quick Target、连接行展开 |
| 拖拽 | 侧边栏宽度 Resizer（resizeLeftRight 光标）、主机卡片 onDrag/onDrop 排序 |
| 右键 | 主机卡（开始停止/编辑/删除）、管理卡、模板卡、服务 chip（打开/复制）、服务项、记录行、Tailscale 管理菜单 |
| Sheet | 主机编辑、模板编辑、快捷方式编辑、记录编辑、标签编辑、添加规则 |
| 动画 | header 呼吸灯 1.5s repeatForever；卡片 hover spring 1.01 + 彩色阴影；Tab matchedGeometryEffect spring；服务带 spring 0.28/0.82；详情覆盖层 move(trailing)+blur；行 hover easeInOut 0.15s（Traceroute 页，主机管理页为 0.2s）；Toast move+opacity 2s；进度条 easeInOut(value:)；地图相机 withAnimation |
| 快捷键 | 表单 Cancel（Esc）/ Save（Return，defaultAction）；无其他自定义快捷键 |

---

## 13. 官网（docs/，GitHub Pages）

### 结构（index.html）
固定导航（brand 蓝点 pulse + Features/Changelog/GitHub + 中/EN 切换）→ Hero（canvas 波形装饰 + GitHub latest release 版本徽章 + 双词渐变 H1 "Network. Nuanced." / 中文「毫秒。洞见。」+ 下载/GitHub CTA + **纯 CSS 仿应用窗口 mockup**：侧边栏 5 项、5 行主机、质量环形 SVG 分数 90）→ Stats Bar（滚动计数）→ Preview Strip 三面板（Monitor 实时跳动延迟 / Quality 六维条 / Traceroute SVG 动画 pulse 沿路径）→ Bento Grid 5 卡（Pulse/Flow/Path/Widget/Quick Actions，hover 跟随鼠标光斑）→ Tech Specs 4 列 → Footer。changelog.html：类别过滤按钮（All/Added/Updated/Fixed）+ 垂直 timeline（可折叠卡片，四色标签 added 蓝/updated 紫/fixed 绿/changed 橙）。

### 设计体系（style.css）
- 变量：`--bg #000`、`--fg #fff`、`--accent #3b82f6`（与 App accentBlue 同系）、changelog 四色标签；字体 Inter + JetBrains Mono（所有数字）。
- 全局特效：SVG 噪点纹理（0.04）+ 鼠标跟随径向光晕（CSS 变量驱动）+ smooth scroll。
- 动画 9 组 keyframes（fadeInUp/pulse/shimmer/float mockup 悬浮等）+ reveal stagger（cubic-bezier(0.16,1,0.3,1)）。
- 断点：1000 / 768（隐藏 mockup）/ 600 / 480。

### script.js 交互（13 个初始化器）
i18n 双字典（**每语言 63 key**，localStorage `pm-lang`）、GitHub release fetch（版本徽章 + .dmg 直链替换）、canvas 双正弦 sparkline（60 采样、~20fps + 离屏暂停）、延迟数字 1400ms 抖动、滚动计数 1200ms、维度条入场动画、reveal IntersectionObserver stagger、navbar scrolled、鼠标光斑追踪（**三处**：全局背景光晕 + bento 卡局部 + preview 面板）、changelog 折叠/过滤（过滤按钮仅 All/Added/Updated/Fixed **4 个，无 Changed**）、smooth scroll、initParallax（已废弃空函数）。

---

## 14. 文档与实现不一致清单（已逐条代码验证）

| # | 文档说法 | 代码事实 |
|---|---|---|
| 1 | README：`{host}` 占位符 | 实际占位符是 `$address`（Localization.swift:137）；规则标签为纯文本 |
| 2 | README：3D 饼图/环形图 | Dashboard 维度为水平进度条；无任何环形图组件（全库 grep 无 Donut/环形） |
| 3 | README/CLAUDE.md：Tailscale 支持 Exit Node 切换 | `TailscaleManager` 仅读取 `ExitNode/ExitNodeOption` 展示图标，无任何切换写入命令 |
| 4 | README/CLAUDE.md：PrivilegedManager 消除 Traceroute/MTR 重复授权 | `PrivilegedManager.shared` 全库唯一调用点是 `NetworkSpeedManager.killProcess` 的提权 `kill -9`；Traceroute 实际用 `/usr/bin/script -q /dev/null` 包装骗 TTY 运行 ICMP traceroute，不经提权 |
| 5 | CLAUDE.md：FolderMonitor 用于监听配置目录 | ~~死代码~~ **2026-08-29 重构已删除该文件** |
| 6 | README：Keep-Alive 三档策略 | 引擎支持 passive/intensive/adaptive，但无任何配置 UI；`rules` 启动时硬编码注入 1 条 "Tailscale Keep-Alive"（adaptive, utun） |
| 7 | README：网速字号与模块显隐可自由定制 | 该定制仅针对状态栏 4 段（设置页）；NetworkSpeedTab 页面本身无字号/显隐设置 |
| 8 | README：Jitter（标准差） | 详情页 Jitter = max − min（HostDetailView.swift:415-417）；质量引擎 jitter 为**相邻延迟差绝对值的均值**（PingMonitorApp.swift:1217-1221）——两处均非标准差 |
| 9 | README：环境要求 Xcode 16+ | project.yml `xcodeVersion: "17.0"`，CI/Release 实际跑 Xcode 26 / macos-26 runner |
| 10 | — | ~~Widget Small 版本号硬编码 `"v2.0.51"`~~ **重构已修复**：改为读取扩展自身 Info.plist 的 CFBundleShortVersionString |
| 11 | — | ~~`package_dmg.sh` 硬编码 `/Users/framed/...` 路径~~ **重构已修复**：默认取仓库内 build/ 产物，支持 `APP_PATH` 覆盖 |
| 12 | — | ~~硬编码英文未本地化~~ **重构已修复**：新增 30 个 i18n key（traceroute.location、host.records.*、netspeed.tunnel_*、tailscale.cmd_*/error.*/ping.*、common.switch_language/confirm），全部 UI 文案（含 TailscaleManager 错误与诊断结果）走 `t()` |
| 13 | — | 快捷键仅 5 处 `.cancelAction/.defaultAction`（ServicesTab ×2、HostDetailView ×2、TailscaleTab ×1），无其他自定义快捷键 |
| 14 | README/CHANGELOG：网速单元测试 "34 个用例" | 实际 **35** 个 `func test` 方法（README.md:111 与 CHANGELOG v2.1.2-R14 均写 34） |
| 15 | — | ~~killProcess 提权 `kill -9` 后不校验结果~~ **重构已修复**：延迟 1s 后用信号 0 复核（ESRCH=已退出），completion 按真实结果回调 |
| 16 | — | ~~破坏性操作缺确认~~ **重构已修复**：流量历史"重置"与 HostDetail"重置统计"均加二次确认 Alert（不可撤销提示） |

---

## 15. 工程基础设施

### 15.1 XcodeGen（project.yml）
| Target | 类型 | Bundle ID | 备注 |
|---|---|---|---|
| PingMonitor | application | `com.pingmonitor.app` | 依赖并嵌入 PingMonitorWidget；Release 构建前跑 `bump_build.sh`（preBuildScript） |
| PingMonitorWidget | app-extension | `com.pingmonitor.app.widget` | 复用主 target 的 `WidgetDataManager.swift` 源文件；`SKIP_INSTALL: NO`；WidgetBackground/AccentColor 资产 |
| PingMonitorTests | unit-test | `com.pingmonitor.tests` | 宿主 PingMonitor |

- 版本基线：MARKETING_VERSION 2.5.0 / CURRENT_PROJECT_VERSION 127（三处同步：两个 Info.plist + project.yml）。
- **App Group 被注释**（`group.com.pingmonitor.shared`）——因无 DEVELOPMENT_TEAM 签发不了 App Group，这正是 Widget 三级回退存在的根因；Widget 显式 `app-sandbox: false` 使跨容器直写文件（第 2 级回退）可行。
- 主 target sources 同时列目录与单文件（冗余但无害）。

### 15.2 版本管理（scripts/bump_build.sh）
- 被 `build.sh` 与 Release preBuildScript 双入口调用；`SKIP_VERSION_BUMP=1` 空转（build.sh 二次调 xcodebuild 时防重复递增）。
- 三档：无参 = 仅 +1 build 号；`--feature` = minor+1（`2.1.2-R12 → 2.2.0`，剥离 -Rn 后缀）；`--bug` = -Rn 递增（`-R12 → -R13`，兼容小写 r）。
- 顺序同步三个文件（无原子性保障，中途失败可能不一致）：主 Info.plist、Widget Info.plist（PlistBuddy）、project.yml 两行版本号（sed）。

### 15.3 构建与打包
- **build.sh**（一键 DMG，CI Release 同用）：bump → PlistBuddy 读版本 → `xcodegen generate` → 清 DerivedData → Release 构建（ad-hoc 签名 `-`）→ **重签名顺序敏感**：先签 widget.appex（保留自身 entitlements）再签主 app，反序会失效 → hdiutil UDZO 打包（卷名"拖动到 Applications 安装"，内容含 app + README + Applications 符号链接）→ 输出 `~/Desktop/PingMonitor-v{ver}.dmg`。
- **package_dmg.sh**：本地 Debug 产物直接打 DMG（无版本递增；路径硬编码，见 §14-11）。

### 15.4 CI / Release（GitHub Actions）
- **ci.yml**：push/PR → main；concurrency 取消旧跑；`SKIP_VERSION_BUMP=1`；macos-26 + 最新 Xcode 26 → brew 装 xcodegen → `xcodegen generate` → Debug ad-hoc 构建 → `xcodebuild test`。
- **release.yml**：push tag `v*` → checkout 全历史 → build.sh 产 DMG → `softprops/action-gh-release@v2` 发布（自动生成 release notes，unmatched files 报错）。

---

## 16. 测试覆盖（PingMonitorTests）

### QualityEngineTests（2 用例，轻量）
- `QualityDimensionScores.average` 等权平均（验证的是派生属性，不触及硬编码权重的总分公式——总分公式目前无直接单测）。
- 空状态 `GlobalQualitySnapshot` 字段语义（score 0、P95 nil）。

### NetworkSpeedManagerTests（35 用例，回归钉死型）
用 macOS 26 真实 `netstat -bni` / `nettop -P -L 1` 输出样本"描述当前行为"，失败即提示"是修复还是回归"：
- **parseNetstatOutput**（8）：全行型采集、lo0 无 Address 列负偏移、en0 带 MAC 标准偏移、utun 无 MAC、`*` 停用后缀 id/name 分离（Bug #2：up/down 切换保持 baseline key 稳定）、非 `<Link#>` 行跳过、空/畸形输入。
- **InterfaceRole 分类**（5）：en* physical / utun·ipsec tunnel / awdl·gif·stf·bridge·ap virtual / lo0 loopback / `*` 后缀前缀匹配容错。
- **parseNettopOutput**（3）：按 `name.PID` 提取、同 PID 重复行求和、单调累加器契约（文档化 nettop -L 1 的 ~1s 采样偏移、短命 PID 丢失、陈旧 baseline 三个已知偏差）。
- **aggregateTotals**（6，Bug #1）：纯 VPN 报承载体速率、链式封装隧道不超物理链路（21.3 vs 5.7 MB/s 案例）、split-tunnel 不重复计数、默认路由口优先于最忙物理口、指定接口选择、bytes 恒用物理口单调累计（隧道 bytes 取 max 单列）。
- **长间隔 rebase**（3，Bug #3）：5× 阈值边界（4.99x 接受 / 5.01x rebase / 常量钉死 5.0）。
- **速率 delta**（3）：正常、counter 回退归 0、睡眠长间隔均值语义文档化（当前行为，标注"理想应丢弃"）。
- **format 边界**（2）：B/KB/MB/GB 1024 边界值锁定。
- **splitAddressPort / parseLsof**（5）：IPv4、IPv6 方括号、通配 `*:53`、TCP ESTABLISHED 全字段、LISTEN。

---

## 17. 权限、安全与系统配置

| 配置 | 值 / 含义 |
|---|---|
| `LSUIElement` | true —— 纯菜单栏应用，无 Dock 图标（由 StatusBarController 动态 .regular/.accessory 切换） |
| 应用分类 | `public.app-category.utilities`；开发区域 zh_CN |
| **ATS 豁免** | `ip-api.com` 允许明文 HTTP（GeoIP 查询走 http，含子域名）——全 app 唯一非 HTTPS 出网 |
| `NSAppleEventsUsageDescription` | "控制 Terminal 打开 SSH 连接"（.command 方案实际绕开了它，描述保留） |
| 主 app 沙盒 | 无沙盒 entitlement（明文 JSON + 跨容器写依赖此） |
| Widget 沙盒 | 显式 `app-sandbox: false`（覆盖 WidgetKit 默认，支撑三级回退第 2 级） |
| Keychain | 仅 Tailscale OAuth 凭据（kSecClassGenericPassword，AfterFirstUnlock）；界面永不回显 secret |
| 特权 | PrivilegedManager 单次 osascript 授权常驻 root shell + FIFO（`NSTemporaryDirectory()/pingmonitor.<UUID>/priv.fifo`，目录 0700、umask 077 防 TOCTOU）；新 root 需求必须复用该会话 |
| 进程卫生 | ICMP `exec` 防孤儿；Tailscale 循环 `while kill -0 <appPID>` 看门狗防 launchd 收养泄漏（v2.4.0 修复 15 个残留进程案例） |
| 并发纪律 | Swift 6 严格并发：`LockedArray`/`Box` 做 @unchecked Sendable 跨 actor 交接；macOS 26 Tahoe 的 DispatchSource executor-isolation 陷阱规避模式已写入 CLAUDE.md |

### CHANGELOG 设计决策索引（v2.2 → v2.5.0，写设计文档时的语义来源）
- v2.5.0：Tailscale 总闸成为真开关（关闭 = 零 CLI 探测、零控制面请求、探测退回普通 ping、切换即时生效）。
- v2.4.1：adaptive GridItem 排出 6 列填 2 卡的 bug → 统一为宽度切换 Grid/GridRow（`fitsTwoColumns` 抽取共用）。
- v2.4.0：设计令牌大统一（107 处圆角字面量替换、118 行硬编码色迁移、`Theme.Status` 语义色取代 20 处重复函数、PingFang 无 Bold 降级 Semibold）；Tailnet 控制面只读同步 + 管理模式写操作；接口族分组；探测进程泄漏/间隔不生效/侧边栏压缩/状态色不一致等修复。
- v2.2.x：状态栏 NSTextAttachment 分段渲染架构（解决宽度抖动）、质量引擎精化（spikeRate、detectScoreDegradation、P99）。


---

## 18. 重构记录（2026-08-29，基于本文档执行）

**目标**：以文档为基准重构所有页面——行为保持不变，消除文档标记的问题，落地"一页一文件"结构。

### 结构重组
- `MainView.swift` 3398 → **363 行**，只保留主窗口框架（SidebarItem 路由、Header、TailnetStatusPill、SidebarResizer、WindowMinSizeSetter）。
- 新增页面文件（纯代码搬移，零行为变更）：`MonitorTab.swift`（414）、`HostManagementTab.swift`（565）、`SettingsTab.swift`（785）、`HostEditorSheet.swift`（213）、`LogsTab.swift`（137）。
- 删除零引用死代码 **939 行**：旧 `StatisticsTab`/`StatisticsContentView`/`AggregatedStats`/Stats 系列卡片（881 行，含 13 项原始指标卡实现）、`MiniSparkline`（58 行）、`FolderMonitor.swift`（整文件）。

### 文档问题修复（§14）
- **本地化**：新增 30 个 i18n key（en/zh 双份），替换全部硬编码英文——Traceroute "Location" 表头、HostDetail Records 卡全套文案、NetworkSpeedTab 隧道行与说明、TailscaleTab Quick Commands/Global IP/Exit Node tooltip、语言钮 tooltip；TailscaleManager 的 CLI 错误与路径诊断结果文案改为 MainActor 预取模板 → detached 闭包内格式化（Swift 6 隔离安全）。
- **行为修正**：路径诊断的连接类型改由响应字段直接判定，不再对展示文案做 `contains("P2P")` 子串匹配（本地化后该逻辑本会失效）；killProcess 提权 `kill -9` 后用信号 0 复核真实结果；流量重置与统计重置增加不可撤销确认 Alert。
- **杂项**：Widget 版本号从硬编码 `v2.0.51` 改读 Info.plist；`package_dmg.sh` 去除 `/Users/framed` 硬编码（支持 `APP_PATH` 覆盖）。

### 验证
- `xcodegen generate` + Xcode 27 `xcodebuild build`：**BUILD SUCCEEDED**。
- 单元测试：**37/37 通过**（NetworkSpeedManagerTests 35 + QualityEngineTests 2）。
- 备份：`~/PingMonitor/Ping-Monitor-src-backup-20260829.tar.gz`；未提交 git（工作区可用 `git diff` 审阅）。

### 2026-08-29 追加：顶部布局全量卡片化
- 用户反馈不喜欢通栏式页面顶栏 → **所有页面顶部改用卡片**，新增统一样式 `View.cardBar(topInset:bottomInset:)`（Components.swift，与 ModernCard 同视觉语言：cardBackground + 12pt 圆角 + 1pt cardBorder）。
- 改造点：①主窗口共享 Header（MainView，去材质层与渐变，语言圆钮改 surfaceOverlay 底）；②监控页工具栏；③路由追踪工具栏；④测速页分段 Tab；⑤主机管理分段控件（滑轨改 surfaceOverlay）与已保存/模板两个子页工具栏；⑥日志页工具栏；⑦主机详情覆盖层 Header。
- 不再存在页面级 ultraThinMaterial（2026-08-29 二次修复：主机管理/模板两张卡片原用 `.fill(.ultraThinMaterial)` + `textTertiary 0.08` 描边，浅色模式下与背景几乎无对比，已统一为 cardBackground + cardBorder 令牌，hover 描边加强至 0.45）；Dashboard/服务/Tailscale/设置本就是纯卡片流，未动。
- 验证：BUILD SUCCEEDED，37/37 测试通过。

### 2026-08-29 追加：统一分段切换控件
- 用户反馈网速页与主机管理页的两个分段 Tab 视觉不一致 → 新增 `CardSegmentedControl`（Components.swift），两页共用。
- 差异根因：网速页原为固定 200pt 宽、选中项自绘蓝底无滑轨、无滑动动画的自研实现；主机管理页为全宽等分 + surfaceOverlay 滑轨 + matchedGeometryEffect 滑动高亮。统一后均为：等宽分段、surfaceOverlay 滑轨、accentBlue 滑动高亮、body 字号、滑动 spring(0.3/0.7)。

### 2026-08-29 追加：设计令牌全量合规审计
对 15 个视图文件扫描五类违规（硬编码系统字号 / 绕过 Theme 的语义字体 / 直接色 / 数字圆角 / hex 泄漏），结果与处置：
- **合规项**：无 `.font(.system(size:))`、无数字圆角、无 hex 泄漏（仅 Theme.swift 持有 hex 定义）。
- **修正 8 处语义字体**（`.headline`→`Fonts.ui(headline, .semibold)`，`.caption`→`Fonts.ui(caption)`，图标→`Fonts.icon(caption)`）：HostEditorSheet ×3、MonitorTab 工具栏标题、HostManagementTab ×3、SettingsTab 状态栏说明。
- **修正 3 处直接色**：LogsTab 时间戳 `.foregroundStyle(.tertiary)`→`textTertiary`；ServicesTab 命令预览黑底 → 新令牌 `Theme.Colors.codeBackground`（黑 30%）；TailscaleTab 结果胶囊黑底 → 新令牌 `Theme.Colors.chipOverlay`（黑 10%）。
- **豁免例外（功能用途，非样式）**：MonitorTab 0.1% 透明点击遮罩；PingMonitorApp 状态栏 NSColor.white/black（用户显式选择"浅色/深色"文字颜色）；Widget 的 `.system(size:)`（Widget target 不含 Theme.swift，像素规格由 §9 单独定义）。
- **容器间距**：各页滚动列 padding=cardPadding(16)、卡片间距=gridSpacing(16)（本日早前已统一）；组件内 ≤14pt 的微间距属组件规格（design.md 各节已标注），不设全局令牌。
