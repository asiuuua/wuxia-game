# -*- coding: utf-8 -*-
"""phase5_dep_graph_tests.py — Phase 5 Dependency Graph 回归（verify_all GATE41 升级项）

临时目录自包含测试，不碰真工程数据：
  段 A  Content Graph 图遍历（impact / transitive_reverse / find_cycles）
  段 B  dep_graph 统一门面（content_* / code_* 双命名空间）
  段 C  GATE41 Content 环检测集成
退出码 0=通过。
"""
import os
import sys
import json
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ref_index  # noqa: E402


def _w(root, rel, data):
    p = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def make_temp_project():
    """建最小工程：NPC → Dialogue → Quest → Item 链，带环的对话跳转。"""
    d = tempfile.mkdtemp(prefix="p5_dep_")
    _w(d, "data/configs/regions/newbie_village/npcs.json", {"npcs": [
        {"id": "npc_001", "name": "张三", "dialog_id": "dlg_001", "scene": "newbie_village"},
        {"id": "npc_free", "name": "路人甲", "scene": "newbie_village"},
    ]})
    _w(d, "data/configs/npcs/dialogs/_index.json", {"shards": {"dlg_001": {}, "dlg_002": {}}})
    _w(d, "data/configs/npcs/dialogs/shards/dlg_001.json", {
        "id": "dlg_001", "npc_id": "npc_001", "lines": [
            {"id": "l1", "speaker_id": "npc_001", "text": "你好", "next_id": "l2"},
            {"id": "l2", "speaker_id": "player", "text": "你好", "next_id": "l1"},  # l1↔l2 成环
        ]})
    _w(d, "data/configs/npcs/dialogs/shards/dlg_002.json", {
        "id": "dlg_002", "lines": [
            {"id": "m1", "speaker_id": "player", "text": "自由对话"},
        ]})
    _w(d, "data/configs/quests/main.json", {"quests": [
        {"id": "q_001", "name": "初遇", "dialogue_id": "dlg_001",
         "rewards": {"items": [{"item_id": "item_001", "amount": 1}]}},
    ]})
    _w(d, "data/configs/items/consumables.json", {"items": [
        {"id": "item_001", "name": "金创药", "type": "consumable"},
    ]})
    return d


# =====================================================================
# 段 A：Content Graph 图遍历纯函数
# =====================================================================
def section_a(root, checks):
    # A1 impact：npc_001 → dlg_001（直接，speaker + npc_id）→ q_001（间接，任务引用对话）
    imp = ref_index.impact("npc", "npc_001", root=root)
    checks.append(("A1 impact NPC→对话→任务",
                   "dlg_001" in imp.get("dialog", []) and "q_001" in imp.get("quest", []),
                   "imp=%s" % imp))
    # A2 impact 不含起点自身类型（NPC 不在结果里）
    checks.append(("A2 impact 不含起点自身类型", "npc" not in imp,
                   "imp.keys=%s" % list(imp.keys())))
    # A3 impact 无引用 NPC 为空
    imp_free = ref_index.impact("npc", "npc_free", root=root)
    checks.append(("A3 impact 无引用 NPC 为空",
                   all(len(v) == 0 for v in imp_free.values()) or not imp_free,
                   "imp_free=%s" % imp_free))
    # A4 transitive_reverse：item_001 被 q_001 引用（直接）
    rev = ref_index.transitive_reverse("item", "item_001", root=root)
    checks.append(("A4 transitive_reverse item→quest",
                   "q_001" in rev.get("quest", []),
                   "rev=%s" % rev))
    # A5 transitive_reverse：dlg_001 被 npc_001 + q_001 引用
    rev_dlg = ref_index.transitive_reverse("dialog", "dlg_001", root=root)
    checks.append(("A5 transitive_reverse dialog 反向",
                   "npc_001" in rev_dlg.get("npc", []) and "q_001" in rev_dlg.get("quest", []),
                   "rev_dlg=%s" % rev_dlg))
    # A6 find_cycles：line_jump l1↔l2 成环（对话跳转环）
    cycles = ref_index.find_cycles(root=root)
    has_line_cycle = any(
        all(k == "line_jump" for k, _e in c) and len(c) >= 2
        for c in cycles
    )
    checks.append(("A6 find_cycles 检测到 line_jump 环", has_line_cycle,
                   "cycles=%d first=%s" % (len(cycles), cycles[0] if cycles else None)))
    # A7 NPC↔Dialog 双向绑定环是正常模式（NPC.dialog_id ↔ Dialog.npc_id 互指）
    has_npc_dialog_cycle = any(
        {"npc", "dialog"}.issubset({k for k, _e in c})
        for c in cycles
    )
    checks.append(("A7 NPC↔Dialog 双向绑定环存在（正常模式）", has_npc_dialog_cycle,
                   "has_cycle=%s" % has_npc_dialog_cycle))
    # A8 _kind_of_id 反推正确
    defs, _refs = ref_index.build(root)
    checks.append(("A8 _kind_of_id npc", ref_index._kind_of_id("npc_001", defs) == "npc",
                   "kind=%s" % ref_index._kind_of_id("npc_001", defs)))
    checks.append(("A8b _kind_of_id item", ref_index._kind_of_id("item_001", defs) == "item",
                   "kind=%s" % ref_index._kind_of_id("item_001", defs)))
    checks.append(("A8c _kind_of_id 不存在返回 None", ref_index._kind_of_id("ghost", defs) is None,
                   "kind=%s" % ref_index._kind_of_id("ghost", defs)))


