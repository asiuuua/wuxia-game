"""
模块注册中心 —— 工作室平台化的「插件总线」骨架（Phase 1 骨架，纯元数据层）。

当前阶段：只定义 Domain Module 的自描述清单（id/名称/角色可见性/功能列表/描述），
不移动任何业务函数。studio_core.py 的 200+ 函数仍原地运行，
但通过本注册表「挂名」到对应 Domain，为后续 Phase 1b（函数物理迁移到各模块文件）
和 Phase 3（RBAC 按角色过滤接口）提供数据源。

使用方式：
    from modules import get_modules_for_role, MODULE_REGISTRY

扩展方式：
    新增 Domain → 在 DOMAIN_MODULES 列表加一项，函数自动归属。
    新增工程版本 → 在 projects/ 下加一份 manifest.yaml。
"""

# ── 角色清单（与架构方案 §4 RBAC 一致）─────────────────
ROLES = {
    "super_admin": "超级管理员",
    "narrative_creator": "剧情创作者",
    "ui_artist": "UI 美术",
    "combat_designer": "战斗策划",
    "asset_manager": "资产管理员",
    "governance_clerk": "治理专员",
}

# ── 每个 Domain Module 可见哪些角色 ────────────────────────
DOMAIN_ROLE_MAP = {
    "ui_visual": ["super_admin", "ui_artist"],
    "narrative": ["super_admin", "narrative_creator"],
    "combat": ["super_admin", "combat_designer"],
    "asset": ["super_admin", "asset_manager"],
    "governance": ["super_admin", "governance_clerk"],
}

# ── Domain Module 自描述清单（Phase 1a：元数据，函数仍驻 studio_core.py）
#   functions 列表 = 该 Domain 当前在 studio_core.py 中拥有的函数名（精确匹配 def 名）
#   后续 Phase 1b：这些函数会从 studio_core.py 物理迁移到 modules/<domain>.py
DOMAIN_MODULES = [
    {
        "id": "ui_visual",
        "name": "UI 视觉模块",
        "description": "登录界面 / UI 贴图 / 预加载界面 / 主菜单布局 / 按钮背景 / 多分辨率变体",
        "functions": [
            "_login_bg_base", "_detect_image_ext", "_image_size", "_jpeg_size", "_webp_size",
            "clarity_report", "_patch_login_bg_refs", "_login_bg_path", "_login_strings_path",
            "_login_btn_bg_dir", "_login_btn_bg_cfg", "login_bg_info", "login_bg_replace",
            "login_texts", "login_texts_update", "login_version", "login_btn_bg_list",
            "login_btn_bg_set", "_login_bg_layout_path", "login_bg_layout", "login_bg_layout_update",
            "_loading_layout_path", "loading_layout_get", "loading_layout_update",
            "_main_menu_layout_path", "main_menu_layout_get", "main_menu_layout_update",
            "_main_menu_assets_path", "_main_menu_assets_dir", "main_menu_assets_get",
            "main_menu_assets_update", "_main_menu_asset_key_to_field", "_main_menu_asset_disk_path",
            "main_menu_asset_replace", "main_menu_asset_clear_icon",
            "_bg_variants_cfg_path", "_bg_variant_base", "_load_variants", "_save_variants",
            "login_bg_variants", "login_bg_variant_set", "login_bg_variant_remove",
            "login_btn_bg_clear", "login_btn_bg_scan_fix", "login_btn_bg_file",
            "_purge_import_cache_for", "ui_screens_list", "_slot_to_fname",
            "ui_slot_upload", "ui_slot_clear", "ui_bg_add",
            "_tscn_backup_dir", "_tscn_ready", "ui_slot_disk_path", "ui_slot_file",
        ],
    },
    {
        "id": "narrative",
        "name": "剧情创作模块",
        "description": "NPC 数据 / 剧情对话树 / 欢庆模块（结缘 CG / 台词 / BGM）",
        "functions": [
            "npc_portrait_import", "npc_portrait_clear", "npc_list", "npc_get",
            "npc_upsert", "npc_delete", "npc_rename",
            "dlg_list", "dlg_get", "dlg_new", "dlg_line_upsert",
            "dlg_line_delete", "dlg_delete",
            "cel_list", "cel_get", "cel_upsert", "cel_delete", "_shard_path",
        ],
    },
    {
        "id": "combat",
        "name": "战斗关卡模块",
        "description": "战棋布局可视化编辑器 / 战斗背景图 / Demo 立绘",
        "functions": [
            "_battle_layout_dir", "_battle_bg_dir", "_detect_existing_bg",
            "battle_layout_list", "battle_layout_get", "battle_layout_save",
            "battle_layout_delete", "battle_layout_preset",
            "_battle_bg_path_for", "battle_bg_upload", "battle_bg_clear",
            "demo_portrait_list", "_demo_portrait_path_for", "demo_portrait_file",
            "demo_portrait_upload", "demo_portrait_reset",
        ],
    },
    {
        "id": "asset",
        "name": "资产资源模块",
        "description": "立绘一键导入(静态/帧动画/Spine) / 回收站 / 备份 / 自动清理",
        "functions": [
            "trash_put", "trash_list", "_trash_path", "trash_restore",
            "trash_purge", "auto_cleanup", "_backup_dir",
        ],
    },
    {
        "id": "governance",
        "name": "系统治理模块",
        "description": "设置 / 操作日志 / 待办清单 / 协同启动卡 / 总控台(未来) / 元数据中心(未来)",
        "functions": [
            "load_settings", "save_settings", "discover_project_root", "set_project_root",
            "_has_project_marker", "_paths", "_user_data_dir", "_ensure_dirs",
            "tool_version", "_exe_dir", "log_event", "read_log", "_now",
            "self_test", "backlog_get", "_ensure_gdignore",
        ],
    },
]

# ── 公开 API ────────────────────────────────────────────────
MODULE_REGISTRY = DOMAIN_MODULES


def get_modules_for_role(role: str):
    """按角色返回该角色有权限看到的 Domain Module 清单。

    super_admin 返回全部；其他角色按 DOMAIN_ROLE_MAP 过滤。
    """
    if role == "super_admin":
        return [m.copy() for m in MODULE_REGISTRY]
    return [m for m in MODULE_REGISTRY if role in DOMAIN_ROLE_MAP.get(m["id"], [])]


def get_function_domain(func_name: str):
    """查某个函数属于哪个 Domain（用于后续路由分发）。"""
    for mod in DOMAIN_MODULES:
        if func_name in mod.get("functions", []):
            return mod["id"]
    return None
