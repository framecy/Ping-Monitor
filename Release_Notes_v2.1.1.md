# PingMonitor v2.1.1 Release Notes

本次版本更新（v2.1.1 系列，相较于 v2.1.0 版本）重点提升了界面的 UI 交互一致性、图表视觉表现、内存运行效率，并彻底修复了 macOS 小组件可见性以及相关的环境授权问题。

## ✨ 新增功能 (Added)
- **主机任意拖放排序 (Draggable Reordering)**：在主监控网格视图中，支持通过长按并拖拽随意调整主机的卡片排序。
- **Tailscale 指令中枢 (Quick Commands)**：在 Tailscale 标签页中加入了功能强大的 Command Ribbon，支持一键发起 Status, Netcheck, Ping All, 以及 Exit Node 命令行查询，并能直接在日志区捕获返回结果。
- **Exit Node 状态可视化 (Exit Node Indicators)**：在局域网节点视图中，Tailscale 节点现在会显示直观的 Exit Node (出口节点) 图标，方便辨认。
- **沙盒与组数据共享 (App Group & Sandbox)**：小组件体系完全接入 App Sandbox，并打通 `group.com.pingmonitor.shared` App Group，保证了应用数据能够被小组件安全、正确地读取。

## 💄 界面与体验优化 (Updated)
- **设计系统革新 (Theme System Overhaul)**：适配了极其完整的 Light/Dark 浅色深色模式，修复了此前在浅色高亮模式下部分文字对比度过低的核心问题。
- **Mini-Sparkline 图表视觉升级**：
  - 弃用简易拉伸，采用全局一致的笔触宽度 (2px)
  - 引入了丝滑的渐变填充区 (Linear Gradient Fill)
  - 根据最新延迟状态呈现绿、橙、红三种阶梯色彩（`<100ms` 绿色，`100-300ms` 橙色，`>300ms` 红色）。
- **捷径面板重编排 (Quick Access Ribbon)**：全局服务状态捷径栏从易被遮挡横向滑动视图 (`ScrollView`) 重构为响应式流式网格 (`LazyVGrid`)，所有项一览无余。
- **默认侦测与显示规则优化**：
  - 添加新监控主机的默认命令由 1 秒检测优化至**每 10 秒检测一次** (`ping -i 10 $address`)，极大减缓长驻 CPU 请求负荷。
  - 新主机的默认规则更新为更贴近直觉的 `<50ms -> 直连(Direct)` 与 `>100ms -> 转发(Relay)`。
- **设置页排版对齐 (Settings Layout)**：梳理了设置页面所有控制行，左侧标题与右侧组件（Stepper，Picker，Toggle 等）拥有绝对严格的对齐基线，整体布局扩展至右对齐 220pt 宽度。

## 🐛 核心修复 (Fixed)
- **小组件无法添加 (Widget Visibility)**：修复了长期存在的“PingMonitor 小组件由于打包配置缺少真机签名及 Sandbox 权限认证而被 macOS 系统画廊封禁隐藏”的严重级问题。
- **内存泄漏与图表重绘爆炸 (Performance & Memory Sink)**：大幅缓解了大量的主机（特别是短频检测时）不断触发 `@Published`，导致 SwiftUI 无限制重绘底层复杂 UI 图表引发系统内存极速攀升的灾难性反馈。
- **表单畸变修复 (Form Alignment)**：完美修整了“主机显示规则编辑器”中 Threshold 编辑框与 Label 内容长短不一导致的垂直水平同时错位的问题。
- **数据回滚 Bug**：修正了用户新增主机时，没有自动填入预设状态规则的 Bug。
