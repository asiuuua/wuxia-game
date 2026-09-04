# -*- coding: utf-8 -*-
"""
ref_index.py — 数据引用索引 + 悬空引用校验（P5 工具边界 · 2026-09-04）
================================================================
回答两个问题（整改路线 P5 验收）：
  1) 校验：数据里写的 ID 引用是否都存在（悬空引用 = 游戏运行时查表失败）？
  2) 索引：某个 NPC/任务/物品/旗标 被谁引用？（--who <id>）

扫描范围：data/configs/**/*.json
提取规则（P5 轻量版，按已知字段名精准提取，不做全键猜测）：
  定义侧（写入索引的实体）：
    npc      ← regions/*/npcs.json + npcs/town_npcs.json(只读留档)
    quest    ← regions/*/quests.json + quests/quests.json
    item     ← items/{equipment,materials,pills}.json + regions/*/items.json
    battle   ← regions/*/battles.json + battles/*.json(定义形态扫描)
    enemy    ← regions/*/enemies.json + npcs/enemies.json
    dialog   ← npcs/dialogs/_index.json 分片 + regions/*/index.json dialogs
    ability  ← abilities/skills.json
    flag     ← 任务 then_set 键 + 对话 set_flag 命令（旗标"定义"）
  引用侧（checked，悬空即报）：
    npc.dialog_id→dialog / npc.quest_id→quest / npc.battle_id→battle
    quest.objectives[].target_battle→battle / .need_item→item
    quest.rewards.items[].item_id→item / rewards.abilities[]→ability
    对话行 next_id/options.jump_id → 同分片行 id（对话图内部可达）
    quest.prerequisites 键 → flag（旗标引用只告警不硬拦：旗标可运行时定义）
用法：
  python tools/ref_index.py               # 全量校验报告（悬空=退出码1）
  python tools/ref_index.py --who <id>    # 查谁引用了它
基线：tools/ref_baseline.json 里登记的存量悬空不拦（修一个删一条）。
"""
import os
import sys
import json
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BASE = os.path.join(HERE, "ref_baseline.json")


def _load(fp):
    try:
        with open(fp, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def build():
    defs = {k: {} for k in ["npc", "quest", "item", "battle", "enemy", "dialog", "ability", "flag_def"]}
    refs = []   # (kind, from_id, to_kind, to_id, file)

    def add_def(kind, eid, file):
        defs[kind][str(eid)] = file

    def add_ref(from_id, to_kind, to_id, file):
        refs.append((to_kind, str(from_id), str(to_id), file))

    # ---- 定义收集 ----
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "npcs.json")):
        for n in _load(fp).get("npcs", []):
            add_def("npc", n.get("id"), fp)
    for n in _load(os.path.join(ROOT, "data", "configs", "npcs", "town_npcs.json")).get("npcs", []):
        add_def("npc", n.get("id"), "town_npcs.json(留档)")
    quest_files = glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "quests.json")) + \
        glob.glob(os.path.join(ROOT, "data", "configs", "quests", "*.json"))
    for fp in quest_files:
        d = _load(fp)
        for q in d.get("quests", []):
            add_def("quest", q.get("id"), fp)
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "items", "*.json")) + \
            glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "items.json")):
        for it in _load(fp).get("items", []):
            add_def("item", it.get("id"), fp)
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "battles.json")):
        for b in _load(fp).get("battles", []):
            add_def("battle", b.get("id"), fp)
            for eid in b.get("enemy_ids", []):
                refs.append(("enemy", str(b.get("id")), str(eid), fp))
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "scenes", "*.json")) + \
            glob.glob(os.path.join(ROOT, "data", "configs", "battles", "*.json")):
        d = _load(fp)
        bl = d.get("battles", [])
        if not isinstance(bl, list):
            continue
        for b in bl:
            if isinstance(b, dict) and b.get("id"):
                add_def("battle", b["id"], fp)
                for eid in b.get("enemy_ids", []):
                    refs.append(("enemy", str(b["id"]), str(eid), fp))
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "enemies.json")) + \
            [os.path.join(ROOT, "data", "configs", "npcs", "enemies.json")]:
        for e in _load(fp).get("enemies", []):
            add_def("enemy", e.get("id"), fp)
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "index.json")):
        for did in _load(fp).get("dialogs", []):
            add_def("dialog", did, fp)
    gi = _load(os.path.join(ROOT, "data", "configs", "npcs", "dialogs", "_index.json"))
    for did in gi.get("shards", {}).keys():
        add_def("dialog", did, "npcs/dialogs/_index.json")
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "npcs", "dialogs", "shards", "*.json")):
        add_def("dialog", os.path.basename(fp)[:-5], fp)
    for a in _load(os.path.join(ROOT, "data", "configs", "abilities", "skills.json")).get("skills", []):
        add_def("ability", a.get("id"), "abilities/skills.json")

    # ---- 引用收集 ----
    # NPC → dialog/quest/battle
    for fp in glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "npcs.json")) + \
            [os.path.join(ROOT, "data", "configs", "npcs", "town_npcs.json")]:
        for n in _load(fp).get("npcs", []):
            nid = n.get("id", "?")
            if n.get("dialog_id"):
                add_ref(nid, "dialog", n["dialog_id"], fp)
            if n.get("quest_id"):
                add_ref(nid, "quest", n["quest_id"], fp)
            if n.get("battle_id"):
                add_ref(nid, "battle", n["battle_id"], fp)
    # 任务 → 目标/奖励/前置旗标/回写旗标
    for fp in quest_files:
        for q in _load(fp).get("quests", []):
            qid = q.get("id", "?")
            for obj in q.get("objectives", []):
                if obj.get("target_battle"):
                    add_ref(qid, "battle", obj["target_battle"], fp)
                if obj.get("need_item"):
                    add_ref(qid, "item", obj["need_item"], fp)
            for it in q.get("rewards", {}).get("items", []):
                if it.get("item_id"):
                    add_ref(qid, "item", it["item_id"], fp)
            for ab in q.get("rewards", {}).get("abilities", []):
                add_ref(qid, "ability", ab, fp)
            for k in q.get("prerequisites", {}).keys():
                add_ref(qid, "flag_def", k, fp)   # 旗标引用：只告警
            for k in q.get("then_set", {}).keys():
                add_def("flag_def", k, fp)
    # 对话分片：行内命令 + 图内部跳转
    shard_files = glob.glob(os.path.join(ROOT, "data", "configs", "npcs", "dialogs", "shards", "*.json")) + \
        glob.glob(os.path.join(ROOT, "data", "configs", "regions", "*", "dialogs", "*.json"))
    for fp in shard_files:
        d = _load(fp)
        did = d.get("id", os.path.basename(fp)[:-5])
        line_ids = {str(l.get("id")) for l in d.get("lines", []) if l.get("id")}
        for l in d.get("lines", []):
            lid = l.get("id", "?")
            if l.get("next_id") and str(l["next_id"]) not in line_ids:
                refs.append(("line_jump", "%s/%s" % (did, lid), str(l["next_id"]), fp))
            for o in l.get("options", []):
                if o.get("jump_id") and str(o["jump_id"]) not in line_ids:
                    refs.append(("line_jump", "%s/%s" % (did, lid), str(o["jump_id"]), fp))
                for eff in o.get("effects", []):
                    _effect_ref(did, eff, fp, add_ref, add_def)
            for eff in l.get("effects", []):
                _effect_ref(did, eff, fp, add_ref, add_def)
    return defs, refs


