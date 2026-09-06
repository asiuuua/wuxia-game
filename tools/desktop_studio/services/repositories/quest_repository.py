# -*- coding: utf-8 -*-
"""QuestRepository —— 任务域数据访问（区域 quests.json 的 quest_graph 写回）。

承载原 quest_service 中与文件打交道的读写：
  - regions/<region>/quests.json（type == "quest_graph" 节点）
写操作统一经 services.persistence（DataSink 六步收口），业务层不直接落盘。
"""

import os

from services import persistence
from services._common import load_json
from services.project_service import discover_project_root


class QuestRepository:
    """任务域数据访问对象（无状态；模块级单例 quest_repo）。"""

    def quests_file(self, region):
        root = discover_project_root()
        return os.path.join(root, "data", "configs", "regions", str(region), "quests.json")

    def load_quests(self, region):
        return load_json(self.quests_file(region), {"quests": []})

    def save_quests(self, region, data, note=""):
        persistence.save_json(self.quests_file(region), data, note=note or "任务图")


quest_repo = QuestRepository()
