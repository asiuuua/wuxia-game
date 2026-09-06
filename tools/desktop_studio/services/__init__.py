# -*- coding: utf-8 -*-
"""内容工作室域服务包（Phase 1 拆分产物）。

studio_core.py 原为 130KB 大一统模块，现按域拆为七个 service：
  npc_service / dialogue_service / quest_service / localization_service
  asset_service / audit_service / project_service
共享基础设施（路径 / ID 校验 / DataSink 写收口 / 备份 / 日志）在 _common.py。
studio_core 保留为门面（Facade），仅做转发，不再实现业务逻辑（施工图 §5.2）。
"""
