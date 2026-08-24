#!/usr/bin/env python3
"""coverage_audit.py — G1 符号覆盖闸
Kotlin 源符号(fun/class/object/val/const) vs Swift 对应符号,diff 未映射项。
用法: python3 scripts/coverage_audit.py [--android-dir PATH] [--ios-dir PATH]
退出码: 0=零未解释项(按 FILE_MAPPING 的批次范围);2=有未映射符号
"""
import re, sys, os, json, argparse

ANDROID = os.path.expanduser('~/Desktop/sleepy/app/src/main/java/com/lingion/sleepy')
IOS = os.path.expanduser('~/Desktop/sleepy-ios')

def kotlin_symbols(path):
    """返回 {kind: [names]} — 顶层与成员 fun/class/object/interface/val/const"""
    src = open(path, encoding='utf-8').read()
    out = {'fun': [], 'class': [], 'object': [], 'interface': [], 'val': [], 'const': [], 'enum': []}
    for m in re.finditer(r'^\s*(?:@\w+\s+)*(?:private\s+|internal\s+|public\s+)?(?:suspend\s+)?(fun|class|object|interface|enum class)\s+[`]?(\w+)', src, re.M):
        kind, name = m.group(1), m.group(2)
        if kind == 'fun':
            out['fun'].append(name)
        elif kind == 'enum class':
            out['enum'].append(name)
        else:
            out[kind].append(name)
    for m in re.finditer(r'^\s*(?:private\s+|internal\s+)?(?:const\s+)?val\s+(\w+)', src, re.M):
        out['val'].append(m.group(1))
    return {k: sorted(set(v)) for k, v in out.items() if v}

def swift_symbols(path):
    src = open(path, encoding='utf-8').read()
    out = {'func': [], 'class': [], 'struct': [], 'enum': [], 'var': [], 'let': []}
    for m in re.finditer(r'^\s*(?:private\s+|internal\s+|public\s+|open\s+|@(?:discardableResult|objc)\s+)*(?:static\s+|class\s+)?(func|class|struct|enum)\s+[`]?(\w+)', src, re.M):
        kind, name = m.group(1), m.group(2)
        out[{'func':'func','class':'class','struct':'struct','enum':'enum'}[kind]].append(name)
    for m in re.finditer(r'^\s*(?:private\s+|internal\s+|public\s+)?(?:static\s+)?(?:let|var)\s+(\w+)', src, re.M):
        out['let'].append(m.group(1))
    return {k: sorted(set(v)) for k, v in out.items() if v}

def kt_to_swift_name(name):
    """Kotlin camelCase → Swift 同名(移植规范: 保留 camelCase)"""
    return name

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--android-dir', default=ANDROID)
    ap.add_argument('--ios-dir', default=IOS)
    ap.add_argument('--json', action='store_true', help='输出 JSON 而非文本')
    ap.add_argument('--scope', help='只审计指定 Kotlin 子路径(如 data/util),默认全部')
    args = ap.parse_args()

    # 收集 Swift 全部符号(跨文件全局池)
    swift_pool = set()
    for root, _, files in os.walk(args.ios_dir):
        for f in files:
            if f.endswith('.swift'):
                for syms in swift_symbols(os.path.join(root, f)).values():
                    swift_pool.update(syms)

    unmapped = []
    total = 0
    for root, _, files in os.walk(args.android_dir):
        rel = os.path.relpath(root, args.android_dir)
        if args.scope and not rel.startswith(args.scope):
            continue
        for f in files:
            if not f.endswith('.kt'):
                continue
            path = os.path.join(root, f)
            syms = kotlin_symbols(path)
            for kind, names in syms.items():
                for n in names:
                    total += 1
                    if kt_to_swift_name(n) not in swift_pool:
                        unmapped.append(f'{rel}/{f}:{kind}:{n}')

    if args.json:
        print(json.dumps({'total': total, 'unmapped_count': len(unmapped), 'unmapped': unmapped}, ensure_ascii=False, indent=1))
    else:
        print(f'Kotlin 符号总数: {total}')
        print(f'未映射: {len(unmapped)}')
        for u in unmapped[:80]:
            print(f'  ✗ {u}')
        if len(unmapped) > 80:
            print(f'  ... 共 {len(unmapped)} 项')
    sys.exit(2 if unmapped else 0)

if __name__ == '__main__':
    main()
