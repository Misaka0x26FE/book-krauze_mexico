#!/usr/bin/env bash
# merge_md.sh — 合并 split_translated/ 分片并格式化
# 用法：bash merge_md.sh <书名> <作者> [译者] [出版社] [日期]
# 输入：split_translated/ 目录
# 输出：书名.md

set -euo pipefail

TITLE="${1:?用法: $0 <书名> <作者> [译者] [出版社] [日期]}"
AUTHOR="${2:?请提供作者名}"
TRANSLATOR="${3:-}"
PUBLISHER="${4:-}"
DATE="${5:-}"

INDIR="split_translated"
OUTFILE="${TITLE}.md"
TMPFILE=$(mktemp)

if [[ ! -d "$INDIR" ]]; then
    echo "错误: 目录不存在: $INDIR"
    exit 1
fi

echo "合并 $INDIR/ 到 $OUTFILE ..."

# 写入 YAML front matter
cat > "$TMPFILE" <<YAML
---
title: "${TITLE}"
author: "${AUTHOR}"
YAML

if [[ -n "$TRANSLATOR" ]]; then
    echo "translator: \"${TRANSLATOR}\"" >> "$TMPFILE"
fi
echo 'lang: "zh-CN"' >> "$TMPFILE"
if [[ -n "$PUBLISHER" ]]; then
    echo "publisher: \"${PUBLISHER}\"" >> "$TMPFILE"
fi
if [[ -n "$DATE" ]]; then
    echo "date: \"${DATE}\"" >> "$TMPFILE"
fi
echo "---" >> "$TMPFILE"
echo "" >> "$TMPFILE"

# 按序号读取所有分片
files=($(ls "$INDIR"/[0-9][0-9][0-9][0-9].md 2>/dev/null | sort))

if (( ${#files[@]} == 0 )); then
    echo "错误: $INDIR/ 中没有找到分片文件"
    exit 1
fi

prev_last_line=""
prev_last_nonempty=""
first_file=true
merged_content=()

for ((idx=0; idx < ${#files[@]}; idx++)); do
    f="${files[idx]}"
    mapfile -t chunk < "$f"

    # 跳过空文件开头的空行
    start=0
    while (( start < ${#chunk[@]} )) && [[ -z "${chunk[start]// }" ]]; do
        ((start++))
    done

    for ((j=start; j < ${#chunk[@]}; j++)); do
        line="${chunk[j]}"

        # 跨文件断句修复
        if ! $first_file && [[ -n "$prev_last_nonempty" ]]; then
            # 上一文件以逗号/分号结尾 → 合并为一段
            if [[ "$prev_last_nonempty" =~ [，,；\;]$ ]] && [[ -n "$(echo "$line" | tr -d ' ')" ]]; then
                # 移除上一行末尾，与当前行合并
                merged_content[-1]="${merged_content[-1]}${line}"
                prev_last_nonempty="$line"
                continue
            fi

            # 上一文件以独立 – 结尾 → 移除
            if [[ "$prev_last_nonempty" =~ ^[-–—]+$ ]] || [[ "$prev_last_nonempty" =~ ^[-–—]$ ]]; then
                unset 'merged_content[-1]'
            fi

            # 下一文件以列表项开头，上一行非句末 → 回溯
            line_starts_list=""
            if echo "$line" | grep -qE '^[a-zA-Z]\)'; then line_starts_list=1; fi
            if echo "$line" | grep -qE '^[0-9]+[.)]'; then line_starts_list=1; fi
            if [[ -n "$line_starts_list" ]]; then
                if [[ ! "$prev_last_nonempty" =~ [。！？]$ ]]; then
                    # 不额外插入空行，紧接
                    :
                fi
            fi
        fi

        merged_content+=("$line")
        if [[ -n "${line// }" ]]; then
            prev_last_nonempty="$line"
        fi
    done

    # 文件间默认加一个空行（断句修复可能已移除）
    if (( idx < ${#files[@]} - 1 )); then
        last_line="${merged_content[-1]}"
        if [[ -n "${last_line// }" ]]; then
            merged_content+=("")
        fi
    fi

    first_file=false
done

# 写入合并内容（先输出空行避免紧接 YAML）
echo "" >> "$TMPFILE"

# 格式转换：*文本* → > 文本（仅对以 * 开头且以 * 结尾的独立行，不含 ** 加粗）
for ((i=0; i < ${#merged_content[@]}; i++)); do
    line="${merged_content[i]}"

    # *诗句/引文* → > 诗句（行末加两个空格）
    if [[ "$line" =~ ^\*[^*].*[^*]\*$ ]]; then
        content="${line#\*}"
        content="${content%\*}"
        merged_content[i]="> ${content}  "
        continue
    fi

    # <img src="..."> → ![](media/...)
    img_regex='<img[^>]*src="([^"]+)"[^>]*>'
    if [[ "$line" =~ $img_regex ]]; then
        img_path="${BASH_REMATCH[1]}"
        filename=$(basename "$img_path")
        merged_content[i]="![](${filename})"
        continue
    fi

    # ![...](Images/...) → ![...](media/...)
    if [[ "$line" =~ ^!\[.*\]\(Images/ ]]; then
        merged_content[i]=$(echo "$line" | sed 's|(Images/|(media/|g')
        continue
    fi
done

printf '%s\n' "${merged_content[@]}" >> "$TMPFILE"

# 输出
mv "$TMPFILE" "$OUTFILE"
line_count=$(wc -l < "$OUTFILE")
echo "完成：$OUTFILE ($line_count 行)"
