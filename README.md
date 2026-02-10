# PingMonitor

macOS 菜单栏网络延迟监控工具，支持多主机监控、实时统计、可视化图表和智能通知。

## 功能特性

### 核心功能

- **多主机监控** - 同时监控多个网络地址
- **连续 Ping 模式** - 实时 1 秒间隔延迟检测
- **智能状态指示** - 绿/橙/红三色延迟状态
- **阈值规则** - 自定义延迟阈值触发显示标签

### 界面特性

- **响应式卡片布局** - 自适应 1-4 列网格
- **实时统计面板** - 请求数、成功率、丢包率、流量统计
- **延迟趋势图表** - 可视化历史延迟曲线
- **悬浮交互效果** - 卡片悬浮放大、阴影变化
- **应用图标** - 完整的 macOS 图标集支持

### 数据统计

- **单主机统计** - 最小/最大/平均延迟
- **聚合统计** - 多主机数据汇总
- **流量统计** - 发送/接收字节统计
- **运行时长追踪**

### 其他特性

- **主机预设** - 快速添加常用主机
- **显示规则** - 自定义延迟标签显示
- **系统通知** - 延迟超标时推送通知
- **日志系统** - 完整 ping 记录
- **登录启动** - 开箱即用

## 技术架构

| 组件     | 技术                      |
| -------- | ------------------------- |
| UI 框架  | SwiftUI 6.0               |
| 最低系统 | macOS 14.0+               |
| 架构模式 | MVVM                      |
| 数据存储 | UserDefaults (App Groups) |
| 构建工具 | XcodeGen                  |

## 项目结构

```
PingMonitor/
├── PingMonitor/
│   ├── PingMonitorApp.swift    # 主应用入口
│   ├── MainView.swift          # UI 视图
│   ├── Info.plist              # 应用配置
│   ├── PingMonitor.entitlements # 权限配置
│   └── Assets.xcassets/        # 应用图标
├── PingMonitorWidget/
│   ├── PingMonitorWidget.swift # 小组件
│   └── Info.plist
├── project.yml                  # XcodeGen 配置
└── build.sh                    # 自动化打包脚本
```

## 编译与打包

### 环境要求

- macOS 14.0+
- Xcode 17+
- XcodeGen: `brew install xcodegen`

### 编译命令

```bash
# 完整打包 (自动递增版本)
chmod +x build.sh
./build.sh

# 仅打包 (不递增版本)
./build.sh
```

### 版本控制

编辑 `build.sh` 顶部的 `AUTO_VERSION` 变量:

```bash
AUTO_VERSION=true   # 自动递增版本号 (默认)
AUTO_VERSION=false  # 不递增版本号
```

## DMG 安装包

编译后输出至 `~/Desktop/PingMonitor-v{version}-r{build}.dmg`

**安装方法:**

1. 打开 DMG 文件
2. 将 PingMonitor 拖动到 Applications 文件夹
3. 或点击 DMG 中的 Applications 快捷入口

## 使用说明

### 添加监控主机

1. 点击右上角「添加」按钮
2. 输入名称和地址
3. (可选) 自定义 ping 命令，使用 `{host}` 占位符

### 设置显示规则

```
<50ms → P2P    # 延迟小于 50ms 显示 P2P 标签
>100ms → 转发  # 延迟大于 100ms 显示转发标签
```

### 查看统计数据

1. 切换到「统计」标签
2. 选择查看「全部主机」或单个主机
3. 实时延迟图表和详细指标

### 配置通知

- 延迟 > 阈值时发送系统通知
- 支持 Bark 远程推送

## 版本历史

| 版本    | 构建 | 更新内容                                                     |
| ------- | ---- | ------------------------------------------------------------ |
| v2.0.24 | r25  | 美化卡片、悬浮效果、延迟图表、应用图标、Applications 快捷入口 |
| v2.0.22 | r23  | 响应式网格布局、聚合统计、延迟图表                           |
| v2.0.20 | r21  | 连续 ping 模式、数据统计                                     |

## 开源协议

MIT License

## 致谢

基于 SwiftUI 构建，使用了 Apple 系统框架和以下开源项目:

- XcodeGen - 项目生成工具
