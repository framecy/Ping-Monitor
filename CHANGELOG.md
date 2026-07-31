# Changelog

所有显著的更改将记录在此文件中。格式基于 [Keep a Changelog](https://keepachangelog.com) 规范，版本遵循语义化版本。

---

## [v2.4.0] - 2026-07-31 · 设计令牌统一、Tailnet 全局监管与探测准确性修复

### Added
- **Tailnet 全局监管**：新增基于 Tailscale OAuth client 的控制面只读同步（`GET /api/v2/tailnet/-/devices`），覆盖整个 tailnet 的设备清单、在线状态、标签、密钥有效期与可用更新，不依赖本机能否连通对端。PingMonitor 不注册为 tailnet 节点、不承载 tailnet 流量，探测复用本机已运行的 Tailscale app。
- **管理模式**：默认关闭；开启后设备行提供控制面写操作 —— 设备授权/取消授权、子网与 exit-node 路由审批、密钥过期开关、标签编辑、从 tailnet 删除。取消授权与删除强制二次确认，写入后立即回拉清单，不做乐观更新。
- **凭据存储**：OAuth client id/secret 存入系统钥匙串（`kSecAttrAccessibleAfterFirstUnlock`），不写入 `ConfigManager` 的明文 JSON；界面永不回显 secret。设置页内置六步获取引导与管理后台跳转。
- **网络接口分组**：接口列表按族（Wi-Fi / 以太网 / VPN·隧道 / 网桥·虚拟 / 隔空投送 / 系统内部 / 回环）合并展示，可展开查看成员，承载默认路由的组带「默认出口」徽标。

### Fixed
- **网速统计虚高**：总速率此前对所有 `physical` 接口求和，实际把 `anpi0/1/2`（Apple 网络协处理器管理口）与 `en1`–`en8`（雷雳/USB/桥接成员）共 12 个接口一并计入。现改为通过 `route -n get default` 识别真实出口并只统计该接口，取不到时退化为速率最高的物理口；`anpi*`/`vmenet*`/`vnic*` 重新归类为系统内部接口，永不计入用户流量。
- **探测进程泄漏**：Tailscale 探测以 `sh -c "while true; …; sleep N; done"` 运行且未 `exec`，app 被强杀或崩溃后循环被 launchd 收养，按旧间隔持续探测并与新实例叠加（开发机上累积 15 个）。循环条件改为 `while kill -0 <appPID>`，随宿主进程退出。
- **Ping 间隔修改不生效**：间隔在 spawn 时写入命令行（`ping -i N` / `sleep N`），修改设置无法影响已运行进程。新增 `applyPingIntervalChange()`，仅重启未配置自定义命令的主机；自定义命令自带节奏，不受该设置影响。
- **侧边栏被压缩**：detail 区不可压缩内容会连带压扁固定宽度的侧边栏。侧边栏改为高布局优先级 + `fixedSize`，detail 成为唯一可压缩列，窗口最小宽度随侧边栏宽度推导。8pt 拖拽热区改为浮于接缝之上，不再占据一列而露出色差缝隙。
- **主机健康矩阵布局**：`alignment: .top` 在水平方向等同居中，加之列宽按测量值的百分比算死（测量失败时停留在默认 480pt），导致宽卡片中渲染窄表并留下大片空白。列宽改由 `Grid` 按内容自适应，测量值仅用于决定列数。
- **状态色阈值不一致**：同一主机延迟在卡片按 100/300ms 着色、在列表按 80/180ms 着色，现统一由 `Theme.Status` 提供。

### Changed
- **设计令牌统一**：新增语义状态色（`Theme.Status`）取代 20 处重复的颜色函数；圆角标度替换 107 处字面量；118 行硬编码系统色迁移至令牌，并引入明暗自适应的中性叠加色，修复浅色模式下白底白线的描边。
- **字体系统**：中文 PingFang SC、英文 SF Pro Text，18 种字号收敛为 10 档。SF Symbols 保留系统字体以免破坏符号度量；PingFang 无 Bold 字重，粗体统一降级为 Semibold 而非由系统合成。
- **表格斑马纹**：主机健康矩阵与接口列表改用半透明色块区分行，替代分隔线。

---

## [v2.3.0] - 2026-07-14 · 自适应布局与 Tailscale 功能开关

### Added
- **可调侧边栏**：侧边栏宽度支持在 180–360 pt 范围内拖动调整，并通过 `@AppStorage` 跨启动保留。
- **Tailscale 功能开关**：设置页新增 Tailscale 总开关；仅在用户启用且本机 Tailscale CLI 可用时显示侧边栏和顶部快捷入口，并在关闭后自动回退到监控页。
- **窗口最小尺寸约束**：主窗口最小尺寸固定为 900 × 650，避免标题栏拖拽缩小时破坏内容布局。

### Changed
- **仪表盘响应式布局**：质量卡片根据可用宽度在双列与单列之间切换；主机健康和流量卡片改为全宽自然高度，减少卡片重叠与拉伸。
- **主机健康表自适应**：根据宽度自动使用六列、三列或纵向紧凑布局，在窄窗口下仍能保持关键指标可读。
- **详情与管理页面自适应**：主机详情、统计指标、主机管理和预设管理统一采用自适应网格，优化不同窗口尺寸下的展示。
- **Traceroute 表格缩放**：逐跳表格的 IP、延迟、平均值和丢包列随容器宽度等比调整，降低横向溢出。
- **网速页窄屏优化**：网络接口摘要区域的最小宽度由 150 pt 调整为 110 pt。

---

## [v2.2.2] - 2026-07-13 · macOS 26 (Tahoe) 兼容与菜单栏窗口修复

### Fixed
- **macOS 26/Tahoe 启动崩溃**：`startTCPProbe` 的 `DispatchSource` 定时器事件回调捕获了 `@MainActor` 隔离的 `self` 并在后台队列上执行；Swift 6 的执行器隔离前导代码在更严格的 Tahoe 运行时上触发 `_swift_task_checkIsolatedSwift → _dispatch_assert_queue_fail → SIGTRAP`，首个 TCP 探针 tick（`deadline: .now()`）一触发即崩。改为在主队列上驱动定时器，并以纯回调式（无 `Task.detached`/`await`）的 `measureTCPConnectLatency` 取代 `async` 版本；实际 TCP I/O 仍在 `NWConnection` 私有队列上运行，仅将结果回调写回 `pendingUpdatesBuffer`（`LockedArray` 自带锁，与 ICMP 路径 `parsePingLine` 同构的 off-actor 模式）。
- **关闭窗口后无法从菜单栏重新打开**：`isReleasedWhenClosed = false` 令窗口被红按钮关闭后停留在「已关闭但未销毁」中间态，`isVisible` 语义破坏 `toggleWindow`；macOS 26 的 agent app 下 `makeKeyAndOrderFront` + `ignoringOtherApps:` 已无法可靠把窗口带回前台。新增 `windowShouldClose(_:)` 拦截红按钮关闭，改为 `orderOut(nil)` + `.accessory` 策略并返回 `false`，使窗口仅隐藏、与 toggle 保持对称；`showWindow()` 改用 `NSApp.activate()`（新激活语义）+ `orderFrontRegardless()` 兜底强制置前。

---

## [v2.2.1] - 2026-06-10 · 状态栏自定义宽度

### Added
- 状态栏 4 大元素独立自定义宽度设置：支持在「设置」界面中针对**显示图标**、**显示延迟数值**、**显示规则标签**和**显示网速**分别设置自定义宽度。
- 新增 `Combine` 属性变化监听订阅，用户调节宽度与字体大小时状态栏即可瞬间刷新，解决界面显示与状态栏的耦合更新延迟问题。
- 图标、延迟、标签、网速均重构为固定宽度的 `NSTextAttachment`（图片）在菜单栏进行渲染排列，从根本上解决数值跳动时引起的系统状态栏整体抖动挤压问题。
- 新增安全降级微圆点 `●`（`renderPlaceholderImage`）机制，当所有状态栏元素隐藏或在停止监控状态下，渲染 16 像素圆点保留状态栏的点击热区。

### Fixed
- 修复状态栏未监控（`!viewModel.isRunning`）状态下的排版留白 Bug：延迟和标签仅在监控运行时显示并占用宽度，未运行状态下自动收回不留空。
- 修复 `MainView.swift` 编译时的大括号未匹配错误，并将“字体大小”和“字体粗细”从“显示网速”包裹中移出为通用全局状态栏设置。

---

## [v2.2.0] - 2026-05-13 · 质量引擎精化

### Fixed
- `resolutionScore`：零 DNS 失败时上限由 85 修正为 100，消除与其他维度的不对称性
- `spikeRate`：样本数 <5 时跳过尖峰率计算，避免冷启动阶段的误报评分

### Added
- `detectScoreDegradation()`：每 5 个批次轮次检测评分变化；分数跌破 40 触发 `.critical` 质量事件，单批次降幅 ≥20 分触发 `.warning` 质量事件
- 质量趋势卡片新增**抖动趋势徽章**：抖动 >25 ms 时以橙色突出显示
- 统计页原始指标格新增 **P99 延迟**单元格

### Changed
- 提取 `trendPoints(from:bucketInterval:)` 公共 helper，消除 ~80 行重复趋势分桶逻辑
- `NetworkQualityWindow` 新增 `bucketInterval` 计算属性（`.oneMinute` = 5 s，`.fiveMinutes` = 15 s，`.oneHour` = 60 s）
- 趋势评分公式引入抖动惩罚（>25 ms 扣 15 分，>10 ms 扣 8 分），与全维度评分模型保持一致
- 质量趋势折线颜色统一改为固定的 `accentBlue`，不再随分段评分变色

---

## [v2.1.2-R16] - 2026-05-13 · Tailscale CGNAT 检测

### Added
- 100.64.0.0/10（CGNAT 地址段）即时识别为 Tailscale 地址，无需等待异步节点列表加载
- 匹配节点 `PrimaryRoutes` 广播子网路由内的 IP，支持 Tailscale 子网路由场景
- 节点列表延迟加载完成后，自动重启以普通 ICMP 启动的探针，升级为 Tailscale Ping

### Changed
- `tailscale ping` 切换为非 JSON 输出模式，简化延迟解析逻辑
- `isIPv4InCIDR` / `ipv4ToUInt32` 辅助函数新增

---

## [v2.1.2-R15] - 2026-05-09 · 版本号同步

### Changed
- Marketing version 同步为 2.1.2-R15 / build 118

---

## [v2.1.2-R14] - 2026-05-09 · 状态栏与网速稳定性

### Fixed
- 状态栏在「仅标签」模式下无规则命中时缩至零宽变为不可点击；现在回退显示 `●` 占位符
- `NetworkSpeedManager.fetchStats` 新增 `isFetchingStats` 并发保护，防止慢速 netstat 进程重叠调用导致时间间隔近零、速度尖峰
- 流量计数器回绕导致的负值速度（Bug #4）
- 睡眠/唤醒后基准未重置导致的速度突增（Bug #3）
- 带星号后缀的 down 接口 ID 不稳定导致的重复条目（Bug #2）

### Added
- `NetworkSpeedManagerTests`：34 个单元测试用例，覆盖上述所有修复点

### Changed
- `parseLsof` 与 `fetchProcessTraffic` 改为并行 Task 执行，进程列表刷新耗时从 ~1.5 s 降至 ~1 s
- 提取 `aggregateTotals` 辅助函数，流量统计逻辑集中管理

---

## [v2.1.2-R13] - 2026-04-29 · 快速访问功能区

### Changed
- 顶部快速访问面板重构为可折叠条带：展开时每台主机独立行，固定 110 px 名称列 + 横向滚动快捷操作列表
- 展开/折叠状态通过 `@AppStorage("pm.quickAccessExpanded")` 持久化，跨重启保留；默认展开

---

## [v2.1.2-R12] - 2026-04-28 · 质量引擎首版 & 特权管理

### Added
- **探针诊断框架**：`ProbeFailureReason` / `ProbeFailureCategory` / `ProbePathKind` / `ProbePathSnapshot` / `HostProbeDiagnostic`，每次 ping 结构化记录失败原因与路径元数据
- **六维质量评分引擎**：`QualityDimensionScores`（延迟/稳定性/路径/带宽/DNS 解析/叠加层）、`HostQualitySnapshot`、`GlobalQualitySnapshot`、`NetworkQualityEvent`、`QualityTrendPoint`；4096 样本环形缓冲（`maxProbeSamplesPerHost`）
- **质量评估 Tab**：1 分钟 / 5 分钟 / 1 小时三时间窗口，维度分解条形图、事件流
- **`PrivilegedManager`**：FIFO 持久化特权 Bash 会话（`/tmp/pingmonitor_priv_fifo`），单次授权后全生命周期复用，彻底消除 Traceroute/MTR 重复弹窗
- **`KeepAliveManager`**：Passive / Intensive / Adaptive 三档探测策略；SSH 主机自动升频，检测到空闲时自动降频；监听 `utun*` 接口状态
- **`ConfigManager`**：统一 JSON 持久化层，管理 `hosts.json` / `presets.json` / `stats.json` / `settings.json`；首次启动自动从 UserDefaults 迁移旧数据
- **`FolderMonitor`**：`DispatchSourceFileSystemObject` 封装，防抖监听配置目录变更
- **`WidgetDataManager`**：三级回退同步策略（App Group → 容器文件 → 共享目录）；5 s 节流防止频繁 IO
- **`PrivilegedManager` FIFO 安全加固**：/tmp 竞态条件（TOCTOU）防护

---

## [v2.1.1] - R1–R9 · 性能优化与架构拆分

### Changed
- 缓存 `NSRegularExpression` / `DateFormatter` / `ByteCountFormatter` 为 `nonisolated(unsafe) static`，消除高频路径重复分配
- 默认探测间隔调整为 10 秒
- `MainView.swift`（2444 行）拆分为 `DashboardView`、`HostDetailView`、`NetworkSpeedTab`、`TracerouteView`、`TailscaleTab` 五个独立文件
- Widget 数据同步节流至 5 s，减少 90%+ 无效文件 IO
- Ping 主机查找改为 UUID 匹配，消除数组索引错位风险

### Added
- 主机拖拽排序
- Tailscale 快捷命令面板与 Exit Node 状态标识
- 图表阶梯式警示色（<100 ms 绿 / 100–300 ms 橙 / >300 ms 红）

### Fixed
- 主机规则编辑器排版错位及默认值缺失
- 主应用与小组件 App Group 双向通讯
- 浅色/深色模式设计系统适配

---

## [v2.1.0] - 核心功能与 UI 升级 (r19–r38)

### Added
- **Traceroute / MTR**：逐跳 IP、延迟与丢包；地图可视化本地→目标完整路径；MTR 持续追踪模式
- 监控页顶部常驻 `ServiceShortcutsRibbon` 快捷访问面板
- 独立变更日志文件与自动打包脚本联动

### Changed
- 采用单次提权 Bash 容器封装 MTR 循环，消除频繁系统授权弹窗
- 网速页折线图升级为平滑贝塞尔曲线与渐变填充
- 全新状态栏：网速仪表盘集成、固定宽度防抖

### Fixed
- VPN / Tailscale 接口下 Errors 计数异常
- 主机卡片连接状态颜色判断逻辑
- Traceroute 权限执行问题

---

## [v2.0.x] - 功能奠基与体验完善 (r21–r64)

### Added
- 自动发现并一键导入 Tailscale 私有网络节点；NAT 类型检测；Exit Node 切换
- 全局服务快捷方式面板；SSH 自动认证（expect 脚本绕过 AppleScript 授权限制）
- 统计仪表盘 3D 立体饼图
- 小/中/大三款 WidgetKit 桌面小组件
- 中英文运行时动态切换（`Localization.swift`）
- Bark 远程推送通知
- 审计日志（Debug/Info/Warning/Error 分级）

### Changed
- 状态栏多级间距、字体与网速全集成
- 设置页重构为卡片式分组设计
- `WidgetDataManager` 三级回退同步策略

### Fixed
- macOS 15.7+ 环境下小组件背景色崩溃
- 网速状态栏抖动与排版对齐
- AppleScript 授权限制下的 SSH 认证问题
