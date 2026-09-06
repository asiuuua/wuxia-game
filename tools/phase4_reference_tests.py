# -*- coding: utf-8 -*-
"""phase4_reference_tests.py — Phase 4 Reference 三件套回归（verify_all GATE11）

临时目录自包含测试，不碰真工程数据：
  段 A  三件套纯函数（Resolver 解析 / Inspector 反查 / Validator 删除保护+级联）
  段 B  NPC 删除保护 + 显式级联（npc_delete）
  段 C  对话/台词行删除保护 + 级联（dlg_delete / dlg_line_delete）
  段 D  战棋布局删除保护 + 级联（battle_layout_delete）
  段 E  负向验收：NPC.dialog_id=UNKNOWN → Reference FAIL → Commit BLOCK
退出码 0=通过；供 verify_all.py GATE11 调用。
"""
import os
import sys
import json
import shutil
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
STUDIO = os.path.join(HERE, "desktop_studio")
sys.path.insert(0, STUDIO)

import ref_index  # noqa: E402

try:
    import data_sink as _ds
    _ds._changelog_enabled = False
except Exception:
    pass


def _w(root, rel, data):
    """测试夹具写 JSON（不走 DataSink，只放数据）。"""
    p = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def make_temp_project():
    """建最小工程：NPC 表 + 对话分片 + 对话索引 + 战斗定义 + 战棋布局。"""
    d = tempfile.mkdtemp(prefix="p4_ref_")
    _w(d, "data/configs/npcs/town_npcs.json", {"npcs": []})  # 工程标记：set_project_root 依赖
    _w(d, "data/configs/regions/newbie_village/npcs.json", {"npcs": [
        {"id": "npc_001", "name": "被引用NPC", "dialog_id": "dlg_001", "scene": "newbie_village"},
        {"id": "npc_free", "name": "无引用NPC", "scene": "newbie_village"},
    ]})
    _w(d, "data/configs/npcs/dialogs/_index.json", {"shards": {
        "dlg_001": {"file": "res://data/configs/npcs/dialogs/shards/dlg_001.json", "npc_id": "npc_001", "chapter": "custom"},
        "dlg_002": {"file": "res://data/configs/npcs/dialogs/shards/dlg_002.json", "npc_id": "", "chapter": "custom"},
    }})
    _w(d, "data/configs/npcs/dialogs/shards/dlg_001.json", {
        "id": "dlg_001", "npc_id": "npc_001", "lines": [
            {"id": "l1", "speaker_id": "npc_001", "text": "你好"},
            {"id": "l2", "speaker_id": "player", "text": "再见", "next_id": "l1"},
        ]})
    _w(d, "data/configs/npcs/dialogs/shards/dlg_002.json", {
        "id": "dlg_002", "lines": [
            {"id": "m1", "speaker_id": "npc_001", "text": "甲"},
            {"id": "m2", "speaker_id": "player", "text": "乙", "next_id": "m1"},
        ]})
    _w(d, "data/configs/scenes/battles.json", {"battles": [
        {"id": "battle_001", "name": "测试战", "layout": "grid_01", "enemy_ids": []},
    ]})
    _w(d, "data/configs/battles/grids/grid_01.json", {"name": "测试布局", "width": 6, "height": 8})
    return d


