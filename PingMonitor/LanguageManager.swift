import SwiftUI

enum Language: String, CaseIterable {
    case zh = "zh"
    case en = "en"
    
    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @AppStorage("appLanguage", store: UserDefaults(suiteName: "group.com.pingmonitor.shared")) var languageString: String = "zh" {
        didSet {
            currentLanguage = Language(rawValue: languageString) ?? .zh
        }
    }
    
    @Published var currentLanguage: Language = .zh
    
    init() {
        self.currentLanguage = Language(rawValue: languageString) ?? .zh
    }
    
    func t(_ key: String) -> String {
        return translations[currentLanguage]?[key] ?? key
    }
    
    func toggle() {
        languageString = (currentLanguage == .zh) ? "en" : "zh"
    }
    
    // MARK: - Translations
    private let translations: [Language: [String: String]] = [
        .en: [
            // Sidebar
            "sidebar.monitor": "Monitor",
            "sidebar.dashboard": "Dashboard",
            "sidebar.traceroute": "Traceroute",
            "sidebar.hosts": "Hosts",
            "sidebar.logs": "Logs",
            "sidebar.settings": "Settings",
            "sidebar.overview": "Overview",
            "sidebar.management": "Management",
            "sidebar.config": "Config",
            "sidebar.admin": "Administrator",
            
            // Header
            "header.monitoring": "Monitoring %d hosts",
            "header.stopped": "Stopped",
            "header.start": "Start",
            "header.stop": "Stop",
            
            // Dashboard
            "dashboard.running_status": "Running Status",
            "dashboard.uptime": "Uptime",
            "dashboard.running": "Running",
            "dashboard.hosts_count": "Hosts",
            "dashboard.memory": "Memory",
            "dashboard.system": "System",
            "dashboard.version": "Version",
            "dashboard.network_status": "Network Status",
            "dashboard.network_wifi": "Network",
            "dashboard.latency_trend": "Latency Trend",
            "dashboard.no_data": "No Data",
            "dashboard.seven_day_trend": "7-Day Trend",
            "dashboard.daily_avg": "Daily Avg",
            "dashboard.ping_summary": "Ping Summary",
            "dashboard.total": "Total",
            "dashboard.success": "Success",
            "dashboard.failed": "Failed",
            "dashboard.timeout": "Timeout",
            "dashboard.latency_ranking": "Latency Ranking",
            
            // Monitor Tab
            "monitor.title": "Monitoring Hosts",
            "monitor.add": "Add",
            "monitor.no_hosts": "No Hosts",
            "monitor.add_host_hint": "Click add button to start",
            
            // Host Management
            "host.manage.section.saved": "Saved Hosts",
            "host.manage.section.presets": "Presets",
            "host.manage.add": "Add Host",
            "host.manage.no_hosts": "No Hosts",
            "host.manage.add_hint": "Add host to start monitoring",
            "host.manage.quick_add": "Quick Add Presets",
            "host.manage.add_preset": "Add Preset",
            "host.manage.no_presets": "No Presets",
            "host.manage.add_preset_hint": "Add presets for quick host creation",
            
            // Editors
            "editor.add_host": "Add Host",
            "editor.edit_host": "Edit Host",
            "editor.add_preset": "Add Preset",
            "editor.edit_preset": "Edit Preset",
            "editor.basic_info": "Basic Info",
            "editor.name": "Name",
            "editor.address": "Address",
            "editor.command": "Command (Optional)",
            "editor.command_hint": "Default: ping -i 1 $address\nSupports $address placeholder",
            "editor.preset_command_hint": "Default: ping -c 1 -W 3 $address",
            "editor.display_rules": "Display Rules",
            "editor.add_rule": "Add Rule",
            "editor.cancel": "Cancel",
            "editor.save": "Save",
            "editor.add": "Add",
            
            // Common
            "common.add": "Add",
            "common.cancel": "Cancel",
            "common.save": "Save",
            
            // Editor sections
            "editor.section.basic": "Basic Info",
            "editor.section.rules": "Display Rules",
            
            // Editor rule aliases (code uses editor.rule.* prefix)
            "editor.rule.enable": "Enable",
            "editor.rule.condition": "Condition",
            "editor.rule.greater": "Greater than",
            "editor.rule.less": "Less than",
            "editor.rule.threshold": "Threshold (ms)",
            "editor.rule.label": "Label",
            "editor.rule.label_placeholder": "e.g. P2P",
            
            // Rules
            "rule.enable": "Enable",
            "rule.condition": "Condition",
            "rule.less": "Less than",
            "rule.greater": "Greater than",
            "rule.threshold": "Threshold (ms)",
            "rule.label": "Label",
            "rule.add_title": "Add Display Rule",
            "rule.latency_less": "Latency <",
            "rule.latency_greater": "Latency >",
            
            // Logs
            "logs.level": "Log Level",
            "logs.level.all": "All",
            "logs.level.debug": "DEBUG",
            "logs.level.info": "INFO",
            "logs.level.warn": "WARN",
            "logs.level.error": "ERROR",
            "logs.all": "All",
            "logs.clear": "Clear",
            "logs.export": "Export",
            
            // Settings
            "settings.display_mode": "Display Mode",
            "settings.display.average": "Average",
            "settings.display.worst": "Worst",
            "settings.display.best": "Best",
            "settings.display.first": "First",
            "settings.avg_latency": "Avg Latency",
            "settings.worst_host": "Worst Host",
            "settings.best_host": "Best Host",
            "settings.first_host": "First Host",
            "settings.desc.average": "Show average latency of all hosts",
            "settings.desc.worst": "Show highest latency or unreachable host",
            "settings.desc.best": "Show lowest latency host",
            "settings.desc.first": "Show first host in the list",
            "settings.desc.avg": "Show average latency of all hosts",
            "settings.desc.worst_old": "Show highest latency or unreachable",
            "settings.desc.best_old": "Show lowest latency",
            "settings.desc.first_old": "Show first host in list",
            "settings.show_latency": "Show Latency Value",
            "settings.show_labels": "Show Rule Labels",
            "settings.status_bar": "Status Bar",
            "settings.section.status_bar": "Status Bar",
            "settings.section.monitor": "Monitor",
            "settings.section.notify": "Notification",
            "settings.section.system": "System",
            "settings.interval": "Ping Interval",
            "settings.interval.3s": "3s",
            "settings.interval.5s": "5s",
            "settings.interval.10s": "10s",
            "settings.interval.30s": "30s",
            "settings.monitor_interval": "Monitor Interval",
            "settings.seconds": "%.0fs",
            "settings.monitor": "Monitor",
            "settings.notify.enable": "Enable Notification",
            "settings.notify.type": "Notification Type",
            "settings.enable_notify": "Enable Notification",
            "settings.notify_type": "Notification Type",
            "settings.notify.system": "System",
            "settings.notify.bark": "Bark",
            "settings.notify": "Notification",
            "settings.auto_start": "Launch at Login",
            "settings.autostart": "Auto Start",
            "settings.system": "System",
            
            // Stats Details
            "stats.detailed": "Detailed Stats",
            "stats.requests": "Requests",
            "stats.success_rate": "Success Rate",
            "stats.loss_rate": "Loss Rate",
            "stats.traffic": "Traffic",
            "stats.success": "Success",
            "stats.failed": "Failed",
            "stats.min_latency": "Min Latency",
            "stats.max_latency": "Max Latency",
            "stats.avg_latency": "Avg Latency",
            "stats.sent": "Sent",
            "stats.received": "Received",
            "stats.reset_current": "Reset Current",
            "stats.reset_all": "Reset All",
            "stats.time.hours": "%dh %dm",
            "stats.time.minutes": "%dm %ds",
            "stats.time.seconds": "%ds",
            "stats.legend.excellent": "<50ms Excellent",
            "stats.legend.good": "<100ms Good",
            "stats.legend.poor": ">100ms Poor",
            "stats.chart.count": "Count %d",
            "stats.chart.current": "Current",
            "stats.select_host": "Select Host",
            "stats.all_hosts": "All Hosts",
            
            // Cards
            "card.rules": "%d Rules",
            "card.timeout": "Timeout",
            
            // Context Menu
            "menu.edit": "Edit",
            "menu.delete": "Delete",
            "menu.add_to_monitor": "Add to Monitor",
            
            // Traceroute
            "traceroute.title": "Route Tracing",
            "traceroute.input_placeholder": "Enter hostname or IP",
            "traceroute.start": "Start Trace",
            "traceroute.stop": "Stop",
            "traceroute.mtr_mode": "MTR Mode",
            "traceroute.hop": "Hop",
            "traceroute.ip": "IP / Host",
            "traceroute.latency": "Latency",
            "traceroute.avg": "Avg",
            "traceroute.loss": "Loss",
            "traceroute.status": "Status",
            "traceroute.tracing": "Tracing route to %@...",
            "traceroute.complete": "Trace complete: %d hops",
            "traceroute.no_result": "No results yet",
            "traceroute.hint": "Enter a target to trace its network route",
            "traceroute.copy": "Copy Result",
            "traceroute.copied": "Copied!",
            "traceroute.timeout": "Timeout",
            "traceroute.mtr_hint": "MTR combines ping and traceroute for continuous monitoring",
            "traceroute.monitored_hosts": "Monitored Hosts",
            
            // Host Detail
            "host_detail.checking": "Checking...",
            "host_detail.connection_status": "Connection Status",
            "host_detail.status": "Status",
            "host_detail.online": "Online",
            "host_detail.offline": "Offline",
            "host_detail.uptime": "Uptime",
            "host_detail.latency_stats": "Latency Statistics",
            "host_detail.current": "Current",
            "host_detail.min": "Min",
            "host_detail.max": "Max",
            "host_detail.avg": "Average",
            "host_detail.jitter": "Jitter",
            "host_detail.latency_chart": "Real-time Latency",
            "host_detail.data_points": "Points",
            "host_detail.packet_stats": "Packet Statistics",
            "host_detail.total_pings": "Total Pings",
            "host_detail.success": "Success",
            "host_detail.failed": "Failed",
            "host_detail.success_rate": "Success Rate",
            "host_detail.traffic": "Traffic",
            "host_detail.sent": "Sent",
            "host_detail.received": "Received",
            "host_detail.total_traffic": "Total",
            "host_detail.display_rules": "Display Rules",
            "host_detail.enabled": "Enabled",
            "host_detail.disabled": "Disabled",
        ],
        .zh: [
            // Sidebar
            "sidebar.monitor": "监控",
            "sidebar.dashboard": "统计",
            "sidebar.traceroute": "路由追踪",
            "sidebar.hosts": "主机管理",
            "sidebar.logs": "日志",
            "sidebar.settings": "设置",
            "sidebar.overview": "概览",
            "sidebar.management": "管理",
            "sidebar.config": "配置",
            "sidebar.admin": "管理员",
            
            // Header
            "header.monitoring": "正在监控 %d 个主机",
            "header.stopped": "已停止",
            "header.start": "开始",
            "header.stop": "停止",
            
            // Dashboard
            "dashboard.running_status": "运行状态",
            "dashboard.uptime": "运行时间",
            "dashboard.running": "运行中",
            "dashboard.hosts_count": "主机数量",
            "dashboard.memory": "内存占用",
            "dashboard.system": "系统",
            "dashboard.version": "版本",
            "dashboard.network_status": "网络状态",
            "dashboard.network_wifi": "网络连接",
            "dashboard.latency_trend": "延迟趋势",
            "dashboard.no_data": "暂无数据",
            "dashboard.seven_day_trend": "7日趋势",
            "dashboard.daily_avg": "日平均",
            "dashboard.ping_summary": "Ping 统计",
            "dashboard.total": "总计",
            "dashboard.success": "成功",
            "dashboard.failed": "失败",
            "dashboard.timeout": "超时",
            "dashboard.latency_ranking": "延迟排行",
            
            // Monitor Tab
            "monitor.title": "监控中主机",
            "monitor.add": "添加",
            "monitor.no_hosts": "没有主机",
            "monitor.add_host_hint": "点击右上角按钮添加主机",
            
            // Host Management
            "host.manage.section.saved": "已保存主机",
            "host.manage.section.presets": "预设",
            "host.manage.add": "添加主机",
            "host.manage.no_hosts": "没有主机",
            "host.manage.add_hint": "添加主机开始监控",
            "host.manage.quick_add": "预设快速添加",
            "host.manage.add_preset": "添加预设",
            "host.manage.no_presets": "没有预设",
            "host.manage.add_preset_hint": "添加预设快速创建主机",
            
            // Editors
            "editor.add_host": "添加主机",
            "editor.edit_host": "编辑主机",
            "editor.add_preset": "添加预设",
            "editor.edit_preset": "编辑预设",
            "editor.basic_info": "基本信息",
            "editor.name": "名称",
            "editor.address": "地址",
            "editor.command": "命令 (可选)",
            "editor.command_hint": "留空默认: ping -i 1 $address\n支持 $address 占位符",
            "editor.preset_command_hint": "留空默认: ping -c 1 -W 3 $address",
            "editor.display_rules": "显示规则",
            "editor.add_rule": "添加规则",
            "editor.cancel": "取消",
            "editor.save": "保存",
            "editor.add": "添加",
            
            // Common
            "common.add": "添加",
            "common.cancel": "取消",
            "common.save": "保存",
            
            // Editor sections
            "editor.section.basic": "基本信息",
            "editor.section.rules": "显示规则",
            
            // Editor rule aliases
            "editor.rule.enable": "启用",
            "editor.rule.condition": "条件",
            "editor.rule.greater": "> 大于",
            "editor.rule.less": "< 小于",
            "editor.rule.threshold": "阈值(ms)",
            "editor.rule.label": "显示文本",
            "editor.rule.label_placeholder": "如: P2P",
            
            // Rules
            "rule.enable": "启用",
            "rule.condition": "条件",
            "rule.less": "< 小于",
            "rule.greater": "> 大于",
            "rule.threshold": "阈值(ms)",
            "rule.label": "显示文本",
            "rule.add_title": "添加显示规则",
            "rule.latency_less": "延迟小于",
            "rule.latency_greater": "延迟大于",
            
            // Logs
            "logs.level": "日志级别",
            "logs.level.all": "全部",
            "logs.level.debug": "调试",
            "logs.level.info": "信息",
            "logs.level.warn": "警告",
            "logs.level.error": "错误",
            "logs.all": "全部",
            "logs.clear": "清空",
            "logs.export": "导出",
            
            // Settings
            "settings.display_mode": "显示策略",
            "settings.display.average": "平均值",
            "settings.display.worst": "最差",
            "settings.display.best": "最优",
            "settings.display.first": "首个",
            "settings.avg_latency": "平均延迟",
            "settings.worst_host": "最差主机",
            "settings.best_host": "最快主机",
            "settings.first_host": "首个主机",
            "settings.desc.average": "显示所有主机的平均延迟",
            "settings.desc.worst": "显示延迟最高或不可达的主机",
            "settings.desc.best": "显示延迟最低的主机",
            "settings.desc.first": "显示列表中第一个主机",
            "settings.desc.avg": "显示所有主机的平均延迟",
            "settings.desc.worst_old": "显示延迟最高或不可达的主机",
            "settings.desc.best_old": "显示延迟最低的主机",
            "settings.desc.first_old": "显示列表中的第一个主机",
            "settings.show_latency": "显示延迟数值",
            "settings.show_labels": "显示规则标签",
            "settings.status_bar": "状态栏显示",
            "settings.section.status_bar": "状态栏显示",
            "settings.section.monitor": "监控",
            "settings.section.notify": "通知",
            "settings.section.system": "系统",
            "settings.interval": "Ping 间隔",
            "settings.interval.3s": "3秒",
            "settings.interval.5s": "5秒",
            "settings.interval.10s": "10秒",
            "settings.interval.30s": "30秒",
            "settings.monitor_interval": "监控间隔",
            "settings.seconds": "%.0f秒",
            "settings.monitor": "监控",
            "settings.notify.enable": "启用通知",
            "settings.notify.type": "通知方式",
            "settings.enable_notify": "启用通知",
            "settings.notify_type": "通知方式",
            "settings.notify.system": "系统通知",
            "settings.notify.bark": "Bark推送",
            "settings.notify": "通知",
            "settings.auto_start": "开机自启动",
            "settings.autostart": "开机自启动",
            "settings.system": "系统",
            
            // Stats Details
            "stats.detailed": "详细统计",
            "stats.requests": "请求数",
            "stats.success_rate": "成功率",
            "stats.loss_rate": "丢包率",
            "stats.traffic": "总流量",
            "stats.success": "成功请求",
            "stats.failed": "失败请求",
            "stats.min_latency": "最小延迟",
            "stats.max_latency": "最大延迟",
            "stats.avg_latency": "平均延迟",
            "stats.sent": "发送流量",
            "stats.received": "接收流量",
            "stats.reset_current": "重置当前主机统计",
            "stats.reset_all": "重置所有统计",
            "stats.time.hours": "%d小时%d分",
            "stats.time.minutes": "%d分%d秒",
            "stats.time.seconds": "%d秒",
            "stats.legend.excellent": "<50ms 优秀",
            "stats.legend.good": "<100ms 良好",
            "stats.legend.poor": ">100ms 较差",
            "stats.chart.count": "共 %d 次",
            "stats.chart.current": "当前",
            "stats.select_host": "选择主机",
            "stats.all_hosts": "全部主机",
            
            // Cards
            "card.rules": "%d 条规则",
            "card.timeout": "超时",
            
            // Context Menu
            "menu.edit": "编辑",
            "menu.delete": "删除",
            "menu.add_to_monitor": "添加到监控",
            
            // Traceroute
            "traceroute.title": "路由追踪",
            "traceroute.input_placeholder": "输入主机名或 IP",
            "traceroute.start": "开始追踪",
            "traceroute.stop": "停止",
            "traceroute.mtr_mode": "MTR 模式",
            "traceroute.hop": "跳数",
            "traceroute.ip": "IP / 主机名",
            "traceroute.latency": "延迟",
            "traceroute.avg": "平均",
            "traceroute.loss": "丢包",
            "traceroute.status": "状态",
            "traceroute.tracing": "正在追踪到 %@ 的路由...",
            "traceroute.complete": "追踪完成：共 %d 跳",
            "traceroute.no_result": "暂无结果",
            "traceroute.hint": "输入目标地址以追踪网络路由",
            "traceroute.copy": "复制结果",
            "traceroute.copied": "已复制！",
            "traceroute.timeout": "超时",
            "traceroute.mtr_hint": "MTR 结合了 Ping 和 Traceroute 进行持续监控",
            "traceroute.monitored_hosts": "监控中的主机",
            
            // Host Detail
            "host_detail.checking": "检测中...",
            "host_detail.connection_status": "连接状态",
            "host_detail.status": "当前状态",
            "host_detail.online": "在线",
            "host_detail.offline": "离线",
            "host_detail.uptime": "持续时间",
            "host_detail.latency_stats": "延迟统计",
            "host_detail.current": "当前",
            "host_detail.min": "最小",
            "host_detail.max": "最大",
            "host_detail.avg": "平均",
            "host_detail.jitter": "抖动",
            "host_detail.latency_chart": "实时延迟",
            "host_detail.data_points": "个数据点",
            "host_detail.packet_stats": "丢包统计",
            "host_detail.total_pings": "总Ping数",
            "host_detail.success": "成功",
            "host_detail.failed": "失败",
            "host_detail.success_rate": "成功率",
            "host_detail.traffic": "网络流量",
            "host_detail.sent": "发送",
            "host_detail.received": "接收",
            "host_detail.total_traffic": "总流量",
            "host_detail.display_rules": "显示规则",
            "host_detail.enabled": "已启用",
            "host_detail.disabled": "已禁用",
        ]
    ]
}