def _effect_ref(did, eff, fp, add_ref, add_def):
    if not (isinstance(eff, str) and ":" in eff):
        return
    cmd, arg = eff.split(":", 1)
    if cmd == "quest_accept" or cmd == "quest_complete":
        add_ref(did, "quest", arg, fp)
    elif cmd == "set_flag":
        add_def("flag_def", arg, fp)


def check(defs, refs):
    baseline = set()
    if os.path.exists(BASE):
        baseline = {(e.get("kind"), e.get("from"), e.get("to")) for e in _load(BASE).get("known", [])}
    dangling, warned, known = [], [], []
    for kind, frm, to, fp in refs:
        ok = to in defs.get(kind, {})
        if ok:
            continue
        entry = (kind, frm, to)
        if entry in baseline:
            known.append((kind, frm, to, fp))
        elif kind == "flag_def":
            warned.append((kind, frm, to, fp))
        else:
            dangling.append((kind, frm, to, fp))
    return dangling, warned, known


def main():
    defs, refs = build()
    args = sys.argv[1:]
    if "--who" in args:
        target = args[args.index("--who") + 1]
        hits = [(k, f, t, fp) for (k, f, t, fp) in refs if t == target]
        print("被谁引用 [%s]：%d 处" % (target, len(hits)))
        for k, f, t, fp in hits[:30]:
            print("  [%s] %s ← %s" % (k, t, os.path.relpath(fp, ROOT)))
        return 0
    dangling, warned, known = check(defs, refs)
    print("════ ref_index · 数据引用校验 ════")
    print("实体定义：npc=%d quest=%d item=%d battle=%d enemy=%d dialog=%d ability=%d flag_def=%d"
          % tuple(len(defs[k]) for k in ["npc", "quest", "item", "battle", "enemy", "dialog", "ability", "flag_def"]))
    print("引用总数：%d" % len(refs))
    for kind, frm, to, fp in dangling[:15]:
        print("  ✗ 悬空[%s] %s → %s（%s）" % (kind, frm, to, os.path.relpath(fp, ROOT)))
    for kind, frm, to, fp in warned[:10]:
        print("  ⚠ 旗标引用无定义来源[%s] %s → %s（可运行时定义，仅提示）" % (kind, frm, to, os.path.relpath(fp, ROOT)))
    for kind, frm, to, fp in known[:10]:
        print("  ⏸ 基线存量(不拦) [%s] %s → %s" % (kind, frm, to, os.path.relpath(fp, ROOT)))
    ok = not dangling
    print("════ 结论：%s（悬空 %d / 旗标提示 %d / 基线 %d）════"
          % ("✓ 通过" if ok else "✗ 有悬空引用", len(dangling), len(warned), len(known)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
