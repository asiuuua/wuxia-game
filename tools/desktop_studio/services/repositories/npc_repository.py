# -*- coding: utf-8 -*-
"""NPCRepository —— NPC 域数据访问（区域表 / 详细资料 / 欢庆内容）。

承载原 npc_service 中与文件打交道的读写：
  - regions/<rid>/npcs.json 区域表（NPC 唯一来源，town_npcs.json 只读留档）
  - data/configs/npcs/npc_stats.json 详细资料
  - data/configs/bond/celebrations.json 欢庆内容
写操作统一经 services.persistence（DataSink 六步收口），业务层不直接落盘。
"""

import os

from services import persistence
from services._common import load_json
from services.project_service import discover_project_root, _paths


class NPCRepository:
    """NPC 域数据访问对象（无状态；模块级单例 npc_repo）。"""

    def region_file(self, rid):
        root = discover_project_root()
        return os.path.join(root, "data", "configs", "regions", str(rid), "npcs.json")

    def all_region_ids(self):
        """所有已建区域的目录名（含 npcs.json 的）列表，按目录名排序。"""
        regions_dir = os.path.join(discover_project_root(), "data", "configs", "regions")
        out = []
        if os.path.isdir(regions_dir):
            for rid in sorted(os.listdir(regions_dir)):
                if os.path.isfile(os.path.join(regions_dir, rid, "npcs.json")):
                    out.append(rid)
        return out

    def load_region(self, rid):
        """读某区域 NPC 表；目录/文件缺失则返回空结构并确保父目录存在。返回 (path, data)。"""
        p = self.region_file(rid)
        try:
            os.makedirs(os.path.dirname(p), exist_ok=True)
        except Exception:
            pass
        data = load_json(p, {"npcs": []})
        if not isinstance(data, dict):
            data = {"npcs": []}
        data.setdefault("npcs", [])
        return p, data

    def save_region(self, rid, data, note=""):
        persistence.save_json(self.region_file(rid), data, note=note or "NPC 区域表")

    def load_npc_stats(self):
        return load_json(_paths()["npc_stats"], {})

    def save_npc_stats(self, data, note=""):
        persistence.save_json(_paths()["npc_stats"], data, note=note or "NPC 详细资料")

    def load_celebrations(self):
        return load_json(_paths()["cel"], {})

    def save_celebrations(self, data, note=""):
        persistence.save_json(_paths()["cel"], data, note=note or "欢庆内容")


npc_repo = NPCRepository()