def section_a(root, checks):
    """段 A：三件套纯函数。"""
    defs, refs = ref_index.build(root)
    # A1 定义解析（Resolver）：npc / dialog / battle_layout 定义都在
    checks.append(("A1 Resolver 解析定义", "npc_001" in defs["npc"] and "dlg_001" in defs["dialog"]
                   and "grid_01" in defs.get("battle_layout", {})
                   and "battle_001" in defs["battle"], "defs=%s" % list(defs.keys())))
    # A2 新边 speaker_id 命中（软边）：dlg_002.m1 的 speaker_id=npc_001 → 引用方=dlg_002
    who = ref_index.reverse_dependencies("npc_001", root=root)
    froms = sorted({f for (_k, f, _fp) in who})
    checks.append(("A2 Inspector 反查 speaker 边", "dlg_001" in froms and "dlg_002" in froms,
                   "who=%s" % froms))
    # A3 player 排除：speaker_id=player 不产生边
    pl = ref_index.reverse_dependencies("player", root=root)
    checks.append(("A3 player 保留字排除", len(pl) == 0, "who(player)=%d" % len(pl)))
    # A4 新边 layout 命中：battle_001.layout=grid_01 → 引用方=battle_001
    who2 = ref_index.reverse_dependencies("grid_01", root=root)
    checks.append(("A4 Inspector 反查 layout 边", any(f == "battle_001" for (_k, f, _fp) in who2),
                   "who(grid_01)=%s" % who2))
    # A5 软硬分级：现工程无硬悬空
    dangling, warned, _known = ref_index.check(defs, refs)
    checks.append(("A5 现工程全绿（无硬悬空）", len(dangling) == 0,
                   "dangling=%s" % dangling))
    # A6 删除保护：npc_001 被引用 → BLOCK
    allowed, blockers = ref_index.validate_delete("npc", "npc_001", root=root)
    checks.append(("A6 validate_delete 被引用 BLOCK", (not allowed) and len(blockers) >= 2,
                   "allowed=%s blockers=%s" % (allowed, blockers)))
    # A7 删除保护：npc_free 无引用 → 放行
    allowed2, blockers2 = ref_index.validate_delete("npc", "npc_free", root=root)
    checks.append(("A7 validate_delete 无引用放行", allowed2 and not blockers2,
                   "allowed=%s" % allowed2))
    # A8 级联验证：完整覆盖放行
    a_ok, uncovered, invalid = ref_index.validate_cascade("npc", "npc_001", ["dlg_001", "dlg_002"], root=root)
    checks.append(("A8 cascade 完整覆盖放行", a_ok and not uncovered and not invalid,
                   "ok=%s unc=%s inv=%s" % (a_ok, uncovered, invalid)))
    # A9 级联验证：漏报 BLOCK
    a_ok2, uncovered2, _i2 = ref_index.validate_cascade("npc", "npc_001", ["dlg_001"], root=root)
    checks.append(("A9 cascade 漏报 BLOCK", (not a_ok2) and "dlg_002" in uncovered2,
                   "ok=%s unc=%s" % (a_ok2, uncovered2)))
    # A10 级联验证：瞎写 BLOCK
    a_ok3, _u3, invalid3 = ref_index.validate_cascade("npc", "npc_001", ["dlg_001", "dlg_002", "ghost_x"], root=root)
    checks.append(("A10 cascade 瞎写 BLOCK", (not a_ok3) and "ghost_x" in invalid3,
                   "ok=%s inv=%s" % (a_ok3, invalid3)))


def section_b(root, checks):
    """段 B：npc_delete 删除保护 + 显式级联（服务层，切根临时工程）。"""
    import studio_core as _sc
    _sc.set_project_root(root)
    # B1 被引用 NPC 无级联 → BLOCK（npc_001 被 dlg_001/002 引用）
    ok, msg = _sc.npc_delete("npc_001")
    checks.append(("B1 npc_delete 被引用 BLOCK", (not ok) and "阻止" in str(msg),
                   "ok=%s msg=%s" % (ok, msg)))
    # B2 无引用 NPC → 成功
    ok2, msg2 = _sc.npc_delete("npc_free")
    checks.append(("B2 npc_delete 无引用成功", ok2, "ok=%s msg=%s" % (ok2, msg2)))
    # B3 显式级联完整覆盖 → 成功，且引用方分片 npc_id 已清空
    ok3, msg3 = _sc.npc_delete("npc_001", cascade=["dlg_001", "dlg_002"])
    sh = json.load(open(os.path.join(root, "data/configs/npcs/dialogs/shards/dlg_001.json"), encoding="utf-8"))
    checks.append(("B3 npc_delete 级联成功", ok3 and sh.get("npc_id") == "",
                   "ok=%s msg=%s npc_id=%r" % (ok3, msg3, sh.get("npc_id"))))
    # B4 级联声明覆盖软边引用方（speaker_id）→ 成功
    _sc.npc_upsert({"id": "npc_002", "dialog_id": "dlg_002", "scene": "newbie_village"})
    _w(root, "data/configs/npcs/dialogs/shards/dlg_002.json", {
        "id": "dlg_002", "npc_id": "npc_002", "lines": [
            {"id": "m1", "speaker_id": "npc_002", "text": "甲"},
        ]})
    ok4, msg4 = _sc.npc_delete("npc_002", cascade=["dlg_002"])
    checks.append(("B4 npc_delete 级联覆盖软边引用方", ok4, "ok=%s msg=%s" % (ok4, msg4)))
    # B5 级联后 NPC 已删（区域表无记录）
    ids = [n.get("id") for n in _sc.npc_list()]
    checks.append(("B5 级联后 NPC 已删除", "npc_001" not in ids, "ids=%s" % ids))


