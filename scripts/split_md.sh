#!/usr/bin/env bash
# split_md.sh — 将 markdown 文件智能切片到 split/ 目录
# 用法：bash split_md.sh <输入.md> [每片行数] [输出目录]
# 默认：每片 20 行，输出到 split/

set -euo pipefail

INPUT="${1:?用法: $0 <输入.md> [每片行数] [输出目录]}"
LINES_PER_CHUNK="${2:-20}"
OUTDIR="${3:-split}"

if [[ ! -f "$INPUT" ]]; then
    echo "错误: 文件不存在: $INPUT"
    exit 1
fi

echo "[DEBUG] split_md.sh start: INPUT=$INPUT LINES_PER_CHUNK=$LINES_PER_CHUNK OUTDIR=$OUTDIR"
mkdir -p "$OUTDIR"
# 清空已有分片
rm -f "$OUTDIR"/????.md

# 判断是否为"好"断点
is_good_break() {
    local line="$1"
    # 空行 = 自然段落结束
    [[ -z "$line" ]] && return 0
    # 以句号、感叹号、问号结尾 = 句子结束
    [[ "$line" =~ [。！？]$ ]] && return 0
    # 以英文句号结尾后跟空行或下一行为非空
    [[ "$line" =~ \.$ ]] && return 0
    return 1
}

is_bad_break() {
    local line="$1"
    local next_line="$2"
    # 空行后是图片 — 不行，图片不能和上文分离
    if [[ -z "$line" ]] && ( [[ "$next_line" =~ ^!\[ ]] || [[ "$next_line" =~ ^\<img ]] ); then
        return 0
    fi
    # 当前行在 ** 中间（奇数个 **）
    local asterisks
    asterisks=$(echo "$line" | grep -co '\*\*')
    if (( asterisks % 2 != 0 )); then
        return 0
    fi
    return 1
}

# 读取所有行
mapfile -t lines < "$INPUT"
total_lines=${#lines[@]}

chunk_num=1
chunk_lines=()
i=0

write_chunk() {
    local fname
    fname=$(printf "%s/%04d.md" "$OUTDIR" "$chunk_num")
    printf '%s\n' "${chunk_lines[@]}" > "$fname"
    echo "  写入 $fname (${#chunk_lines[@]} 行)"
    chunk_num=$((chunk_num+1))
    chunk_lines=()
}

while (( i < total_lines )); do
    remaining=$(( total_lines - i ))

    # 若剩余行数 < 目标行数，全部摄入后结束
    if (( remaining <= LINES_PER_CHUNK + 5 )); then
        while (( i < total_lines )); do
            chunk_lines+=("${lines[i]}")
            i=$((i+1))
        done
        break
    fi

    # 目标切点 = i + LINES_PER_CHUNK
    cut_point=$(( i + LINES_PER_CHUNK - 1 ))

    # 向后扫描 5 行找更好断点
    best_point=$cut_point
    for offset in $(seq 0 5); do
        candidate=$(( cut_point + offset ))
        if (( candidate >= total_lines )); then
            break
        fi
        next_idx=$(( candidate + 1 ))
        next_line=""
        if (( next_idx < total_lines )); then
            next_line="${lines[next_idx]}"
        fi
        if is_good_break "${lines[candidate]}" && ! is_bad_break "${lines[candidate]}" "$next_line"; then
            best_point=$candidate
            break
        fi
    done

    # 若没找到，向前扫描
    if (( best_point == cut_point )); then
        for offset in $(seq 1 5); do
            candidate=$(( cut_point - offset ))
            if (( candidate <= i )); then
                break
            fi
            next_idx=$(( candidate + 1 ))
            next_line=""
            if (( next_idx < total_lines )); then
                next_line="${lines[next_idx]}"
            fi
            if is_good_break "${lines[candidate]}" && ! is_bad_break "${lines[candidate]}" "$next_line"; then
                best_point=$candidate
                break
            fi
        done
    fi

    # 摄入行
    while (( i <= best_point && i < total_lines )); do
        chunk_lines+=("${lines[i]}")
        i=$((i+1))
    done

    write_chunk
done

# 写入最后一批（如有）
if [[ ${#chunk_lines[@]} -gt 0 ]]; then
    write_chunk
fi

echo "[DEBUG] split_md.sh done: $((chunk_num - 1)) chunks, total_lines=$total_lines, OUTDIR=$OUTDIR"
