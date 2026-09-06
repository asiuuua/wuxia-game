#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""武侠游戏「内容工作室」桌面版 —— 门面（Facade）层。

Phase 1 拆分后，全部业务逻辑已迁入 services/ 七域服务（施工图 §5.2）：
  npc_service / dialogue_service / quest_service / localization_service
  asset_service / audit_service / project_service
共享基础设施（路径 / 设置 / ID 校验 / 备份 / 日志）在 services/_common.py；
写收口（save_json / save_text + DataSink 六步）在 services/persistence.py。

本文件职责：
  1) 按域 import services 并在模块级转发全部对外函数与常量（保持旧调用方 core.xxx 兼容）；
  2) 不再实现任何业务逻辑；
  3) 新代码请直接 import services.<域>_service，不要再新增对 studio_core 的依赖。
"""

import os
import sys

MODULE_DIR = os.path.dirname(os.path.abspath(__file__))
TOOLS_DIR = os.path.dirname(MODULE_DIR)          # tools/（data_sink 所在层）
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

# ---------------- 共享基础设施（含常量，单一来源 services/_common） ----------------
from services._common import (  # noqa: F401
    _user_data_dir, _ensure_dirs, load_settings, save_settings,
    _safe_id, _is_valid_id, load_json, _backup, _backup_dir,
    SAFETY_DIR, TRASH_DIR, BACKUP_DIR, SETTINGS_PATH, LOG_PATH,
    DEFAULT_PROJECT_ROOT, DEFAULT_PORT, DEFAULT_RETENTION_DAYS, DEFAULT_SAFE_MODE,
)

# ---------------- 写收口（DataSink 六步，业务层唯一落盘通道） ----------------
from services.persistence import save_text, save_json  # noqa: F401

# ---------------- 工程域 ----------------
from services.project_service import (  # noqa: F401
    _exe_dir, tool_version, _has_project_marker, set_project_root,
    discover_project_root, _paths, _half_body_dir, _shard_path, backlog_get,
)

# ---------------- 审计与运维域 ----------------
from services.audit_service import (  # noqa: F401
    log_event, read_log, _now, trash_put, trash_list, _trash_path,
    trash_restore, trash_purge, auto_cleanup, self_test,
)

# ---------------- NPC 域（含欢庆） ----------------
from services.npc_service import (  # noqa: F401
    npc_portrait_import, npc_portrait_clear, npc_asset_upload, npc_half_body_file,
    _all_region_ids, _default_region, _region_npc_file, _load_region_file,
    _load_all_region_npcs, _remove_npc_from_region, npc_list, npc_get,
    _upsert_target_region, npc_upsert, npc_delete, npc_rename,
    npc_stats_get, npc_stats_upsert, cel_list, cel_get, cel_upsert, cel_delete,
)

# ---------------- 对话域 ----------------
from services.dialogue_service import (  # noqa: F401
    dlg_list, dlg_get, dlg_new, dlg_line_upsert, dlg_line_delete, dlg_delete,
)

# ---------------- 任务域 ----------------
from services.quest_service import (  # noqa: F401
    quest_graph_list, quest_graph_get, _find_graph_refs, quest_graph_save,
)

# ---------------- 本地化域 ----------------
from services.localization_service import (  # noqa: F401
    _i18n_path, i18n_read, i18n_list, i18n_upsert,
)

# ---------------- 资源域（含资产常量） ----------------
from services.asset_service import (  # noqa: F401
    _ensure_gdignore, _detect_image_ext, _image_size, _jpeg_size, _webp_size,
    clarity_report, _login_bg_base, _login_bg_ref_files, _patch_login_bg_refs,
    _login_bg_path, _login_strings_path, _login_btn_bg_dir, _login_btn_bg_cfg,
    login_bg_info, login_bg_replace, login_texts, login_texts_update, login_version,
    login_btn_bg_list, login_btn_bg_set, _login_bg_layout_path, login_bg_layout,
    login_bg_layout_update, _loading_layout_path, loading_layout_get,
    loading_layout_update, _main_menu_layout_path, main_menu_layout_get,
    main_menu_layout_update, _hud_layout_path, _is_num, hud_layout_get,
    hud_layout_update, _settings_screen_layout_path, settings_screen_layout_get,
    settings_screen_layout_update, _SAVELOAD_SCREEN_LAYOUT_DEFAULT,
    _saveload_screen_layout_path, saveload_screen_layout_get,
    saveload_screen_layout_update, _ui_skin_dir, _ui_skin_path, ui_skin_get,
    ui_skin_save, _main_menu_assets_path, _main_menu_assets_dir, _clamp_icon_scale,
    _clamp_hover_shift_x, _clamp_hover_shift_y, main_menu_assets_get,
    main_menu_assets_update, main_menu_icon_scales_set, main_menu_hover_shift_set,
    _main_menu_asset_key_to_field, _main_menu_asset_disk_path,
    main_menu_asset_replace, main_menu_asset_clear_icon, _battle_layout_dir,
    _battle_bg_dir, _detect_existing_bg, battle_layout_list, battle_layout_get,
    battle_layout_save, battle_layout_delete, battle_layout_preset,
    _battle_bg_path_for, battle_bg_upload, battle_bg_clear, demo_portrait_list,
    _demo_portrait_path_for, demo_portrait_file, demo_portrait_upload,
    demo_portrait_reset, _purge_import_cache_for, login_btn_bg_clear,
    login_btn_bg_scan_fix, login_btn_bg_file, _bg_variants_cfg_path,
    _bg_variant_base, _load_variants, _save_variants, login_bg_variants,
    login_bg_variant_set, login_bg_variant_remove, _tscn_backup_dir, _tscn_ready,
    ui_screens_list, _slot_to_fname, ui_slot_upload, ui_slot_clear, ui_bg_add,
    ui_slot_disk_path, ui_slot_file,
    CLARITY_TARGETS, LOGIN_TEXT_KEYS, _LOGIN_BG_LAYOUT_DEFAULT, LOADING_ELEMS,
    _LOADING_LAYOUT_DEFAULT, MAIN_MENU_ELEMS, _MAIN_MENU_LAYOUT_DEFAULT,
    _HUD_LAYOUT_DEFAULT, _HUD_PANEL_KEYS, _HUD_REF_W, _HUD_REF_H, _HUD_SCALE_MIN,
    _HUD_SCALE_MAX, _SETTINGS_SCREEN_LAYOUT_DEFAULT, _SETTINGS_SCREEN_LAYOUT_KEYS,
    _SAVELOAD_SCREEN_LAYOUT_KEYS, _DEFAULT_MAIN_MENU_ASSETS, _DEMO_PORTRAIT_TARGETS,
)



# ---------------- Dependency Graph：impact 分析（Phase 5，删除确认弹窗用） ----------------
def impact_of(kind, eid):
    """Content Graph 影响分析：改 kind/eid 会影响哪些实体（可传递）。
    返回 {kind: [ids...]}。供前端删除确认弹窗展示「删除此 NPC 将影响 X 个对话、Y 个任务」。
    失败时返回空 dict（降级：不影响删除流程）。"""
    try:
        import dep_graph
        return dep_graph.content_impact(kind, eid)
    except Exception:
        return {}