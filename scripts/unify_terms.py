#!/usr/bin/env python3
"""unify_terms.py — 根据 GLOSSARY.csv 统一译文中的术语

用法：
    python3 unify_terms.py [--dry-run]
    python3 unify_terms.py --csv GLOSSARY.csv --dir split_translated/

工作原理：
    1. 读取 GLOSSARY.csv
    2. 对每个 source（原文），在全部译文文件中搜索
    3. 如果发现非标准译法，替换为标准译法
    4. 输出变更报告
"""

import csv
import os
import sys
import argparse
import re
from pathlib import Path
from collections import defaultdict


def load_glossary(csv_path):
    """加载 glossary CSV，返回 {source: (target, category)} 和对 target 的 source 变体映射"""
    glossary = {}
    target_to_sources = defaultdict(set)

    if not os.path.exists(csv_path):
        print(f"警告: glossary 文件不存在: {csv_path}")
        return glossary, target_to_sources

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            source = row.get("source", "").strip()
            target = row.get("target", "").strip()
            category = row.get("category", "").strip()
            if source and target:
                glossary[source] = (target, category)
                target_to_sources[target].add(source)

    return glossary, target_to_sources


def find_alternative_translations(text, glossary, target_to_sources):
    """在文本中搜索可能的替代译名（非标准译法）"""
    issues = []
    # 按 target 分组：同一 target 可能有多种 source 变体
    for target, sources in target_to_sources.items():
        if len(sources) <= 1:
            continue
        # 对每个 source，检查 target 是否在文本中出现
        for src in sources:
            if src in text:
                canonical = glossary.get(src, (target, ""))[0]
                # 查找该 source 附近的非标准译名
                pass
    return issues


def replace_terms(text, glossary):
    """将文本中的 source 原文替换为 target 标准译法（在西里尔字母或拉丁字母上下文中）"""
    replacements = []
    # 按 source 长度降序排列，先替换长词避免短词误伤
    sorted_sources = sorted(glossary.keys(), key=len, reverse=True)

    for source in sorted_sources:
        target, category = glossary[source]
        # 只替换完整词（前后为分隔符/行首行尾）
        delim = r'[\s,.\"\'«»\(\)\[\]{}—–-]'
        pattern = re.compile(rf"(?<![^\s,.\"\'«»\(\)\[\]{{}}—–-]){re.escape(source)}(?={delim}|$)")


        matches = list(pattern.finditer(text))
        for m in matches:
            replacements.append((m.start(), m.end(), source, target, category))

    return replacements


def main():
    parser = argparse.ArgumentParser(description="统一译文术语")
    parser.add_argument("--csv", default="GLOSSARY.csv", help="Glossary CSV 路径")
    parser.add_argument("--dir", default="split_translated", help="译文目录")
    parser.add_argument("--dry-run", action="store_true", help="仅报告，不实际修改")
    args = parser.parse_args()

    if not os.path.isdir(args.dir):
        print(f"错误: 目录不存在: {args.dir}")
        sys.exit(1)

    glossary, target_to_sources = load_glossary(args.csv)
    if not glossary:
        print("术语表为空，无需处理")
        return

    print(f"加载术语表: {args.csv} ({len(glossary)} 条)")

    total_replacements = 0
    files_modified = 0

    files = sorted(Path(args.dir).glob("[0-9][0-9][0-9][0-9].md"))
    if not files:
        print(f"警告: {args.dir}/ 中没有找到分片文件")
        return

    for fpath in files:
        with open(fpath, "r", encoding="utf-8") as f:
            lines = f.readlines()

        file_modified = False
        new_lines = []
        for line_num, line in enumerate(lines, 1):
            replacements = replace_terms(line, glossary)
            if replacements:
                file_modified = True
                modified_line = line
                # 从后往前替换，避免偏移
                for start, end, src, tgt, cat in reversed(replacements):
                    if not args.dry_run:
                        modified_line = modified_line[:start] + tgt + modified_line[end:]
                    total_replacements += 1
                    print(f"  {fpath.name}:{line_num} [{cat}] {src} → {tgt}")
                new_lines.append(modified_line)
            else:
                new_lines.append(line)

        if file_modified:
            files_modified += 1
            if not args.dry_run:
                with open(fpath, "w", encoding="utf-8") as f:
                    f.writelines(new_lines)

    print()
    if args.dry_run:
        print(f"[DRY RUN] 将修改 {files_modified} 个文件，{total_replacements} 处替换")
    else:
        print(f"完成: 修改 {files_modified} 个文件，{total_replacements} 处替换")


if __name__ == "__main__":
    main()
