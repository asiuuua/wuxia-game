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


def build(root=None):
    # root 参数：DataSink 增量反查（15 图 ST-2 ⑤）对被编辑工程（可非本仓）建索引用
    R = os.path.abspath(root) if root else ROOT
    defs = {k: {} for k in ["npc", "quest", "item", "battle", "enemy", "dialog",
                            "ability", "flag_def", "battle_layout", "line_jump"]}
    refs = []   # (kind, from_id, to_kind, to_id, file, soft)

    def add_def(kind, eid, file):
        defs[kind][str(eid)] = file

    def add_ref(from_id, to_kind, to_id, file, soft=False):
        refs.append((to_kind, str(from_id), str(to_id), file, soft))

    # ---- 定义收集 ----
    for fp in glob.glob(os.path.join(R, "data", "configs", "regions", "*", "npcs.json")):
        for n in _load(fp).get("npcs", []):
            add_def("npc", n.get("id"), fp)
    for n in _load(os.path.join(R, "data", "configs", "npcs", "town_npcs.json")).get("npcs", []):
        add_def("npc", n.get("id"), "town_npcs.json(留档)")
    quest_files = glob.glob(os.path.join(R, "data", "configs", "regions", "*", "quests.json")) + \
        glob.glob(os.path.join(R, "data", "configs", "quests", "*.json"))
    for fp in quest_files:
        d = _load(fp)
        for q in d.get("quests", []):
            add_def("quest", q.get("id"), fp)
    for fp in glob.glob(os.path.join(R, "data", "configs", "items", "*.json")) + \
            glob.glob(os.path.join(R, "data", "configs", "regions", "*", "items.json")):
        for it in _load(fp).get("items", []):
            add_def("item", it.get("id"), fp)
    for fp in glob.glob(os.path.join(R, "data", "configs", "regions", "*", "battles.json")):
        for b in _load(fp).get("battles", []):
            add_def("battle", b.get("id"), fp)
            for eid in b.get("enemy_ids", []):
                refs.append(("enemy", str(b.get("id")), str(eid), fp, False))
    for fp in glob.glob(os.path.join(R, "data", "configs", "scenes", "*.json")) + \
            glob.glob(os.path.join(R, "data", "configs", "battles", "*.json")):
        d = _load(fp)
        bl = d.get("battles", [])
        if not isinstance(bl, list):
            continue
        for b in bl:
            if isinstance(b, dict) and b.get("id"):
                add_def("battle", b["id"], fp)
                for eid in b.get("enemy_ids", []):
                    refs.append(("enemy", str(b["id"]), str(eid), fp, False))
                if b.get("layout"):
                    add_ref(b["id"], "battle_layout", b["layout"], fp)   # 硬边：战斗定义字段
    for fp in glob.glob(os.path.join(R, "data", "configs", "battles", "grids", "*.json")):
        if os.path.basename(fp).startswith("_"):
            continue
        add_def("battle_layout", os.path.basename(fp)[:-5], fp)
    for fp in glob.glob(os.path.join(R, "data", "configs", "regions", "*", "enemies.json")) + \
            [os.path.join(R, "data", "configs", "npcs", "enemies.json")]:
        for e in _load(fp).get("enemies", []):
            add_def("enemy", e.get("id"), fp)
    for fp in glob.glob(os.path.join(R, "data", "configs", "regions", "*", "index.json")):
        for did in _load(fp).get("dialogs", []):
            add_def("dialog", did, fp)
    gi = _load(os.path.join(R, "data", "configs", "npcs", "dialogs", "_index.json"))
    for did in gi.get("shards", {}).keys():
        add_def("dialog", did, "npcs/dialogs/_index.json")
    for fp in glob.glob(os.path.join(R, "data", "configs", "npcs", "dialogs", "shards", "*.json")):
        add_def("dialog", os.path.basename(fp)[:-5], fp)
    for a in _load(os.path.join(R, "data", "configs", "abilities", "skills.json")).get("skills", []):
        add_def("ability", a.get("id"), "abilities/skills.json")

    # ---- 引用收集 ----
    # NPC → dialog/quest/battle
    for fp in glob.glob(os.path.join(R, "data", "configs", "regions", "*", "npcs.json")) + \
            [os.path.join(R, "data", "configs", "npcs", "town_npcs.json")]:
        for n in _load(fp).get("npcs", []):
            nid = n.get("id", "?")
            if n.get("dialog_id"):
                add_ref(nid, "dialog", n["dialog_id"], fp)
            if n.get("quest_id"):
                add_ref(nid, "quest", n["quest_id"], fp)
            if n.get("battle_id"):
                add_ref(nid, "battle", n["battle_id"], fp)
    # 任务 → 目标/奖励/前置旗标/回写旗标 + 关联对话
    for fp in quest_files:
        for q in _load(fp).get("quests", []):
            qid = q.get("id", "?")
            if q.get("dialogue_id"):
                add_ref(qid, "dialog", q["dialogue_id"], fp)
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
    # 对话分片：绑定 NPC + 行内命令 + 图内部跳转（line_jump 正向边：行定义全量登记，目标作用域=分片 id）
    shard_files = glob.glob(os.path.join(R, "data", "configs", "npcs", "dialogs", "shards", "*.json")) + \
        glob.glob(os.path.join(R, "data", "configs", "regions", "*", "dialogs", "*.json"))
    for fp in shard_files:
        d = _load(fp)
        did = d.get("id", os.path.basename(fp)[:-5])
        if d.get("npc_id"):
            add_ref(did, "npc", d["npc_id"], fp, soft=True)   # 软边：VA4-BINDING 登记放行（回收站延迟绑定/预建实体）
        for l in d.get("lines", []):
            if l.get("id"):
                add_def("line_jump", "%s/%s" % (did, l["id"]), fp)
        for l in d.get("lines", []):
            lid = l.get("id", "?")
            s = l.get("speaker_id")
            if s and s != "player":
                add_ref(did, "npc", s, fp, soft=True)     # 软边：内容字段（player=玩家发言）
            if l.get("next_id"):
                refs.append(("line_jump", "%s/%s" % (did, lid), "%s/%s" % (did, l["next_id"]), fp, False))
            for o in l.get("options", []):
                if o.get("jump_id"):
                    refs.append(("line_jump", "%s/%s" % (did, lid), "%s/%s" % (did, o["jump_id"]), fp, False))
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
    for kind, frm, to, fp, soft in refs:
        ok = to in defs.get(kind, {})
        if ok:
            continue
        entry = (kind, frm, to)
        if entry in baseline:
            known.append((kind, frm, to, fp))
        elif kind == "flag_def" or soft:
            warned.append((kind, frm, to, fp))
        else:
            dangling.append((kind, frm, to, fp))
    return dangling, warned, known