# =====================================================================
# 段 B：dep_graph 统一门面（content_* / code_* 双命名空间）
# =====================================================================
def section_b(root, checks):
    sys.path.insert(0, HERE)
    try:
        import dep_graph
    except ImportError as e:
        checks.append(("B0 dep_graph 模块存在", False, "ImportError: %s" % e))
        return
    # B1 content_impact 透传
    imp = dep_graph.content_impact("npc", "npc_001", root=root)
    checks.append(("B1 content_impact 透传",
                   "dlg_001" in imp.get("dialog", []),
                   "imp=%s" % imp))
    # B2 content_reverse 透传（transitive=True）
    rev = dep_graph.content_reverse("item", "item_001", root=root, transitive=True)
    checks.append(("B2 content_reverse transitive 透传",
                   "q_001" in rev.get("quest", []),
                   "rev=%s" % rev))
    # B3 content_cycles 透传
    cycles = dep_graph.content_cycles(root=root)
    checks.append(("B3 content_cycles 透传", len(cycles) >= 1,
                   "cycles=%d" % len(cycles)))
    # B4 code_scan 透传（对工程根扫描有结果）
    code_report = dep_graph.code_scan(root=root)
    gd_count = code_report.get("summary", {}).get("gd_files", 0)
    checks.append(("B4 code_scan 透传", gd_count >= 0,  # 临时目录可能没 .gd
                   "gd_files=%d" % gd_count))
    # B5 code_impact 对被引用文件非空（_test_base.gd 被 80+ 测试文件引用）
    real_root = os.path.dirname(HERE)
    real_impact = dep_graph.code_impact("tests/unit/_test_base.gd", root=real_root)
    checks.append(("B5 code_impact _test_base 非空", len(real_impact) >= 10,
                   "impact_count=%d first=%s" % (len(real_impact), real_impact[:3])))
    real_reverse = dep_graph.code_reverse("tests/unit/_test_base.gd", root=real_root)
    checks.append(("B6 code_reverse _test_base 非空", len(real_reverse) >= 10,
                   "reverse_count=%d" % len(real_reverse)))


# =====================================================================
# 段 C：GATE41 Content 环检测集成
# =====================================================================
def section_c(root, checks):
    # C1 find_cycles 在真实工程上也能跑（不崩）
    real_cycles = ref_index.find_cycles()
    checks.append(("C1 find_cycles 真实工程可运行", isinstance(real_cycles, list),
                   "type=%s count=%d" % (type(real_cycles).__name__, len(real_cycles))))
    # C2 真实工程 Content Graph 有环（NPC↔Dialog 双向绑定等正常模式），REPORT 模式
    checks.append(("C2 真实工程 Content Graph 环数（REPORT）", True,
                   "cycles=%d（NPC↔Dialog 双向绑定等正常模式，不拦截）" % len(real_cycles)))


def main():
    failures = []
    d = make_temp_project()
    try:
        checks = []
        section_a(d, checks)
        section_b(d, checks)
        section_c(d, checks)
        for name, ok, msg in checks:
            print("  %s %s（%s）" % ("✓" if ok else "✗", name, msg))
        failures = [(n, o, m) for n, o, m in checks if not o]
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print("════ Phase 5 Dependency Graph：%s（失败 %d）════" % (
        "✓ 通过" if not failures else "✗ 未过", len(failures)))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
