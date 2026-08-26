#!/bin/bash
# design-audit.sh — 设计规范审计
#
# 用法:
#   scripts/design-audit.sh            # report-only，恒退出 0
#   scripts/design-audit.sh --strict   # 存在违规时退出 1（发布前把关用）
#
# 四类违规（对应 CLAUDE.md「设计规范」章节）:
#   1. padding/spacing 数字字面量   —— 间距只能用 Theme.Space
#   2. 系统字体逃逸                 —— 字体只能用 Theme.Fonts.ui/.number/.icon
#   3. cornerRadius 数字字面量      —— 圆角只能用 Theme.Radius / Layout.cardCornerRadius
#   4. segmented Picker 定宽（.frame(width:)）却缺 .controlSize(.small)
#      （设置行/表单里的全尺寸分段选择器是合法形态，不算违规）
#
# 白名单: 行尾加注释 `// design-audit: allowed` 可豁免该行。
# 范围: 只审主 App（PingMonitor/）；Widget 目标不引 Theme 属已知例外。
# Theme.swift 是令牌定义处、DesignSystem.swift 是组件实现处，均不参与审计。

set -u
cd "$(dirname "$0")/.."

SRC="PingMonitor"
ALLOWED="design-audit: allowed"
EXCLUDE_RE='/(Theme|DesignSystem)\.swift:'
strict=0
picker_detail=""
[ "${1:-}" = "--strict" ] && strict=1

files_with() { # $1 = grep extra args...
    grep -rn --include='*.swift' "$@" "$SRC" 2>/dev/null \
        | grep -vE "$EXCLUDE_RE" \
        | grep -v "$ALLOWED"
}

# 1) padding / spacing 数字字面量（排除 String.padding(toLength:) 与 spacing: 0 结构值）
pad_hits=$(files_with -E '\.padding\((\.[a-z]+, )?[0-9]' | grep -v toLength)
spc_hits=$(files_with -E '[a-zA-Z]*spacing: [0-9]+' | grep -v 'spacing: 0')
n_pad=$(echo "$pad_hits" | grep -c . || true)
n_spc=$(echo "$spc_hits" | grep -c . || true)

# 2) 系统字体逃逸：.font(.headline) 等
font_hits=$(files_with -E '\.font\(\.[a-zA-Z]')
n_font=$(echo "$font_hits" | grep -c . || true)

# 3) 圆角数字字面量
rad_hits=$(files_with -E 'cornerRadius\([0-9]')
n_rad=$(echo "$rad_hits" | grep -c . || true)

# 4) segmented Picker 后 3 行内：有 .frame(width:) 却没有 .controlSize 的用例
picker_misses=0
while IFS= read -r line; do
    f="${line%%:*}"          # path
    rest="${line#*:}"
    ln="${rest%%:*}"         # line number
    end=$((ln + 3))
    window=$(sed -n "${ln},${end}p" "$f")
    if echo "$window" | grep -q 'frame(width:' \
        && ! echo "$window" | grep -q 'controlSize'; then
        picker_misses=$((picker_misses + 1))
        picker_detail="${picker_detail}${line}\n"
    fi
done < <(files_with 'pickerStyle(.segmented)')
n_picker=$picker_misses

total=$((n_pad + n_spc + n_font + n_rad + n_picker))

printf '%s\n' "── 设计规范审计 ──────────────────────────────"
printf '%-46s %s\n' "1a) padding 数字字面量"         "$n_pad"
printf '%-46s %s\n' "1b) spacing 数字字面量"         "$n_spc"
printf '%-46s %s\n' "2) 系统字体逃逸"               "$n_font"
printf '%-46s %s\n' "3) cornerRadius 数字字面量"     "$n_rad"
printf '%-46s %s\n' "4) segmented Picker 缺 controlSize" "$n_picker"
printf '%s\n' "──────────────────────────────────────────"
printf '%-46s %s\n' "合计" "$total"

if [ "$strict" = "1" ] && [ "$total" -gt 0 ]; then
    echo "STRICT: 存在违规，退出码 1。明细:"
    echo "$pad_hits"; echo "$spc_hits"; echo "$font_hits"; echo "$rad_hits"
    printf '%b' "$picker_detail"
    exit 1
fi
exit 0