def section_c(root, checks):
    """段 C：dlg_delete / dlg_line_delete 删除保护 + 级联。"""
    import studio_core as _sc
    _sc.set_project_root(root)
    # 重建状态：B 段级联已删 npc_001/002；新 NPC 引用 dlg_001 供 C1/C3 使用
    _sc.npc_upsert({"id": "npc_c1", "dialog_id": "dlg_001", "scene": "newbie_village"})
    # C1 被 NPC 引用的对话 → BLOCK（npc_c1.dialog_id=dlg_001）
    ok, msg = _sc.dlg_delete("dlg_001")
    checks.append(("C1 dlg_delete 被引用 BLOCK", (not ok) and "阻止" in str(msg),
                   "ok=%s msg=%s" % (ok, msg)))
    # C2 无引用对话 → 成功（safe_mode 保留分片文件供 C4~C6 使用）
    ok2, msg2 = _sc.dlg_delete("dlg_002")
    checks.append(("C2 dlg_delete 无引用成功", ok2, "ok=%s msg=%s" % (ok2, msg2)))
    # C3 显式级联：清 npc_c1.dialog_id 后删除成功
    ok3, msg3 = _sc.dlg_delete("dlg_001", cascade=["npc_c1"])
    npc = next(n for n in _sc.npc_list() if n.get("id") == "npc_c1")
    checks.append(("C3 dlg_delete 级联成功", ok3 and npc.get("dialog_id") == "",
                   "ok=%s msg=%s dialog_id=%r" % (ok3, msg3, npc.get("dialog_id"))))
    # C4 前置：恢复 dlg_002 分片（m2.next_id=m1 形成 line_jump 正向边）
    _w(root, "data/configs/npcs/dialogs/shards/dlg_002.json", {
        "id": "dlg_002", "lines": [
            {"id": "m1", "speaker_id": "npc_c1", "text": "甲"},
            {"id": "m2", "speaker_id": "player", "text": "乙", "next_id": "m1"},
        ]})
    # C4 被跳转引用的台词行 → BLOCK
    ok4, msg4 = _sc.dlg_line_delete("dlg_002", "m1")
    checks.append(("C4 dlg_line_delete 被引用 BLOCK", (not ok4) and "阻止" in str(msg4),
                   "ok=%s msg=%s" % (ok4, msg4)))
    # C5 手动解除跳转后删除成功
    shp = os.path.join(root, "data/configs/npcs/dialogs/shards/dlg_002.json")
    sh = json.load(open(shp, encoding="utf-8"))
    for l in sh["lines"]:
        if l["id"] == "m2":
            l["next_id"] = ""
    _w(root, "data/configs/npcs/dialogs/shards/dlg_002.json", sh)
    ok5, msg5 = _sc.dlg_line_delete("dlg_002", "m1")
    checks.append(("C5 dlg_line_delete 手动清理后成功", ok5, "ok=%s msg=%s" % (ok5, msg5)))
    # C6 cascade 声明但跳转未真清 → 保存被 DataSink ⑤ 兜底拦截 → 返回失败（已回滚）
    _w(root, "data/configs/npcs/dialogs/shards/dlg_002.json", {
        "id": "dlg_002", "lines": [
            {"id": "m1", "speaker_id": "npc_c1", "text": "甲"},
            {"id": "m2", "speaker_id": "player", "text": "乙", "next_id": "m1"},
        ]})
    ok6, msg6 = _sc.dlg_line_delete("dlg_002", "m1", cascade=["m2"])
    checks.append(("C6 cascade 声明未真清被 ⑤ 兜底", (not ok6) and "回滚" in str(msg6),
                   "ok=%s msg=%s" % (ok6, msg6)))


