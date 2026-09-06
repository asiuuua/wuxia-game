# -*- coding: utf-8 -*-
"""域 Repository 包（Phase 2）：数据访问层，业务域 service 唯一的落盘入口。

每个 Repository 只处理自己域的工程数据文件（§28 Repository Boundary）：
  npc_repository          — 区域 NPC 表 regions/<rid>/npcs.json / npc_stats.json / celebrations.json
  dialogue_repository     — 对话索引 _index.json / 分片 shards/<id>.json
  quest_repository        — regions/<region>/quests.json（quest_graph）
  localization_repository — data/configs/localization/strings.csv
  asset_repository        — data/configs/ui/* 布局·皮肤·映射 / battles/grids 布局 / 登录文案表

写操作一律经 services.persistence（DataSink 六步收口）；本包不实现业务逻辑、
不 import 任何域 service（防环）。业务层经模块级单例（npc_repo 等）使用。
"""
