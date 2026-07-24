#!/usr/bin/env python3
"""
PDF → Markdown 清洗脚本 (krauze-mexico)
处理: 页眉移除、断词修复、段落重建、标题识别
"""

import re, sys

# ── 标题映射 ──

# 所有已知标题(原始英文/中文对照)
TITLE_ENTRIES = [

    # 前置
    ('PREFACE', '## 前言'),
    ('SOURCES AND ACKNOWLEDGMENTS', '## 资料来源与致谢'),
    ('HISTORICAL CHRONOLOGY', '## 历史年表'),
    ('INTRODUCTION', '## 引言：过去、现在与未来'),

    # Part
    ('THE WEIGHT OF THE PAST', '## 第一部：历史的重量'),
    ('CENTURY OF CAUDILLOS', '## 第二部：考迪罗的世纪'),
    ('THE REVOLUTION', '## 第三部：革命'),
    ('THE MODERN STATE', '## 第四部：现代国家'),
    ('PAST AND FUTURE', '## 第五部：过去与未来'),
    ('PAST AND FUTURE: THE DECLINE OF THE SYSTEM', '## 第五部：过去与未来'),

    # 章节
    ('THE CHILDREN OF CUAUHTÉMOC', '## 第一章：夸乌特莫克的后代'),
    ('THE LEGACY OF CORTÉS', '## 第二章：科尔特斯的遗产'),
    ('THE MESTIZO FAMILY', '## 第三章：梅斯蒂索家族'),
    ('THE SPANISH CROWN', '## 第四章：西班牙王权'),
    ('THE MOTHER CHURCH', '## 第五章：母教会'),
    ('THE INSURGENT PRIESTS', '## 第六章：起义的教士们'),
    ('THE COLLAPSE OF THE CREOLES', '## 第七章：克里奥尔人的崩溃'),
    ('THE INDIAN SHEPHERD AND THE AUSTRIAN ARCHDUKE', '## 第八章：印第安牧羊人与奥地利大公'),
    ('THE TRIUMPH OF THE MESTIZO', '## 第九章：梅斯蒂索人的胜利'),
    ('FRANCISCO I. MADERO', '## 第十章：弗朗西斯科·I·马德罗：民主的使徒'),
    ('EMILIANO ZAPATA', '## 第十一章：埃米利亚诺·萨帕塔：天生的无政府主义者'),
    ('FRANCISCO VILLA', '## 第十二章：弗朗西斯科·比利亚：天使与铁腕之间'),
    ('VENUSTIANO CARRANZA', '## 第十三章：贝努斯蒂亚诺·卡兰萨：民族主义与宪法'),
    ('ÁLVARO OBREGÓN', '## 第十四章：阿尔瓦罗·奥夫雷贡：死亡与将军'),
    ('PLUTARCO ELÍAS CALLES', '## 第十五章：普鲁塔尔科·埃利亚斯·卡列斯：从根基改革'),
    ('LÁZARO CÁRDENAS', '## 第十六章：拉萨罗·卡德纳斯：传教士将军'),
    ('MANUEL ÁVILA CAMACHO', '## 第十七章：曼努埃尔·阿维拉·卡马乔：绅士总统'),
    ('MIGUEL ALEMÁN', '## 第十八章：米格尔·阿莱曼：商人总统与体制'),
    ('ADOLFO RUIZ CORTINES', '## 第十九章：阿道弗·鲁伊斯·科尔蒂内斯：行政官'),
    ('ADOLFO LÓPEZ MATEOS', '## 第二十章：阿道弗·洛佩斯·马特奥斯：演说家'),
    ('GUSTAVO DÍAZ ORDAZ', '## 第二十一章：古斯塔沃·迪亚斯·奥尔达斯：秩序的捍卫者'),
    ('THE PREACHER', '## 第二十二章：布道者'),
    ('THE GAMBLER', '## 第二十三章：赌徒'),
    ('LOST OPPORTUNITIES', '## 第二十四章：失去的机会'),
    ('THE MAN WHO WOULD BE KING', '## 第二十五章：想当国王的人'),
    ('THE THEATER OF HISTORY', '## 第二十六章：历史的剧场'),
]

# Spaceless 映射: 移除所有空格 + 大写 → 中文标题
def to_key(s):
    s = s.upper()
    # OCR错误修正（优先于字符规范化）
    s = s.replace('CBOWN', 'CROWN')
    s = s.replace('INSUBGENT', 'INSURGENT')
    s = s.replace('CORUÑES', 'CORTINES')
    s = s.replace('CORUNES', 'CORTINES')
    s = s.replace('YENUSTIANO', 'VENUSTIANO')
    s = s.replace('LÁZAEO', 'LÁZARO')
    s = s.replace('LAZAEO', 'LÁZARO')  # will get deaccented below
    s = s.replace('CORUÑES', 'CORTINES')
    # 移除重音符号
    s = s.replace('Á', 'A').replace('É', 'E').replace('Í', 'I').replace('Ó', 'O').replace('Ú', 'U')
    s = s.replace('Ü', 'U').replace('Ñ', 'N')
    # 移除分隔符
    for ch in " .',:;!?":
        s = s.replace(ch, '')
    return s

