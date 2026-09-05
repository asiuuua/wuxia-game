# -*- coding: utf-8 -*-
"""id_validator.py — 16 图 CP-5 ID 层校验器（物理槽 GATE06，2026-09-06 Phase2 上线）

覆盖 Enforcement 三条（CP-5 五检之第②层）：
  CP-R01  ID 匹配 03 §3.3 冻结正则；存量以 tools/id_baseline.json 基线管理——
          基线外零容忍（FATAL）、基线内只减不增（消失=收敛，通报计数）。
  CP-R02  data/configs/_retired_ids.json 名单内 ID 再现 = 永不复用违约（FATAL，I-1 机器化）。
  CP-R10  同域实体 ID 唯一性：实体「定义」同域重复 = FATAL；跨域同名允许（local）。

定义/引用判定（2026-09-06 校正首跑 13 项误伤，依据实扫数据结构）：
  · 键 id 的值 = 定义候选；键 *_id / *_ids / skills 下的值 = 引用（勾挂、出怪表、导航跳转等）。
  · 对话分片（根对象含 lines 数组；含 regions/*/dialogs/）：根 id = dlg 域定义；
    行 id 属实体内部导航结构，不参与全局定义，仅做分片内唯一性检查
    （同分片行 id 重复 = 导航表互相覆盖，FATAL）。
  · 非分片文件：键 id 且包裹深度 ≤2（根实体 0 层、单层包裹表 2 层）= 定义；
    更深层 id（如 enemies[].abilities[].id 配重引用）= 引用。
  · 域：分片根 = dlg；其余取 ID 首段前缀（battle_xxx → battle；nv_xxx → nv）。
    分片根 id 按 NPC 命名（如 npc_village_chief）是对话定义，与演员表 NPC 实体
    跨域同名，允许（local）。

每条违规带 rule_id + file + id + 证据（05 图 VA-3）。规则来源全部为 JSON 数据
（基线/退役名单/正则），双端同源（05 VA-4）的 GDScript 侧消费待运行期接入。
用法：python tools/id_validator.py   （退出码 0=通过，1=违规）
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BASELINE = os.path.join(HERE, "id_baseline.json")
RETIRED = os.path.join(ROOT, "data", "configs", "_retired_ids.json")

# 附挂表：键 id 的值视为对外部域实体的引用（rel 路径 -> 被挂接域）。
ATTACHED = {
    "data/configs/bond/relations.json": "npc",
}

violations = []
notes = []


def load_json(p):
    return json.load(open(p, encoding="utf-8"))


def find_line(root, rel, val):
    try:
        text = open(os.path.join(root, rel), encoding="utf-8").read()
        idx = text.find('"' + val + '"')
        return text.count("\n", 0, idx) + 1 if idx >= 0 else 0
    except Exception:
        return 0


def main():
    base = load_json(BASELINE)
    pattern = re.compile(base["pattern"])
    exempt = set(base.get("exempt", []))
    baseline_set = {(v["file"], v["id"]) for v in base.get("violations", [])}
    retired = {r["id"] for r in load_json(RETIRED).get("retired", [])}

    scanned = []           # (rel, id, line) — CP-R01/02 扫描面（定义 + 全部引用）
    defs_by_domain = {}    # domain -> {id: [file,...]}（仅实体定义，CP-R10）
    line_ids_by_file = {}  # 分片文件 -> [行 id,...]（分片内唯一性）

    def scan(val, rel):
        if isinstance(val, str) and val:
            scanned.append((rel, val, find_line(ROOT, rel, val)))

    def define(val, rel, domain):
        if isinstance(val, str) and val:
            scanned.append((rel, val, find_line(ROOT, rel, val)))
            if pattern.match(val):
                defs_by_domain.setdefault(domain, {}).setdefault(val, []).append(rel)

    def walk(obj, rel, depth, in_shard=False):
        if isinstance(obj, dict):
            shard_root = isinstance(obj.get("lines"), list)
            for k, v in obj.items():
                if k == "id" and isinstance(v, str) and v:
                    if in_shard or shard_root:
                        if depth == 0:
                            define(v, rel, "dlg")            # 分片根 = 对话定义
                        else:
                            line_ids_by_file.setdefault(rel, []).append(v)
                            scan(v, rel)                      # 行 id = 内部导航
                    elif depth <= 2 and rel not in ATTACHED:
                        define(v, rel, v.split("_", 1)[0])    # 表条目 = 实体定义
                    else:
                        scan(v, rel)                          # 引用（深层 id / 附挂表键 id）
                elif k.endswith("_id") and isinstance(v, str):
                    scan(v, rel)
                elif isinstance(v, list) and (k.endswith("_ids") or k == "skills"):
                    for x in v:
                        scan(x, rel)
                else:
                    walk(v, rel, depth + 1, in_shard or shard_root)
        elif isinstance(obj, list):
            for v in obj:
                walk(v, rel, depth + 1, in_shard)

    cfg = os.path.join(ROOT, "data", "configs")
    for dirpath, dirnames, filenames in os.walk(cfg):
        dirnames[:] = [d for d in dirnames if d != "ui"]
        for fn in filenames:
            if not fn.endswith(".json") or fn == "_retired_ids.json":
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            try:
                walk(load_json(full), rel, 0)
            except Exception as e:
                violations.append(("CP-R01", rel, "-", "JSON 解析失败：%s" % e))

    seen = set()
    for rel, val, line in scanned:
        if (rel, val) in seen:
            continue
        seen.add((rel, val))
        if val in retired:
            violations.append(("CP-R02", rel, val, "退役名单内 ID 再现（I-1 永不复用）行%d" % line))
        if not pattern.match(val) and val not in exempt:
            if (rel, val) not in baseline_set:
                violations.append(("CP-R01", rel, val, "基线外 ID 违例（基线外零容忍）行%d" % line))

    # CP-R01 收敛通报（基线内有、现已不存在）
    found = {(rel, val) for rel, val, _ in scanned
             if not pattern.match(val) and val not in exempt}
    collapsed = baseline_set - found
    if collapsed:
        notes.append("CP-R01 基线收敛 %d 处（只减不增 ✓，可从 id_baseline.json 移除）" % len(collapsed))

    # CP-R10-a 同域实体跨文件重复定义
    for domain, ids in sorted(defs_by_domain.items()):
        for val, files in sorted(ids.items()):
            uniq = sorted(set(files))
            if len(uniq) > 1:
                violations.append(("CP-R10", ";".join(uniq), val,
                                   "同域「%s」实体 ID 重复定义 %d 处" % (domain, len(uniq))))

    # CP-R10-b 分片内行 id 重复（导航表互相覆盖）
    for rel, ids in sorted(line_ids_by_file.items()):
        dup = sorted({i for i in ids if ids.count(i) > 1})
        for val in dup:
            violations.append(("CP-R10", rel, val,
                               "分片内行 id 重复 %d 次（导航表将互相覆盖）" % ids.count(val)))

    print("id_validator · 16图CP-5 ID层校验（GATE06）")
    print("  扫描值点: %d | 基线: %d | 退役名单: %d" % (len(seen), len(baseline_set), len(retired)))
    for n in notes:
        print("  ℹ " + n)
    if violations:
        for rule, f, val, ev in violations:
            print("  ✗ [%s] %s id=%s — %s" % (rule, f, val, ev))
        print("════ 结论：✗ %d 项违规（CP-R01/R02/R10 FATAL）════" % len(violations))
        sys.exit(1)
    print("════ 结论：✓ 通过（基线外零新增 / 退役零再现 / 同域零重复）════")
    sys.exit(0)


if __name__ == "__main__":
    main()
