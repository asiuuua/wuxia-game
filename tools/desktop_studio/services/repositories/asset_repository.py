# -*- coding: utf-8 -*-
"""AssetRepository —— 资产/UI 域数据访问（UI 布局·皮肤·映射·战棋布局·登录文案表）。

承载原 asset_service 中与文件打交道的写操作（14 处 save_json/save_text）：
  - data/configs/ui/*.json 各界面布局（登录背景 / 加载 / 主菜单 / HUD / 设置弹窗 / 读档弹窗）
  - data/configs/ui/skin/*（白名单三文件：theme / confirm_dialog / main_menu_vfx）
  - data/configs/ui/main_menu_assets.json 主菜单资源映射
  - data/configs/battles/grids/<lid>.json 战棋布局
  - data/configs/ui/login_bg_variants.json 登录背景多分辨率变体
  - data/configs/localization/strings.csv 登录界面文案表（与 LocalizationRepository 同文件，
    属登录 UI 资产域，由本仓按 utf-8-sig 写回）
写操作统一经 services.persistence（DataSink 六步收口），业务层不直接落盘。
"""

import json
import os

from services import persistence
from services.project_service import discover_project_root


# 皮肤文件白名单（与 asset_service.ui_skin_save 的校验口径一致）
SKIN_ALLOWED = {
    "theme": "theme.json",
    "confirm_dialog_layout": "confirm_dialog.layout.json",
    "main_menu_vfx": "main_menu.vfx.json",
}


class AssetRepository:
    """资产/UI 域数据访问对象（无状态；模块级单例 asset_repo）。"""

    # ---- 登录界面文案表（strings.csv）----
    def save_login_strings(self, text, note="", encoding="utf-8-sig"):
        path = os.path.join(discover_project_root(), "data", "configs", "localization", "strings.csv")
        persistence.save_text(path, text, note=note or "登录界面文案", encoding=encoding)

    # ---- 登录按钮背景映射 ----
    def login_btn_bg_cfg_path(self):
        return os.path.join(discover_project_root(), "data", "configs", "ui", "login_button_bg.json")

    def load_login_btn_bg_cfg(self):
        p = self.login_btn_bg_cfg_path()
        if not os.path.exists(p):
            return {}
        try:
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}

    def save_login_btn_bg_cfg(self, data, note=""):
        persistence.save_json(self.login_btn_bg_cfg_path(), data, note=note or "按钮背景映射")

    # ---- 各界面布局 ----
    def save_login_bg_layout(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "login_bg_layout.json")
        persistence.save_json(p, data, note=note or "登录背景布局")

    def save_loading_layout(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "loading_layout.json")
        persistence.save_json(p, data, note=note or "加载界面布局")

    def save_main_menu_layout(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "main_menu_layout.json")
        persistence.save_json(p, data, note=note or "主菜单布局")

    def save_hud_layout(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "hud_layout.json")
        persistence.save_json(p, data, note=note or "HUD 布局")

    def save_settings_screen_layout(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "skin", "settings_screen.layout.json")
        persistence.save_json(p, data, note=note or "设置弹窗布局")

    def save_saveload_screen_layout(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "skin", "saveload_screen.layout.json")
        persistence.save_json(p, data, note=note or "读档弹窗布局")

    # ---- UI 皮肤（白名单三文件）----
    def skin_path(self, kind):
        fn = SKIN_ALLOWED.get(kind)
        if not fn:
            return None
        return os.path.join(discover_project_root(), "data", "configs", "ui", "skin", fn)

    def save_ui_skin(self, kind, data, note=""):
        p = self.skin_path(kind)
        if p is None:
            raise ValueError("未知皮肤类型：%s" % kind)
        persistence.save_json(p, data, note=note or "UI 皮肤")

    # ---- 主菜单资源映射 ----
    def save_main_menu_assets(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "main_menu_assets.json")
        persistence.save_json(p, data, note=note or "主菜单资源映射")

    # ---- 战棋布局 ----
    def save_battle_layout(self, layout_id, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "battles", "grids", "%s.json" % layout_id)
        persistence.save_json(p, data, note=note or "战棋布局")

    # ---- 登录背景变体 ----
    def save_bg_variants(self, data, note=""):
        p = os.path.join(discover_project_root(), "data", "configs", "ui", "login_bg_variants.json")
        persistence.save_json(p, data, note=note or "登录背景变体")


asset_repo = AssetRepository()