TITLE_MAP = {}
for eng, chn in TITLE_ENTRIES:
    TITLE_MAP[to_key(eng)] = chn
    # 也添加一些变体
    if "'" in eng:
        TITLE_MAP[to_key(eng.replace("'", ''))] = chn


def match_title(stripped):
    """尝试匹配标题,返回(中文标题,是否匹配)"""
    key = to_key(stripped)
    if key in TITLE_MAP:
        return TITLE_MAP[key]
    return None


# 插图清单
ILLUSTRATIONS = [
    "Centenary Independence Parade, Mexico City, 1910",
    "Cuauhtémoc's martyrdom", "Moctezuma", "Hernán Cortés",
    "Our Lady of Guadalupe", "Miguel Hidalgo y Costilla",
    "José María Morelos y Pavón, 1814", "Agustín de Iturbide, 1822",
    "Antonio López de Santa Anna, 1853", "Benito Juárez",
    "Maximilian von Hapsburg, Emperor of Mexico, 1866", "Empress Carlota, 1867",
    "Porfirio Díaz, 1864", "Porfirio Díaz, 1905",
    "Francisco I. Madero and his wife, 1911", "Emiliano Zapata, 1912",
    "Zapatista soldiers, circa 1912", "Zapata and Villa entering Mexico City, 1914",
    "Zapata with Villa sitting in the Presidential Chair, 1914",
    "Francisco Villa, 1912", "Felipe Ángeles, 1915",
    "Venustiano Carranza with children, 1917", "Álvaro Obregón, 1921",
    "Plutarco Elías Calles, 1925", "Lázaro Cárdenas, 1932",
    "President Cárdenas with the Indians, circa 1936",
    "End of the Ballad, Diego Rivera, 1928",
    "The Trench, José Clemente Orozco, 1922-1926",
    "Manuel Ávila Camacho with his brother Maximino, 1939",
    "Miguel Alemán, 1948", "The new urbanization of Alemán",
    "President Alemán visits a factory, 1950", "Daniel Cosío Villegas, 1953",
    "Adolfo Ruiz Cortines, 1952", "Adolfo López Mateos", "Gustavo Díaz Ordaz",
    "Demonstration of students and teachers at the University, 1968",
    "Tanks in the Plaza de las Tres Culturas, Tlatelolco, October 2, 1968",
    "Bullet holes in window overlooking the Plaza of Tlatelolco, October 3, 1968",
    "Luis Echeverría",
    "Los Halcones, government provocateurs dressed as students, Corpus Christi Thursday, 1971",
    "José López Portillo", "Miguel de la Madrid Hurtado", "Carlos Salinas de Gortari",
    'Subcommander Marcos, Rafael Sebastián Guillén Vicente',
    "Luis Donaldo Colosio", "Ernesto Zedillo Ponce de León, 1995",
]


def is_book_title_variant(text):
    t = text.upper().replace(' ', '').replace(':', '')
    return 5 < len(t) < 30 and t.startswith('MEX') and 'BIOG' in t and 'POW' in t