def section_d(root, checks):
    """段 D：battle_layout_delete 删除保护 + 级联。"""
    import studio_core as _sc
    _sc.set_project_root(root)
    # D1 被战斗引用的布局 → BLOCK（battle_001.layout=grid_01）
    ok, msg = _sc.battle_layout_delete("grid_01")
    checks.append(("D1 battle_layout_delete 被引用 BLOCK", (not ok) and "阻止" in str(msg),
                   "ok=%s msg=%s" % (ok, msg)))
    # D2 显式级联 → 成功，且 battle_001.layout 已清空
    ok2, msg2 = _sc.battle_layout_delete("grid_01", cascade=["battle_001"])
    btls = json.load(open(os.path.join(root, "data/configs/scenes/battles.json"), encoding="utf-8"))
    b = next(x for x in btls["battles"] if x["id"] == "battle_001")
    checks.append(("D2 battle_layout_delete 级联成功", ok2 and b.get("layout") == "",
                   "ok=%s msg=%s layout=%r" % (ok2, msg2, b.get("layout"))))
    # D3 无引用布局删除 → 成功
    _w(root, "data/configs/battles/grids/grid_02.json", {"name": "空布局", "width": 6, "height": 8})
    ok3, msg3 = _sc.battle_layout_delete("grid_02")
    checks.append(("D3 battle_layout_delete 无引用成功", ok3, "ok=%s msg=%s" % (ok3, msg3)))


def section_e(root, checks):
    """段 E：负向验收 NPC.dialog_id=UNKNOWN → Reference FAIL → Commit BLOCK。"""
    from data_sink import write_json, SinkRejected
    import studio_core as _sc
    _sc.set_project_root(root)
    p = os.path.join(root, "data/configs/regions/newbie_village/npcs.json")
    data = json.load(open(p, encoding="utf-8"))
    bad = dict(data["npcs"][0])
    bad["dialog_id"] = "UNKNOWN_DLG_999"
    data["npcs"][0] = bad
    try:
        write_json(root, p, data, note="Phase4 负向验收")
        checks.append(("E1 负向：悬空 dialog_id 被拦截", False, "未被拦截（写入了悬空引用）"))
    except SinkRejected as e:
        checks.append(("E1 负向：悬空 dialog_id 被拦截",
                       "⑤" in getattr(e, "step", "") or "ref_index" in getattr(e, "step", ""),
                       "step=%s" % getattr(e, "step", "?")))
    after = json.load(open(p, encoding="utf-8"))
    checks.append(("E2 负向：写入已回滚",
                   all(n.get("dialog_id") != "UNKNOWN_DLG_999" for n in after["npcs"]),
                   "after=%s" % [n.get("dialog_id") for n in after["npcs"]]))


def main():
    from services._common import load_settings, save_settings
    saved_root = None
    try:
        saved_root = load_settings().get("project_root")
    except Exception:
        saved_root = None
    d = make_temp_project()
    checks = []
    failures = []
    try:
        section_a(d, checks)
        section_b(d, checks)
        section_c(d, checks)
        section_d(d, checks)
        section_e(d, checks)
        for name, ok, msg in checks:
            if not ok:
                failures.append(name)
            print("  %s %s（%s）" % ("✓" if ok else "✗", name, msg))
    finally:
        # 恢复真实工程根（测试期间 set_project_root 改写了 settings）
        try:
            s = load_settings()
            if saved_root:
                s["project_root"] = saved_root
            else:
                s.pop("project_root", None)
            save_settings(s)
        except Exception:
            pass
        shutil.rmtree(d, ignore_errors=True)
    print("════ Phase 4 Reference 三件套：%s（失败 %d）════"
          % ("✓ 通过" if not failures else "✗ 未过", len(failures)))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
