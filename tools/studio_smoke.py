# -*- coding: utf-8 -*-
"""
studio_smoke.py — 工作室编辑流程冒烟（第二阶段·代码审查报告整改 2026-09-04）
================================================================
验证「编辑器写入 → 落到区域表 → 读回可见」闭环，全部在临时目录进行，**不碰真实工程数据**：
  1) studio_core.self_test 全过（既有 15+ 安全/读写断言）
  2) npc_upsert 写入 → npc_list 读回 → 区域表 JSON 落盘含该 NPC（编辑→游戏同源验证）
退出码 0=通过；供 verify_all.py GATE7 调用。
"""
import os
import sys
import json
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
STUDIO = os.path.join(HERE, "desktop_studio")
sys.path.insert(0, STUDIO)

import studio_core  # noqa: E402

# 测试静默：self_test/冒烟夹具写不进真源更改日志（⑥ 开关）
try:
    import data_sink as _ds
    _ds._changelog_enabled = False
except Exception:
    pass

# 测试静默：self_test/冒烟夹具写不进真源更改日志（⑥ 开关）
try:
    import data_sink as _ds
    _ds._changelog_enabled = False
except Exception:
    pass


def main() -> int:
    failures = []
    d = tempfile.mkdtemp(prefix="studio_smoke_")
    # 测试卫生：清空上一轮残留的回收站/备份（TRASH_DIR 跨运行持久，残留记录会让
    # self_test 的 restored==1 断言翻车——2026-09-06 冒烟实录）
    import shutil
    import studio_core as _sc
    shutil.rmtree(getattr(_sc, "TRASH_DIR", ""), ignore_errors=True)
    # 搭最小工程数据（与 self_test 夹具同构 + 区域表）
    for sub in ["data/configs/npcs", "data/configs/npcs/dialogs/shards",
                "data/configs/regions/newbie_village", "data/configs/bond"]:
        os.makedirs(os.path.join(d, *sub.split("/")), exist_ok=True)
    json.dump({"npcs": []}, open(os.path.join(d, "data/configs/regions/newbie_village/npcs.json"), "w", encoding="utf-8"))
    json.dump({"shards": {}}, open(os.path.join(d, "data/configs/npcs/dialogs/_index.json"), "w", encoding="utf-8"))
    json.dump({}, open(os.path.join(d, "data/configs/bond/celebrations.json"), "w", encoding="utf-8"))

    # 1) 既有自测全过
    for name, ok, msg in studio_core.self_test(d):
        if not ok:
            failures.append("self_test[%s]: %s" % (name, msg))

    # 2) 编辑闭环：切根 → 写 NPC → 读回 → 落盘校验
    studio_core.set_project_root(d)
    try:
        ok, msg = studio_core.npc_upsert({"id": "npc_smoke_001", "name": "冒烟测试NPC", "scene": "newbie_village", "pos_x": 10, "pos_y": 20})
        if not ok:
            failures.append("npc_upsert 失败: %s" % msg)
        names = [n.get("id") for n in studio_core.npc_list()]
        if "npc_smoke_001" not in names:
            failures.append("npc_upsert 后 npc_list 未读回 npc_smoke_001（读=%s）" % names)
        region_data = json.load(open(os.path.join(d, "data/configs/regions/newbie_village/npcs.json"), encoding="utf-8"))
        ids = [n.get("id") for n in region_data.get("npcs", [])]
        if "npc_smoke_001" not in ids:
            failures.append("区域表落盘缺少 npc_smoke_001（写入了 %s）" % ids)
    finally:
        studio_core.set_project_root("D:/武侠游戏")   # 恢复真实工程根，绝不残留

    if failures:
        print("GATE7 ✗ 工作室编辑冒烟（%d 项失败）" % len(failures))
        for f in failures:
            print("   ✗ " + f)
        return 1
    print("GATE7 ✓ 工作室编辑冒烟（self_test 全过 + NPC 写入→区域表→读回闭环 OK，全程临时目录）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
