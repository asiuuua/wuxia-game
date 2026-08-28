#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
武侠游戏 · 剧情导入器（零代码数据工具）
=====================================
把 5 张 CSV 模板（人物/任务/战斗/敌人/物品）合并进游戏的 data/configs JSON。
游戏运行时直接读取这些 JSON，因此：你只填表 → 双击 run.bat → 剧情/人物/战斗/物品就进游戏了。

安全原则：
  - 按 id 合并；已存在的 id 自动跳过，绝不覆盖、绝不重复。
  - 模板里带 demo_ 前缀的是示例，导入你自己的内容前把 demo_ 行删掉即可。
  - 纯 Python 标准库，无需安装任何包。

用法：
  双击 run.bat
  或命令行：python convert.py
"""
import csv
import json
import os

BASE = os.path.dirname(os.path.abspath(__file__))
# BASE = D:/武侠游戏/tools/story_import  →  项目根 = 上两级
ROOT = os.path.abspath(os.path.join(BASE, "..", ".."))
DATA = os.path.join(ROOT, "data", "configs")

ITEM_ROUTE = {
    "weapon": "items/weapons.json",
    "pill": "items/pills.json",
    "material": "items/materials.json",
    "armor": "items/equipment.json",
    "accessory": "items/equipment.json",
    "equipment": "items/equipment.json",
}


# ---------- 读取工具 ----------
def load_csv(name):
    path = os.path.join(BASE, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def read_json(rel):
    path = os.path.join(DATA, rel)
    if not os.path.exists(path):
        return {"version": "1.0.0"}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def write_json(rel, data):
    path = os.path.join(DATA, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def cell(row, key, default=""):
    v = row.get(key)
    return (v or default)


def merge(arr, new_entries, id_key="id"):
    """返回合并后的列表，打印跳过/新增。"""
    existing = set()
    for e in arr:
        if isinstance(e, dict) and id_key in e:
            existing.add(e[id_key])
    added = 0
    for e in new_entries:
        eid = e.get(id_key, "")
        if not eid:
            continue
        if eid in existing:
            print("  跳过(已存在): %s" % eid)
            continue
        arr.append(e)
        existing.add(eid)
        added += 1
    return added


# ---------- 各模板 → 游戏数据结构 ----------
def build_npcs(rows):
    out = []
    for r in rows:
        nid = cell(r, "npc_id").strip()
        if not nid:
            continue
        dialogs = []
        for i in range(1, 5):
            sp = cell(r, "对话%d说话人" % i).strip()
            tx = cell(r, "对话%d内容" % i).strip()
            if tx:
                dialogs.append({"speaker": sp, "text": tx})
        out.append({
            "id": nid,
            "name": cell(r, "名字").strip(),
            "pos_x": int(cell(r, "x坐标") or 0),
            "pos_y": int(cell(r, "y坐标") or 0),
            "sprite": cell(r, "立绘路径").strip(),
            "portrait": cell(r, "头像路径").strip(),
            "dialogs": dialogs,
            "quest_id": cell(r, "任务id").strip(),
            "battle_id": cell(r, "战斗id").strip(),
        })
    return out


def build_quests(rows):
    out = []
    for r in rows:
        qid = cell(r, "任务id").strip()
        if not qid:
            continue
        objectives = [{
            "id": "obj1",
            "desc": cell(r, "目标描述").strip(),
            "target_battle": cell(r, "目标战斗id").strip(),
            "need": int(cell(r, "需要数量") or 1),
        }]
        rewards = {"exp": int(cell(r, "奖励经验") or 0)}
        silver = int(cell(r, "奖励银两") or 0)
        if silver > 0:
            rewards["silver"] = silver
        item_id = cell(r, "奖励物品id").strip()
        if item_id:
            rewards["items"] = [{"item_id": item_id, "count": int(cell(r, "奖励物品数量") or 1)}]
        ability = cell(r, "奖励武学id").strip()
        if ability:
            rewards["abilities"] = [ability]
        out.append({
            "id": qid,
            "name": cell(r, "任务名").strip(),
            "desc": cell(r, "描述").strip(),
            "type": cell(r, "类型").strip() or "side",
            "objectives": objectives,
            "rewards": rewards,
        })
    return out


def build_battles(rows):
    out = []
    for r in rows:
        bid = cell(r, "战斗id").strip()
        if not bid:
            continue
        eids = [cell(r, "敌人id%d" % i).strip() for i in range(1, 4)]
        eids = [e for e in eids if e]
        out.append({
            "id": bid,
            "name": cell(r, "战斗名").strip(),
            "enemy_ids": eids,
            "reward_exp": int(cell(r, "奖励经验") or 0),
        })
    return out


def build_enemies(rows):
    out = []
    for r in rows:
        eid = cell(r, "敌人id").strip()
        if not eid:
            continue
        ability = cell(r, "武学id1").strip()
        abilities = [ability] if ability else []
        loot = []
        for i in range(1, 3):
            iid = cell(r, "掉落物品id%d" % i).strip()
            if iid:
                loot.append({"item_id": iid, "count": int(cell(r, "掉落数量%d" % i) or 1)})
        out.append({
            "id": eid,
            "name": cell(r, "名字").strip(),
            "hp": int(cell(r, "血量") or 10),
            "attack": int(cell(r, "攻击") or 5),
            "speed": int(cell(r, "速度") or 5),
            "abilities": abilities,
            "loot": loot,
        })
    return out


def build_items(rows):
    """按类型路由到不同物品文件，返回 {相对路径: [新增条目]}。"""
    buckets = {v: [] for v in ITEM_ROUTE.values()}
    for r in rows:
        iid = cell(r, "物品id").strip()
        if not iid:
            continue
        t = cell(r, "类型").strip() or "material"
        if t not in ITEM_ROUTE:
            print("  [警告] 未知物品类型跳过: %s (类型=%s)" % (iid, t))
            continue
        it = {
            "id": iid,
            "name": cell(r, "名字").strip(),
            "type": t,
            "rarity": cell(r, "稀有度").strip() or "common",
            "max_stack": int(cell(r, "最大堆叠") or 1),
            "weight": float(cell(r, "重量") or 1.0),
            "price": int(cell(r, "价格") or 10),
        }
        if t == "weapon":
            atk = int(cell(r, "攻击") or 10)
            it["attack"] = atk
            it["bonus_attack"] = atk
            it["durability"] = 100
            it["speed"] = 1.0
            it["equip_slot"] = "main_hand"
        elif t == "pill":
            it["heal_hp"] = int(cell(r, "治疗血量") or 0)
            it["heal_mp"] = int(cell(r, "治疗内力") or 0)
        elif t in ("armor", "accessory", "equipment"):
            it["flags"] = 64
            it["equip_slot"] = "armor" if t == "armor" else ("accessory" if t == "accessory" else "armor")
            if int(cell(r, "防御") or 0) > 0:
                it["bonus_defense"] = int(cell(r, "防御"))
            if int(cell(r, "血量") or 0) > 0:
                it["bonus_hp"] = int(cell(r, "血量"))
            if int(cell(r, "内力") or 0) > 0:
                it["bonus_mp"] = int(cell(r, "内力"))
        else:  # material
            it["flags"] = 16
        buckets[ITEM_ROUTE[t]].append(it)
    return buckets


# ---------- 主流程 ----------
def main():
    print("=== 武侠游戏 剧情导入器 ===")
    print("项目根: %s" % ROOT)
    print("数据目录: %s" % DATA)
    print("")

    npc_rows = load_csv("人物模板.csv")
    quest_rows = load_csv("任务模板.csv")
    battle_rows = load_csv("战斗模板.csv")
    enemy_rows = load_csv("敌人模板.csv")
    item_rows = load_csv("物品模板.csv")

    # NPC
    npc_data = read_json("npcs/town_npcs.json")
    if "npcs" not in npc_data:
        npc_data["npcs"] = []
    n = merge(npc_data["npcs"], build_npcs(npc_rows))
    write_json("npcs/town_npcs.json", npc_data)
    print("[人物] 新增 %d 个 NPC（含对话）" % n)

    # Quest
    quest_data = read_json("quests/quests.json")
    if "quests" not in quest_data:
        quest_data["quests"] = []
    q = merge(quest_data["quests"], build_quests(quest_rows))
    write_json("quests/quests.json", quest_data)
    print("[任务] 新增 %d 个任务" % q)

    # Battle
    battle_data = read_json("scenes/battles.json")
    if "battles" not in battle_data:
        battle_data["battles"] = []
    b = merge(battle_data["battles"], build_battles(battle_rows))
    write_json("scenes/battles.json", battle_data)
    print("[战斗] 新增 %d 场战斗" % b)

    # Enemy
    enemy_data = read_json("npcs/enemies.json")
    if "enemies" not in enemy_data:
        enemy_data["enemies"] = []
    e = merge(enemy_data["enemies"], build_enemies(enemy_rows))
    write_json("npcs/enemies.json", enemy_data)
    print("[敌人] 新增 %d 个敌人" % e)

    # Item（按类型分文件）
    item_buckets = build_items(item_rows)
    total_items = 0
    for rel, entries in item_buckets.items():
        if not entries:
            continue
        d = read_json(rel)
        if "items" not in d:
            d["items"] = []
        added = merge(d["items"], entries)
        write_json(rel, d)
        total_items += added
        print("[物品→%s] 新增 %d 个" % (rel, added))
    print("[物品] 合计新增 %d 个" % total_items)

    print("")
    print("=== 导入完成 ===")
    print("下一步：用 Godot 打开工程 → 进城镇 → 找到你填的 NPC 对话即可触发任务/战斗。")
    print("（想清掉示例：删除 data 里所有 demo_ 开头的条目，或把模板中的 demo_ 行删掉重跑。）")


if __name__ == "__main__":
    main()