# ---- ReferenceInspector：查询（Phase 4 三件套） ----
def _all_refs(root=None):
    _defs, refs = build(root)
    return refs


def reverse_dependencies(target, root=None):
    """谁引用了 target：返回 [(kind, from_id, file)]（含软边，供删除保护）。"""
    return [(k, f, fp) for (k, f, t, fp, _s) in _all_refs(root) if str(t) == str(target)]


def references_of(from_id, root=None):
    """我引用了谁：返回 [(kind, to_id, file)]。"""
    return [(k, t, fp) for (k, f, t, fp, _s) in _all_refs(root) if str(f) == str(from_id)]


def resolve(kind, eid, root=None):
    """定义查询：存在返回所在文件，否则 None。"""
    defs, _refs = build(root)
    return defs.get(kind, {}).get(str(eid))


# ---- ReferenceValidator：删除保护（Phase 4 三件套） ----
def validate_delete(kind, eid, root=None):
    """删除保护：kind=被删实体边种类（npc/dialog/line_jump/battle_layout…）。
    被引用 → (False, blockers)；无引用 → (True, [])。blockers=[(kind, from_id, file)]。"""
    blockers = [(k, f, fp) for (k, f, t, fp, _s) in _all_refs(root)
                if k == kind and str(t) == str(eid)]
    return (not blockers), blockers


def validate_cascade(kind, eid, cascade, root=None):
    """显式级联验证：cascade（引用方 id 列表）必须恰好覆盖全部引用方。
    返回 (allowed, uncovered, invalid)。uncovered=漏报；invalid=cascade 里不存在的引用。"""
    blockers = [f for (_k, f, _fp) in validate_delete(kind, eid, root=root)[1]]
    cset = set(str(x) for x in (cascade or []))
    bset = set(blockers)
    uncovered = sorted(bset - cset)
    invalid = sorted(cset - bset)
    return (not uncovered and not invalid), uncovered, invalid


# ---- Content Graph：图遍历（Phase 5 Dependency Graph）----
# 基于 Reference 三件套的实体级依赖图，支持 impact / 传递反查 / 环检测

_CONTENT_KINDS_ORDER = ["npc", "quest", "item", "battle", "enemy", "dialog",
                        "ability", "flag_def", "battle_layout", "line_jump"]


def _kind_of_id(eid, defs):
    """根据 id 反推实体类型（跨 kind 图遍历用）。
    按 CONTENT_KINDS_ORDER 优先匹配更具体的域，line_jump 作用域化 id 单独判断。"""
    eid_s = str(eid)
    for k in _CONTENT_KINDS_ORDER:
        if eid_s in defs.get(k, {}):
            return k
    # line_jump 是作用域化 id（dlg_id/lid），若含斜杠单独判断
    if "/" in eid_s and eid_s in defs.get("line_jump", {}):
        return "line_jump"
    return None


