# -*- coding: utf-8 -*-
"""DialogueRepository —— 对话域数据访问（索引 / 分片）。

承载原 dialogue_service 中与文件打交道的读写：
  - data/configs/npcs/dialogs/_index.json 对话索引
  - data/configs/npcs/dialogs/shards/<dlg_id>.json 对话分片
写操作统一经 services.persistence（DataSink 六步收口），业务层不直接落盘。
"""

from services import persistence
from services._common import load_json
from services.project_service import _paths, _shard_path


class DialogueRepository:
    """对话域数据访问对象（无状态；模块级单例 dialogue_repo）。"""

    def load_index(self):
        return load_json(_paths()["dlg_index"], {"shards": {}})

    def save_index(self, idx, note=""):
        persistence.save_json(_paths()["dlg_index"], idx, note=note or "对话索引")

    def load_shard(self, dlg_id):
        return load_json(_shard_path(dlg_id), {"id": dlg_id, "lines": []})

    def save_shard(self, dlg_id, shard, note=""):
        persistence.save_json(_shard_path(dlg_id), shard, note=note or "对话分片")


dialogue_repo = DialogueRepository()