def clean_pdf_text(input_path, output_path):
    with open(input_path, 'r', encoding='utf-8') as f:
        text = f.read()

    lines = text.splitlines(keepends=True)

    # ── 第1步: form feed移除 ──
    lines = [line.replace('\x0c', '') for line in lines]

    # ── 第2步: 页眉移除 + 行分类 ──
    cleaned = []
    removed = 0
    seen_titles = set()  # 追踪已经出现过的标题(用于去重)

    for line in lines:
        stripped = line.strip()
        if not stripped:
            cleaned.append('\n')
            continue

        # 书眉(书名行)
        if is_book_title_variant(stripped):
            removed += 1
            continue

        # 偶数页页眉: "数字 + 书眉"
        m = re.match(r'^(\d{1,3})\s+(.+)$', stripped)
        if m and is_book_title_variant(m.group(2).strip()):
            removed += 1
            continue

        # 页眉: "文本 + 3+空格 + 数字" (奇数页)
        m = re.match(r'^(.+?)\s{3,}(\d{1,3})$', stripped)
        if m:
            title_part = m.group(1).strip()
            page_num = int(m.group(2))
            title_key = to_key(title_part)

            # 检查是否为已知章节/Part标题
            mapped = match_title(title_part)
            if mapped and mapped not in seen_titles:
                # 首次出现 → 章节标题(含页码)
                seen_titles.add(mapped)
                cleaned.append(mapped + '\n')
                continue
            if mapped and mapped in seen_titles:
                # 重复出现 → 页眉,移除
                removed += 1
                continue

            if title_part.isupper() and len(title_part) > 3:
                # 未知ALL CAPS + 页码 → 可能是章节标题
                seen_titles.add(stripped)
                cleaned.append(title_part + '\n')
                continue
            removed += 1
            continue

        # 页眉: "文本 + 3+空格 + 罗马数字" (前置页眉)
        m = re.match(r'^(.+?)\s{4,}([ivxlcdm]+)$', stripped, re.I)
        if m:
            title_part = m.group(1).strip()
            mapped = match_title(title_part)
            if mapped and mapped not in seen_titles:
                seen_titles.add(mapped)
                cleaned.append(mapped + '\n')
                continue
            if mapped and mapped in seen_titles:
                removed += 1
                continue
            if title_part.isupper() and len(title_part) > 3:
                seen_titles.add(stripped)
                cleaned.append(title_part + '\n')
                continue
            removed += 1
            continue

        # 前置页眉: "罗马数字 + 空格 + 文本"
        m = re.match(r'^([ivxlcdm]+)\s{2,}(.+)$', stripped, re.I)
        if m:
            sec_part = m.group(2).strip()
            if is_book_title_variant(sec_part):
                removed += 1
                continue
            mapped = match_title(sec_part)
            if mapped and mapped not in seen_titles:
                seen_titles.add(mapped)
                cleaned.append(mapped + '\n')
                continue
            if mapped and mapped in seen_titles:
                removed += 1
                continue
            if sec_part.isupper() and len(sec_part) > 2:
                seen_titles.add(stripped)
                cleaned.append(sec_part + '\n')
                continue
            removed += 1
            continue

        # 纯数字行(页码)
        if re.match(r'^(\d{1,3}|[ivxlcdm]+)$', stripped, re.I) and len(stripped) <= 5:
            removed += 1
            continue

        # 插图目录项行 "(List of Illustrations 中的条目)"
        # 这些是前置材料中的列表,保持

        cleaned.append(stripped + '\n')

    print(f'  页眉移除: {removed}, 剩余: {len(cleaned)} 行')

    # ── 第3步: 标题识别(同时处理跨行标题) ──
    result = []
    i = 0

    while i < len(cleaned):
        line = cleaned[i]
        stripped = line.strip()
        next_stripped = cleaned[i+1].strip() if i+1 < len(cleaned) else ''

        # 尝试合并两行(跨行标题如 THE CHILDREN OF / CUAUHTÉMOC)
        if stripped.isupper() and len(stripped) > 2 and \
           next_stripped.isupper() and len(next_stripped) > 2:
            combined = stripped + ' ' + next_stripped
            mapped = match_title(combined)
            if mapped and mapped not in seen_titles:
                seen_titles.add(mapped)
                result.append(mapped + '\n\n')
                i += 2
                continue

        # 单行标题匹配
        if stripped.isupper() and len(stripped) > 2:
            mapped = match_title(stripped)
            if mapped and mapped not in seen_titles:
                seen_titles.add(mapped)
                result.append(mapped + '\n\n')
                i += 1
                continue
            if mapped and mapped in seen_titles:
                # 重复,跳过
                i += 1
                continue
            # ALL CAPS 但非已知标题(如地图标签): 转为Title Case
            result.append(stripped.lower().title() + '\n')
            i += 1
            continue

        result.append(line)
        i += 1

    lines = result

    # ── 第4步: 修复软连字符 + OCR ──
    text = ''.join(lines)
    text = re.sub(r'(\w)-\n(\w)', r'\1\2', text)
    text = text.replace('\u00ad', '')
    for old, new in {'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl',
                     'ﬀ': 'ff', 'Ĳ': 'IJ', 'ĳ': 'ij', 'œ': 'oe',
                     'Œ': 'OE'}.items():
        text = text.replace(old, new)
    text = text.replace('\u00a0', ' ')

    # ── 第5步: 段落重建 ──
    lines = text.splitlines(keepends=False)
    merged = []
    buffer = []

    def flush(buf, out):
        if not buf:
            return
        non_empty = [l.strip() for l in buf if l.strip()]
        if not non_empty:
            return
        para = ' '.join(non_empty)
        para = re.sub(r'  +', ' ', para)
        out.append(para + '\n\n')

    for line in lines:
        s = line.strip()
        if not s:
            flush(buffer, merged)
            buffer = []
        elif s.startswith('#'):
            flush(buffer, merged)
            merged.append(s + '\n\n')
            buffer = []
        else:
            buffer.append(line)

    flush(buffer, merged)
    text = ''.join(merged)

    # ── 第6步: 图片说明 ──
    lines = text.splitlines(keepends=False)
    img = []
    for line in lines:
        s = line.strip()
        if not s or s.startswith('#') or s.startswith('!['):
            img.append(line + '\n')
            continue
        for ill in ILLUSTRATIONS:
            if s == ill or s.startswith(ill) or ill.startswith(s):
                img.append(f'<!-- 图片: {ill} -->\n\n')
                break
        else:
            img.append(line + '\n')

    text = ''.join(img)
    text = re.sub(r'\n{4,}', '\n\n\n', text)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(text)

    out_lines = text.splitlines()
    headings = [l for l in out_lines if l.strip().startswith('#')]
    print(f'清洗完成:')
    print(f'  总行数: {len(out_lines)}, 非空行: {len([l for l in out_lines if l.strip()])}')
    print(f'  标题: {len(headings)}')
    for h in headings:
        print(f'  {h}')


if __name__ == '__main__':
    clean_pdf_text('_原始.txt', '_原始_clean.md')