def impact(kind, eid, root=None):
    """Content Graph 影响分析（可传递）：改 kind/eid 会波及哪些上游实体（即谁引用了它）。
    返回 {kind: [ids...]}，不含起点自身。等价于 transitive_reverse 的业务语义封装。

    例：impact("npc", "npc_001") → {dialog: [dlg_001], quest: [q_001]}
    （改 npc_001 会影响引用它的 dlg_001，进而影响引用 dlg_001 的 q_001）
    """
    return transitive_reverse(kind, eid, root=root)


def transitive_reverse(kind, eid, root=None):
    """Content Graph 传递反向依赖：谁直接+间接引用了 kind/eid。
    返回 {kind: [ids...]}，不含起点自身。

    例：transitive_reverse("dialog", "dlg_001") → {npc: [npc_001], quest: [q_001]}
    """
    defs, refs = build(root)
    start_key = (kind, str(eid))
    visited = set()
    result = {}

    def _walk(k, e):
        key = (k, e)
        if key in visited:
            return
        visited.add(key)
        for rk, rf, rt, _fp, _s in refs:
            if rk == k and rt == e:
                fk = _kind_of_id(rf, defs)
                if fk:
                    ref_key = (fk, rf)
                    if ref_key != start_key:    # 跳过起点自身（双向绑定绕回）
                        result.setdefault(fk, set()).add(rf)
                        _walk(fk, rf)

    _walk(kind, str(eid))
    return {k: sorted(v) for k, v in result.items()}


def find_cycles(root=None):
    """Content Graph 环检测（DFS 三色法）。
    返回 [cycle_list]，每个 cycle 是 [(kind, id), ...] 的节点列表。
    同一环可能被多个起点发现，调用方可按需去重。"""
    defs, refs = build(root)
    # 建邻接表：(kind, id) -> [(kind, id)]
    adj = {}
    for rk, rf, rt, _fp, _s in refs:
        if rt not in defs.get(rk, {}):
            continue  # 跳过悬空边
        fk = _kind_of_id(rf, defs)
        if not fk:
            continue
        adj.setdefault((fk, rf), []).append((rk, rt))
    # DFS 找环
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {}
    cycles = []

    def _dfs(node, path):
        color[node] = GRAY
        path.append(node)
        for nb in adj.get(node, []):
            c = color.get(nb, WHITE)
            if c == GRAY:
                idx = path.index(nb)
                cycles.append(list(path[idx:]))
            elif c == WHITE:
                _dfs(nb, path)
        path.pop()
        color[node] = BLACK

    for node in sorted(adj.keys()):
        if color.get(node, WHITE) == WHITE:
            _dfs(node, [])
    return cycles


def classify_cycles(cycles=None, root=None):
    """环分类：区分「正常模式环」与「问题环」。
    返回 {'normal': [正常环列表], 'problematic': [问题环列表]}

    正常模式环（豁免）：
      1. NPC 自环：NPC 的 speaker_id 指向自己（NPC 自己说话）
      2. NPC↔Dialog 双向绑定：NPC.dialog_id ↔ Dialog.npc_id 互指

    问题环（硬拦截）：
      1. line_jump 死循环：对话行跳转形成的环（玩家卡死在循环里）
      2. 其他跨类型环（待细化规则）
    """
    if cycles is None:
        cycles = find_cycles(root=root)
    normal = []
    problematic = []
    for c in cycles:
        kinds = {k for k, _e in c}
        ids = {e for _k, e in c}
        # 正常模式 1：NPC 自环（只有 npc 一种类型，且是 speaker 自己指自己）
        if kinds == {"npc"} and len(ids) == 1:
            normal.append(c)
            continue
        # 正常模式 2：NPC↔Dialog 双向绑定（只有 npc 和 dialog 两种类型，各一个节点）
        if kinds == {"npc", "dialog"} and len(c) == 2:
            normal.append(c)
            continue
        # 问题环：line_jump 死循环等
        problematic.append(c)
    return {"normal": normal, "problematic": problematic}


def find_problematic_cycles(root=None):
    """只返回问题环（硬拦截用）。"""
    return classify_cycles(root=root)["problematic"]


def main():
    defs, refs = build()
    args = sys.argv[1:]
    if "--who" in args:
        target = args[args.index("--who") + 1]
        hits = [(k, f, t, fp) for (k, f, t, fp, _s) in refs if t == target]
        print("被谁引用 [%s]：%d 处" % (target, len(hits)))
        for k, f, t, fp in hits[:30]:
            print("  [%s] %s ← %s" % (k, t, os.path.relpath(fp, ROOT)))
        return 0
    dangling, warned, known = check(defs, refs)
    print("════ ref_index · 数据引用校验 ════")
    print("实体定义：" + " ".join("%s=%d" % (k, len(defs[k]))
          for k in ["npc", "quest", "item", "battle", "enemy", "dialog",
                    "ability", "flag_def", "battle_layout", "line_jump"]))
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
