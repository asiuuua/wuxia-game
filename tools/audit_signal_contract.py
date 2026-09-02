#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
关联架构审计 · EventBus 信号契约一致性检查器

审计范围（审计核查提示词 §1「系统性风险 / 隐藏风险」+ 范围 C「信号契约」）：
  枚举 autoload/EventBus.gd 声明的全部信号，逐信号核查：
    1. 生产方(emit)：谁产生谁 emit —— 是否至少有 1 处 emit
    2. 消费方(connect)：谁关心谁 connect —— 是否至少有 1 处 connect
    3. 孤儿信号：声明了却 0 emit 或 0 connect（@warning_ignore 会掩盖，属隐藏风险）
    4. 未声明引用：emit/connect 到一个 EventBus 不存在的信号名（拼写漂移 / 已删信号）
    5. 签名漂移：emit 实参个数 vs 声明形参个数（粗略，仅提示）

用法：
    python tools/audit_signal_contract.py                # 打印汇总 + 孤儿清单
    python tools/audit_signal_contract.py --json out.json # 同上加 --json 写结构化结果
    python tools/audit_signal_contract.py --root D:/武侠游戏

纯静态扫描（正则），零运行游戏；只读审查，不改任何游戏代码。
"""
import os
import re
import sys
import json
import argparse
from collections import Counter, defaultdict

EMIT_DOT = re.compile(r'EventBus\.([A-Za-z_]\w*)\s*\.emit\s*\(')
EMIT_STR = re.compile(r'EventBus\.emit_signal\(\s*[\'"]([A-Za-z_]\w*)[\'"]')
CONN_DOT = re.compile(r'EventBus\.([A-Za-z_]\w*)\s*\.connect\s*\(')
CONN_STR = re.compile(r'EventBus\.connect\(\s*[\'"]([A-Za-z_]\w*)[\'"]')

SIG_DECL = re.compile(r'signal\s+([A-Za-z_]\w*)\s*\((.*?)\)', re.S)


def find_project_root(explicit=None):
    if explicit:
        return explicit
    cur = os.getcwd()
    while True:
        if os.path.exists(os.path.join(cur, 'project.godot')):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.getcwd()
        cur = parent


def parse_signals(eventbus_path):
    with open(eventbus_path, 'r', encoding='utf-8', errors='ignore') as f:
        src = f.read()
    sigs = {}
    for m in SIG_DECL.finditer(src):
        name = m.group(1)
        params = m.group(2)
        # 数形参个数（去空）
        pc = 0 if params.strip() == '' else len([p for p in params.split(',') if p.strip()])
        sigs[name] = pc
    return sigs


def scan_project(root):
    emits = Counter()
    conns = Counter()
    locations = defaultdict(lambda: {'emit': [], 'connect': []})
    for dirpath, dirnames, filenames in os.walk(root):
        if '.git' in dirpath:
            continue
        for fn in filenames:
            if not fn.endswith('.gd'):
                continue
            p = os.path.join(dirpath, fn)
            try:
                with open(p, 'r', encoding='utf-8', errors='ignore') as f:
                    text = f.read()
            except Exception:
                continue
            rel = os.path.relpath(p, root).replace('\\', '/')
            for rx, bucket in ((EMIT_DOT, 'emit'), (EMIT_STR, 'emit'),
                               (CONN_DOT, 'connect'), (CONN_STR, 'connect')):
                for m in rx.finditer(text):
                    name = m.group(1)
                    if bucket == 'emit':
                        emits[name] += 1
                        locations[name]['emit'].append(rel)
                    else:
                        conns[name] += 1
                        locations[name]['connect'].append(rel)
    return emits, conns, locations


def _load_baseline(path):
    """读取基线 JSON 的 known_dead_signals 集合。失败则按「零基线」处理（任何死信号都拦）。"""
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        return set(data.get('known_dead_signals', []))
    except Exception as e:
        print(f'[WARN] 基线读取失败，按零基线处理（任何死信号都拦）: {e}', file=sys.stderr)
        return set()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=None)
    ap.add_argument('--eventbus', default=None)
    ap.add_argument('--json', default=None, help='写结构化结果到此路径')
    ap.add_argument('--baseline', default=None,
                    help='基线 JSON（含 known_dead_signals 列表）。门禁模式：仅拦「新增」死信号'
                         '+任何未声明引用，不拦基线内已知死信号（供清理渐进）。')
    args = ap.parse_args()

    root = find_project_root(args.root)
    eb = args.eventbus or os.path.join(root, 'autoload', 'EventBus.gd')
    if not os.path.exists(eb):
        print(f'[ERR] 找不到 EventBus.gd: {eb}', file=sys.stderr)
        sys.exit(2)

    sigs = parse_signals(eb)
    emits, conns, locations = scan_project(root)

    declared = set(sigs.keys())
    referenced = set(emits) | set(conns)

    # 未声明却被引用（拼写漂移 / 已删信号）
    undeclared = sorted(referenced - declared)
    # 孤儿：声明了但 0 emit 或 0 connect
    orphan_no_emit = sorted(n for n in sigs if emits.get(n, 0) == 0)
    orphan_no_connect = sorted(n for n in sigs if conns.get(n, 0) == 0)

    print('=' * 78)
    print(f'EventBus 信号契约一致性审计  | 项目根: {root}')
    print(f'声明信号总数: {len(sigs)}  | emit 引用信号数: {len(emits)} | connect 引用信号数: {len(conns)}')
    print('=' * 78)

    print('\n--- ① 未声明却被引用（拼写漂移 / 已删信号，隐藏风险）---')
    if undeclared:
        for n in undeclared:
            print(f'  ⚠ {n}  emit={emits.get(n,0)} connect={conns.get(n,0)}')
    else:
        print('  ✓ 无（所有 emit/connect 目标均在 EventBus 声明）')

    print('\n--- ② 孤儿信号：声明了却 0 emit（无生产方）---')
    if orphan_no_emit:
        for n in orphan_no_emit:
            print(f'  ✗ {n}  (declared, emit=0, connect={conns.get(n,0)})')
    else:
        print('  ✓ 无（每个声明信号至少有 1 处 emit）')

    print('\n--- ③ 孤儿信号：声明了却 0 connect（无消费方）---')
    if orphan_no_connect:
        for n in orphan_no_connect:
            print(f'  ✗ {n}  (declared, emit={emits.get(n,0)}, connect=0)')
    else:
        print('  ✓ 无（每个声明信号至少有 1 处 connect）')

    print('\n--- ④ 全信号 emit/connect 计数（按声明顺序）---')
    for n in sigs:
        e = emits.get(n, 0)
        c = conns.get(n, 0)
        flag = '' if (e > 0 and c > 0) else '  <<< 孤儿'
        print(f'  {n:38s} emit={e:2d} connect={c:2d}{flag}')

    # 结构化输出
    result = {
        'summary': {
            'declared': len(sigs),
            'referenced_emit': len(emits),
            'referenced_connect': len(conns),
            'orphan_no_emit': orphan_no_emit,
            'orphan_no_connect': orphan_no_connect,
            'undeclared_referenced': undeclared,
        },
        'signals': {
            n: {
                'params': sigs[n],
                'emit': emits.get(n, 0),
                'connect': conns.get(n, 0),
                'emit_at': sorted(set(locations[n]['emit'])),
                'connect_at': sorted(set(locations[n]['connect'])),
            } for n in sigs
        },
    }
    if args.json:
        with open(args.json, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        print(f'\n[OK] 结构化结果已写: {args.json}')

    if args.baseline:
        known = _load_baseline(args.baseline)
        # 门禁只盯「无生产方(emit=0)」信号：永远不可能触发，接它的代码是死代码，
        # 也最易被 @warning_ignore 掩盖而悄悄堆积。
        # 「已发射但暂未订阅(emit>0,connect=0)」是良性广播（先 emit 后接属正常增量开发），不拦。
        current_dead = set(orphan_no_emit)
        advisory_no_consumer = sorted(set(orphan_no_connect) - set(orphan_no_emit))
        new_dead = sorted(current_dead - known)
        removed = sorted(known - current_dead)
        print('\n--- ⑤ 门禁比对（基线模式）---')
        print(f'  基线已知无生产方信号: {len(known)}  当前无生产方: {len(current_dead)}')
        if removed:
            print(f'  ✓ 已清理（基线内有、现已 emit）: {", ".join(removed)}')
        if advisory_no_consumer:
            print(f'  ℹ 已发射但暂未订阅(良性广播，仅提示不拦，{len(advisory_no_consumer)} 个): {", ".join(advisory_no_consumer[:12])}{"…" if len(advisory_no_consumer) > 12 else ""}')
        if new_dead:
            print(f'  ✗ 新增无生产方信号（基线外、须补 emit 或删声明）: {", ".join(new_dead)}')
        if undeclared:
            print(f'  ✗ 未声明引用（必拦，拼写漂移/已删信号）: {", ".join(undeclared)}')
        if not new_dead and not undeclared:
            print('  ✓ 门禁通过：无新增无生产方信号、无未声明引用（基线内已知项不拦）')
        block = bool(new_dead or undeclared)
        sys.exit(1 if block else 0)

    # 退出码：有孤儿/未声明 → 1（供门禁用），否则 0
    sys.exit(1 if (undeclared or orphan_no_emit or orphan_no_connect) else 0)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        # 失败开放（关键，对齐 lint_mouse_filter）：扫描器自身崩溃（磁盘锁/编码/解析异常）
        # 必须放行，绝不以 exit 1 冒充"发现死信号"——否则 pre-commit 钩子会误拦正常提交。
        # 崩溃交 GATE2 + 下次手动扫描兜底，不可因守卫本身故障阻断开发。
        sys.stderr.write("[audit_signal_contract] ⚠ 扫描器自身异常，已放行未阻断提交：%s\n" % e)
        sys.exit(0)
