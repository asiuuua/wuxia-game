#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tools/check_crossref.py —— 区域配置自动对账（机场安检器）

扫描 data/configs/regions/ 下每个区域，把 index 点名册与各分片表互相核对，
揪出三种坏蛋：
  1. 点名册(list) 里写了 X，但对应分片表里没有 X           -> 目录与内容对不上
  2. 任务引用了不存在的战斗 / 物品 / 前置 flag(仅提示)     -> 引错 / 漏写
  3. 战斗列了 enemy_ids，但敌人表里没有该敌人               -> 赏了不存在的敌手

用法:
  python tools/check_crossref.py            # 检查全部区域
  python tools/check_crossref.py --region newbie_village
退出码: 0=全绿  1=有错误(ERR)  2=有警告(WARN)但无错误
"""
import argparse
import json
import os
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGIONS_DIR = os.path.join(PROJECT, "data", "configs", "regions")

# 需要校验"点名册 vs 分片表"的对照（区域里哪类文件对应哪种实体列表）
KIND_FILES = {
    "npcs":    "npcs.json",
    "quests":  "quests.json",
    "items":   "items.json",
    "battles": "battles.json",
    "enemies": "enemies.json",
}


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def entity_ids(data, kind):
    """从分片表里抽出该类的全部 id 集合。"""
    # 形如 { "npcs": [ {...}, {...} ] }
    arr = data.get(kind, [])
    return {e.get("id") for e in arr if isinstance(e, dict) and e.get("id")}


def region_entity_ids(region_dir, kind):
    return set()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", help="只检查指定区域（如 newbie_village）")
    args = ap.parse_args()

    errors, warns = [], []

    def err(msg): errors.append(msg)
    def warn(msg): warns.append(msg)

    # 收集要检查的区域目录
    region_dirs = []
    if args.region:
        target = os.path.join(REGIONS_DIR, args.region)
        if os.path.isdir(target):
            region_dirs.append(target)
        else:
            err(f"找不到区域目录: {target}")
            sys.exit(1)
    else:
        for name in sorted(os.listdir(REGIONS_DIR)):
            if name.startswith("_"):
                continue  # 跳过 _map_index.json 等系统文件
            p = os.path.join(REGIONS_DIR, name)
            if os.path.isdir(p):
                region_dirs.append(p)

    for rdir in region_dirs:
        rname = os.path.basename(rdir)
        ipath = os.path.join(rdir, "index.json")
        if not os.path.exists(ipath):
            err(f"[{rname}] 缺少 index.json 点名册")
            continue
        index = load_json(ipath)
        prefix = index.get("prefix", "")

        # ① 点名册 vs 分片表
        for kind, fname in KIND_FILES.items():
            listed = set(index.get(kind, []))
            fpath = os.path.join(rdir, fname)
            actual = set()
            if os.path.exists(fpath):
                actual = entity_ids(load_json(fpath), kind)
            for e in sorted(listed - actual):
                err(f"[{rname}] 点名册登记了 {kind}:{e}，但 {fname} 里查无此实体")
            for e in sorted(actual - listed):
                err(f"[{rname}] {fname} 存在 {kind}:{e}，但 point出名册 index.json 漏登记")

        # ② 对话分片对照
        dl_dir = os.path.join(rdir, "dialogs")
        listed_dl = set(index.get("dialogs", []))
        actual_dl = set()
        if os.path.isdir(dl_dir):
            for fn in os.listdir(dl_dir):
                if fn.endswith(".json"):
                    actual_dl.add(fn[:-5])
        for e in sorted(listed_dl - actual_dl):
            err(f"[{rname}] 点名册登记对白 {e}，但 dialogs/ 下无 {e}.json")
        for e in sorted(actual_dl - listed_dl):
            err(f"[{rname}] dialogs/{e}.json 存在，但 index.json 漏登记")

        # ③ 任务 → 战斗/物品 引用对照
        qpath = os.path.join(rdir, "quests.json")
        qdata = load_json(qpath) if os.path.exists(qpath) else {}
        battles = entity_ids(load_json(os.path.join(rdir, "battles.json")), "battles") if os.path.exists(os.path.join(rdir, "battles.json")) else set()
        items = entity_ids(load_json(os.path.join(rdir, "items.json")), "items") if os.path.exists(os.path.join(rdir, "items.json")) else set()
        for q in qdata.get("quests", []):
            qid = q.get("id")
            for obj in q.get("objectives", []):
                tb = obj.get("target_battle")
                if tb and tb not in battles:
                    err(f"[{rname}] 任务 {qid} 引用战斗 {tb}，但 battles.json 里没有")
                ni = obj.get("need_item")
                if ni and ni not in items:
                    err(f"[{rname}] 任务 {qid} 需要物品 {ni}，但 items.json 里没有")
            for rd in q.get("rewards", {}).get("items", []):
                ri = rd.get("item_id")
                if ri and ri not in items:
                    err(f"[{rname}] 任务 {qid} 奖励物品 {ri}，但 items.json 里没有")

        # ④ 敌人引用对照
        bpath = os.path.join(rdir, "battles.json")
        enemies = entity_ids(load_json(os.path.join(rdir, "enemies.json")), "enemies") if os.path.exists(os.path.join(rdir, "enemies.json")) else set()
        for b in load_json(bpath).get("battles", []):
            bid = b.get("id")
            for eid in b.get("enemy_ids", []):
                if eid not in enemies:
                    err(f"[{rname}] 战斗 {bid} 引用敌人 {eid}，但 enemies.json 里没有")

        # ⑤ NPC → 对话/任务/战斗 引用对照（空值跳过）
        npath = os.path.join(rdir, "npcs.json")
        for n in load_json(npath).get("npcs", []):
            nid = n.get("id")
            for field, pool, file in (("dialog_id", actual_dl, "dialogs/"),
                                      ("quest_id", entity_ids(qdata, "quests"), "quests.json"),
                                      ("battle_id", battles, "battles.json")):
                v = n.get(field)
                if v and v not in pool:
                    err(f"[{rname}] NPC {nid} 引用 {field}={v}，但 {file} 里没有")

        # ⑥ 命名规范：本区实体的 id 是否带本区前缀
        for kind, fname in KIND_FILES.items():
            fpath = os.path.join(rdir, fname)
            if not os.path.exists(fpath):
                continue
            for e in entity_ids(load_json(fpath), kind):
                if prefix and not e.startswith(prefix):
                    warn(f"[{rname}] {kind}:{e} 未以本区前缀 '{prefix}' 开头")

        # ⑦ 跨区 flag 引用提示（引到别区 flag 常见，属正常，仅当它不在本区前缀时提示）
        for q in qdata.get("quests", []):
            prereq = q.get("prerequisites", {})
            for k, v in prereq.items():
                if "_flag_" in k and not k.startswith(prefix):
                    warn(f"[{rname}] 任务 {q.get('id')} 前置引用跨区 flag: {k}")

    # 输出
    for w in warns:
        print(f"[WARN] {w}")
    for e in errors:
        print(f"[ERR ] {e}")

    n_region = len(region_dirs)
    print(f"\n== 共检查 {n_region} 个区域 | 警告 {len(warns)} 条 | 错误 {len(errors)} 条 ==")
    if not errors and not warns:
        print("== 全绿：点名册与分片表完全咬合 ✅ ==")
    elif not errors:
        print("== 通过（有警告，建议关注）⚠ ==")
    else:
        print("== 有错误，需修复 👇 ==")

    if errors:
        sys.exit(1)
    if warns:
        sys.exit(2)
    sys.exit(0)


if __name__ == "__main__":
    main()