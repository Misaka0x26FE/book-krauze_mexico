#!/usr/bin/env bash
# qc_check.sh — 翻译质量自动化检查
# 用法：bash qc_check.sh [译文目录] [合并文件]
# 默认：split_translated，可选传入 书名.md 作全量扫描

set -euo pipefail

DIR="${1:-split_translated}"
MERGED="${2:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

issues=0
checks=0
warnings=0

check_pass() { ((checks++)); echo -e "  ${GREEN}✓${NC} $1"; }
check_fail() { ((checks++)); ((issues++)); echo -e "  ${RED}✗${NC} $1"; }
check_warn() { ((warnings++)); echo -e "  ${YELLOW}⚠${NC} $1"; }

echo "============================================"
echo "  翻译质量检查"
echo "============================================"
echo ""

# ── 1. ** 成对匹配 ──
echo "【1】** 加粗标记配对检查"
bad_asterisks=0
for f in "$DIR"/*.md; do
    [[ -f "$f" ]] || continue
    lineno=0
    while IFS= read -r line; do
        ((lineno++))
        count=$(echo "$line" | grep -o '\*\*' | wc -l)
        if (( count % 2 != 0 )); then
            echo "    $(basename "$f"):$lineno — ** 不配对"
            ((bad_asterisks++))
        fi
    done < "$f"
done
(( bad_asterisks == 0 )) && check_pass "** 全部成对匹配" || check_fail "$bad_asterisks 处 ** 不配对"

# ── 2. 图片路径检查 ──
echo ""
echo "【2】图片路径有效性检查"
bad_images=0
for f in "$DIR"/*.md; do
    [[ -f "$f" ]] || continue
    lineno=0
    while IFS= read -r line; do
        ((lineno++))
        img=$(echo "$line" | grep -oP '!\[.*?\]\(\K[^)]+' || true)
        if [[ -n "$img" ]] && [[ ! "$img" =~ ^https?:// ]]; then
            if [[ ! -f "$img" ]]; then
                echo "    $(basename "$f"):$lineno — 图片缺失: $img"
                ((bad_images++))
            fi
        fi
    done < "$f"
done
(( bad_images == 0 )) && check_pass "图片路径全部有效" || check_fail "$bad_images 个图片路径无效"

# ── 3. HTML 标签残留 ──
echo ""
echo "【3】HTML 标签残留检查"
html_count=$(grep -rc '<img\|<br\|<div\|<span\|<p \|<a href' "$DIR"/*.md 2>/dev/null | awk -F: '{sum+=$2} END{print sum+0}')
if (( html_count == 0 )); then
    check_pass "无 HTML 标签残留"
else
    check_warn "$html_count 处 HTML 标签残留"
    grep -rn '<img\|<br\|<div\|<span\|<p \|<a href' "$DIR"/*.md 2>/dev/null | head -20
fi

# ── 4. 跨文件断句 ──
echo ""
echo "【4】跨文件断句检查"
files=($(ls "$DIR"/[0-9][0-9][0-9][0-9].md 2>/dev/null | sort))
broken=0
for ((idx=0; idx < ${#files[@]} - 1; idx++)); do
    prev="${files[idx]}"
    curr="${files[idx+1]}"
    prev_last=$(tail -5 "$prev" | grep -v '^[[:space:]]*$' | tail -1)
    curr_first=$(head -5 "$curr" | grep -v '^[[:space:]]*$' | head -1)
    local comma_regex='[，,；;、]$'
    if [[ "$prev_last" =~ $comma_regex ]] && [[ "$curr_first" =~ ^[^[:space:]#\>] ]]; then
        echo "    $(basename "$prev") → $(basename "$curr"): $prev_last | $curr_first"
        ((broken++))
    fi
done
(( broken == 0 )) && check_pass "跨文件断句全部正常" || check_fail "$broken 处跨文件断句"

# ── 5. InDesign 残留检测 ──
echo ""
echo "【5】InDesign/Calibre 标记残留检查"
artifact_count=0
for f in "$DIR"/*.md; do
    [[ -f "$f" ]] || continue
    lineno=0
    while IFS= read -r line; do
        ((lineno++))
        # 匹配 {.XXX} 类残留（CSS类名泄露）
        if echo "$line" | grep -qP '\{\._\w+[^}]*\}'; then
            echo "    $(basename "$f"):$lineno — CSS类残留: $(echo "$line" | grep -oP '\{\._\w+[^}]*\}' | head -1)"
            ((artifact_count++))
        fi
        # 匹配原始脚注标记 [n{...}]{...}
        if echo "$line" | grep -qP '\[\d+\{[^}]*\}.*?\]\{[^}]*\}'; then
            echo "    $(basename "$f"):$lineno — 原始脚注残留"
            ((artifact_count++))
        fi
        # 匹配 InDesign 容器 ID
        if echo "$line" | grep -qP ':::\{#.*?#_idContainer'; then
            echo "    $(basename "$f"):$lineno — 容器ID残留"
            ((artifact_count++))
        fi
    done < "$f"
done
(( artifact_count == 0 )) && check_pass "无 InDesign/Calibre 残留" || check_fail "$artifact_count 处标记残留"

# ── 6. blockquote 完整性 ──
echo ""
echo "【6】blockquote 完整性检查"
bad_q=0
for f in "$DIR"/*.md; do
    [[ -f "$f" ]] || continue
    lineno=0
    in_q=false
    while IFS= read -r line; do
        ((lineno++))
        is_q=$(echo "$line" | grep -c '^>') || true
        if $in_q && (( is_q == 0 )) && [[ -n "${line// }" ]] && [[ ! "$line" =~ ^\[ ]]; then
            echo "    $(basename "$f"):$lineno — blockquote 可能不完整"
            ((bad_q++))
            in_q=false
        fi
        $in_q && (( is_q == 0 )) && in_q=false
        (( is_q > 0 )) && in_q=true
    done < "$f"
done
(( bad_q == 0 )) && check_pass "blockquote 完整性 OK" || check_warn "$bad_q 处可疑断点"

# ── 7. 未翻译原文残留 ──
echo ""
echo "【7】未翻译原文残留检查"
total_lines=0
foreign_lines=0
eng_blocks=0
for f in "$DIR"/*.md; do
    [[ -f "$f" ]] || continue
    file_lines=$(wc -l < "$f")
    total_lines=$(( total_lines + file_lines ))
    # 西里尔字母
    cyrillic=$(grep -cP '[А-Яа-яЁё]' "$f" 2>/dev/null || true)
    foreign_lines=$(( foreign_lines + cyrillic ))
    (( cyrillic > file_lines / 2 )) && check_warn "$(basename "$f"): 西里尔字母占比高 ($cyrillic/$file_lines 行)"

    # 连续 3+ 行纯英文（未翻译段落检测）
    local eng_pattern='^[A-Za-z0-9 .,;:!?()\[\]—–/&%$#@+\*=<>|`~\\'"'"'"-]+$'
    eng_seq=$(grep -nP "$eng_pattern" "$f" 2>/dev/null || true)
    if [[ -n "$eng_seq" ]]; then
        # 统计连续段数
        eng_blocks=$(( eng_blocks + $(echo "$eng_seq" | wc -l) ))
    fi
done
if (( total_lines > 0 )); then
    ratio=$(( 100 * foreign_lines / total_lines ))
    (( ratio < 5 )) && check_pass "未翻译原文比例: ${ratio}% (正常)" || check_warn "未翻译原文比例: ${ratio}% (偏高)"
fi
if (( eng_blocks > 0 )); then
    check_warn "发现约 $eng_blocks 行连续英文，可能存在未翻译段落"
fi

# ── 8. 标点规范 ──
echo ""
echo "【8】标点规范检查"
ascii_q=0
for f in "$DIR"/*.md; do
    [[ -f "$f" ]] || continue
    lineno=0
    while IFS= read -r line; do
        ((lineno++))
        # ASCII 直引号在中文上下文中
        if echo "$line" | grep -qP '[\x{4e00}-\x{9fff}].*"[^"]*[\x{4e00}-\x{9fff}]'; then
            echo "    $(basename "$f"):$lineno — ASCII直引号在中文中"
            ((ascii_q++))
        fi
    done < "$f"
done
(( ascii_q == 0 )) && check_pass "标点规范 OK" || check_warn "$ascii_q 处 ASCII 直引号"

# ── 9. 封面图片重复 ──
echo ""
echo "【9】封面图片重复检查"
if [[ -f "$MERGED" ]]; then
    dup_count=$(grep -co '!\[.*\].*cover' "$MERGED" 2>/dev/null || true)
    if (( dup_count > 1 )); then
        check_warn "封面图片出现 $dup_count 次，可能存在冗余"
    else
        check_pass "封面图片无重复"
    fi
else
    check_pass "封面图片检查跳过（无合并文件）"
fi

# ── 10. 脚注/尾注完整性 ──
echo ""
echo "【10】脚注/尾注完整性检查"
fn_total=0
if [[ -f "$MERGED" ]]; then
    fn_mark=$(grep -cP '\[\^[0-9]+\]' "$MERGED" 2>/dev/null || true)
    fn_def=$(grep -cP '^\[\^[0-9]+\]:' "$MERGED" 2>/dev/null || true)
    # 尾注页内容检查
    endnote_section=$(sed -n '/^## Endnotes\|^## 尾注/,/^## /p' "$MERGED" 2>/dev/null | grep -v '^## ' | grep -cP '[^\s]' || true)
    echo "    脚注标记: $fn_mark, 脚注定义: $fn_def"
    echo "    尾注页内容行数: $endnote_section"
    if (( fn_mark > 0 && fn_def == 0 )); then
        if (( endnote_section <= 2 )); then
            check_fail "有 $fn_mark 个脚注标记但无定义，且尾注页为空（转换丢失）"
        else
            check_fail "有 $fn_mark 个脚注标记但无定义"
        fi
    elif (( fn_mark == 0 && fn_def == 0 )); then
        if (( endnote_section > 0 && endnote_section <= 2 )); then
            check_warn "尾注页仅有标题无内容"
        else
            check_pass "无脚注（或已处理）"
        fi
    elif (( fn_mark > 0 && endnote_section <= 2 )); then
        check_warn "有脚注定义但尾注页似乎无内容"
    else
        check_pass "脚注 $fn_mark / $fn_def 配对正常"
    fi
else
    check_pass "脚注检查跳过（无合并文件）"
fi

# ── 11. 章节标题一致性（合并文件） ──
echo ""
echo "【11】章节标题一致性检查"
if [[ -f "$MERGED" ]]; then
    h2_count=$(grep -c '^## ' "$MERGED" 2>/dev/null || true)
    h3_count=$(grep -c '^### ' "$MERGED" 2>/dev/null || true)
    # 检查是否既有 ** 作为标题又有 ## （不一致）
    bold_title=$(grep -cP '^\*\*[^*]+\*\*$' "$MERGED" 2>/dev/null || true)
    echo "    ## : $h2_count, ### : $h3_count, **标题**: $bold_title"
    if (( h2_count == 0 && bold_title > 0 )); then
        check_warn "无 ## 标题，仅有 **加粗标题**（将不生成 EPUB 目录）"
    else
        check_pass "章节标题层级 OK"
    fi
else
    check_pass "标题一致性检查跳过（无合并文件）"
fi

# ── 汇总 ──
echo ""
echo "============================================"
if (( issues == 0 && warnings == 0 )); then
    echo -e "  ${GREEN}全部 $checks 项检查通过 ✓${NC}"
elif (( issues == 0 )); then
    echo -e "  ${YELLOW}$checks 项检查通过，$warnings 项警告${NC}"
else
    echo -e "  ${RED}$issues/$checks 项检查发现问题，$warnings 项警告 ✗${NC}"
fi
echo "============================================"
