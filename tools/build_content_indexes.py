#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""build_content_indexes.py — Build 期索引生成（05 图 DoD4 / CO-R03「Build 期生成，运行期只查不建」）

首批 2 张（DoD4）：npc_by_region（regions/<rid>/npcs.json 扫描）+ dialogue_by_npc（分片 _index.json 同源）。
产物：data/configs/content/indexes/<index_name>.json —— 运行期经 ContentRegistry.attach_index 注入
（缺失时 Registry 保留运行期兜底计算的过渡双轨，见 _ensure_indexes）。

用法: python tools/build_content_indexes.py
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGIONS_DIR = os.path.join(ROOT, "data", "configs", "regions")
OUT_DIR = os.path.join(ROOT, "data", "configs", "content", "indexes")


def build_npc_by_region() -> dict:
    idx = {}
    for rid in sorted(os.listdir(REGIONS_DIR)):
        npcs_file = os.path.join(REGIONS_DIR, rid, "npcs.json")
        if not os.path.isfile(npcs_file):
            continue
        with open(npcs_file, encoding="utf-8") as f:
            data = json.load(f)
        for npc in data.get("npcs", []):
            nid = str(npc.get("id", "")).strip()
            if nid:
                idx.setdefault(nid, [])
                if rid not in idx[nid]:
                    idx[nid].append(rid)
    return idx


def build_dialogue_by_npc() -> dict:
	"""dialogue_by_npc：从区域 npcs.json 的 dialog_id 字段反向派生（C-3 追认 Dialogue 主权——
	分片 npc_id 空置不代填，读侧索引由 NPC 侧 dialog_id 派生，不篡改源数据）。"""
	idx = {}
	for rid in sorted(os.listdir(REGIONS_DIR)):
		npcs_file = os.path.join(REGIONS_DIR, rid, "npcs.json")
		if not os.path.isfile(npcs_file):
			continue
		with open(npcs_file, encoding="utf-8") as f:
			data = json.load(f)
		for npc in data.get("npcs", []):
			nid = str(npc.get("id", "")).strip()
			did = str(npc.get("dialog_id", "")).strip()
			if nid and did:
				idx.setdefault(did, [])
				if nid not in idx[did]:
					idx[did].append(nid)
	return idx


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    produced = []
    for name, tbl in (("npc_by_region", build_npc_by_region()),
                      ("dialogue_by_npc", build_dialogue_by_npc())):
        out = os.path.join(OUT_DIR, "%s.json" % name)
        with open(out, "w", encoding="utf-8") as f:
            json.dump({"version": "1.0.0", "index": name, "entries": tbl},
                      f, ensure_ascii=False, indent=1, sort_keys=True)
        produced.append("%s（%d keys）" % (os.path.relpath(out, ROOT), len(tbl)))
    print("Build 期索引生成完成（CO-R03）：")
    for p in produced:
        print("  ✓ " + p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
