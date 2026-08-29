import SwiftUI

// 从 MainView.swift 拆出：主机编辑器 + 显示规则行 + 添加规则弹窗

// MARK: - Editor Sheets
struct HostEditorSheet: View {
    @Binding var isPresented: Bool
    let title: String
    @Binding var name: String
    @Binding var address: String
    @Binding var command: String
    @Binding var displayRules: [DisplayRule]
    @Binding var probeMode: HostProbeMode
    @Binding var tcpPort: Int
    let onSave: () -> Void
    @State private var showingAddRule = false
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))

            ScrollView {
                Form {
                    Section(languageManager.t("editor.section.basic")) {
                        TextField(languageManager.t("editor.name"), text: $name)
                        TextField(languageManager.t("editor.address"), text: $address)
                            .textContentType(.URL)

                        Picker("Probe", selection: $probeMode) {
                            Text("ICMP").tag(HostProbeMode.icmp)
                            Text("TCP").tag(HostProbeMode.tcp)
                        }
                        .pickerStyle(.segmented)

                        if probeMode == .tcp {
                            Stepper(value: $tcpPort, in: 1...65535) {
                                HStack {
                                    Text("TCP Port")
                                    Spacer()
                                    Text("\(tcpPort)")
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(languageManager.t("editor.command"), text: $command)
                            Text(languageManager.t("editor.command_hint"))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(languageManager.t("editor.command_follows_interval"))
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.accentBlue)
                        }
                    }
                    
                    Section(languageManager.t("editor.section.rules")) {
                        ForEach($displayRules) { $rule in
                            RuleEditorRow(rule: $rule, onDelete: {
                                if let index = displayRules.firstIndex(where: { $0.id == rule.id }) {
                                    displayRules.remove(at: index)
                                }
                            })
                        }
                        
                        Button {
                            showingAddRule = true
                        } label: {
                            Label(languageManager.t("editor.add_rule"), systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(languageManager.t("common.save")) {
                    onSave()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || address.isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 500)
        .sheet(isPresented: $showingAddRule) {
            AddRuleSheet(isPresented: $showingAddRule, rules: $displayRules)
        }
    }
}

struct RuleEditorRow: View {
    @Binding var rule: DisplayRule
    let onDelete: () -> Void
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Enable toggle + Delete
            HStack {
                Toggle(languageManager.t("editor.rule.enable"), isOn: $rule.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(Theme.Fonts.icon(Theme.Fonts.Size.caption))
                }
                .buttonStyle(.borderless)
            }
            
            // Row 2: Condition + Threshold + Label (properly spaced)
            HStack(spacing: 8) {
                // Condition picker
                Picker("", selection: $rule.condition) {
                    Text(languageManager.t("editor.rule.less")).tag("less")
                    Text(languageManager.t("editor.rule.greater")).tag("greater")
                }
                .pickerStyle(.segmented)
                .frame(width: 90)
                
                // Threshold
                HStack(spacing: 4) {
                    TextField("", value: $rule.threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 45)
                    Text("ms")
                        .font(Theme.Fonts.ui(Theme.Fonts.Size.caption))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                
                Spacer(minLength: 4)
                
                // Static Label "显示文本"
                Text(languageManager.t("editor.rule.label"))
                    .font(Theme.Fonts.ui(Theme.Fonts.Size.footnote))
                    .foregroundStyle(Theme.Colors.textSecondary)
                
                // Label TextField
                TextField(languageManager.t("editor.rule.label_placeholder"), text: $rule.label)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
            .frame(height: 28) // Force consistent height to fix vertical alignment
        }
        .padding(.vertical, 8)
    }
}

struct AddRuleSheet: View {
    @Binding var isPresented: Bool
    @Binding var rules: [DisplayRule]
    @State private var condition = "less"
    @State private var threshold: Double = 100
    @State private var label = ""
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text(languageManager.t("editor.add_rule"))
                .font(Theme.Fonts.ui(Theme.Fonts.Size.headline, weight: .semibold))
            
            Form {
                Picker(languageManager.t("editor.rule.condition"), selection: $condition) {
                    Text(languageManager.t("editor.rule.less")).tag("less")
                    Text(languageManager.t("editor.rule.greater")).tag("greater")
                }
                .pickerStyle(.segmented)
                
                HStack {
                    Text(languageManager.t("editor.rule.threshold"))
                    Spacer()
                    TextField("ms", value: $threshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                
                TextField(languageManager.t("editor.rule.label_placeholder"), text: $label)
            }
            .formStyle(.grouped)
            
            HStack {
                Button(languageManager.t("common.cancel")) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(languageManager.t("common.add")) {
                    let finalLabel = label.isEmpty ? "\(condition == "less" ? "<" : ">") \(Int(threshold))ms" : label
                    rules.append(DisplayRule(condition: condition, threshold: threshold, label: finalLabel, enabled: true))
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 350)
    }
}
