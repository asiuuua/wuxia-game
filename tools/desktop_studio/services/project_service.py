# -*- coding: utf-8 -*-
"""工程域服务：工程根解析 / 版本标识 / 数据路径表 / 待办读取。

职责边界：只做「工程是什么、工程在哪儿、数据文件在哪儿」的只读解析，
不写任何业务数据（写操作在各自域 service，经 _common.save_json 收口）。
"""

import os
import sys
import json
import re
import hashlib
import datetime

from services import _common
from services._common import (  # noqa: F401  门面透传用
    _safe_id, _is_valid_id, _ensure_dirs, load_settings, save_settings,
    SAFETY_DIR, TRASH_DIR, BACKUP_DIR, SETTINGS_PATH, LOG_PATH,
    DEFAULT_PROJECT_ROOT, DEFAULT_PORT, DEFAULT_RETENTION_DAYS, DEFAULT_SAFE_MODE,
)


def _exe_dir():
    # PyInstaller 打包后是 exe 真实所在目录；脚本模式是 .py 所在目录
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(sys.argv[0]))


def tool_version():
    """返回工具自身版本标识：exe 修改时间 + md5 前8位 + 当前生效工程根目录，用于首页状态栏显示。"""
    exe_path = None
    if getattr(sys, "frozen", False):
        exe_path = sys.executable
    else:
        # 脚本模式：取本脚本自身
        exe_path = os.path.abspath(__file__)
    try:
        st = os.stat(exe_path)
        mtime = datetime.datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
        h = hashlib.md5()
        with open(exe_path, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""):
                h.update(b)
        md5 = h.hexdigest()[:8]
        return {"build_time": mtime, "md5": md5, "path": exe_path,
                "root": discover_project_root()}
    except Exception as e:
        return {"build_time": "unknown", "md5": "unknown", "path": str(exe_path),
                "root": discover_project_root(), "error": str(e)}


def _has_project_marker(root):
    if not root or not os.path.isdir(root):
        return False
    if os.path.exists(os.path.join(root, "project.godot")):
        return True
    if os.path.exists(os.path.join(root, "data", "configs", "npcs", "town_npcs.json")):
        return True
    return False


def set_project_root(root):
    """手动设置工程根目录（前端"选择工程"或 --root 参数调用），持久化到设置并即时生效。"""
    root = (root or "").strip()
    if not root:
        return False, "路径为空"
    if not _has_project_marker(root):
        return False, "该目录不是有效的武侠游戏工程（缺少 project.godot 或 data/configs/npcs/town_npcs.json）"
    s = load_settings()
    s["project_root"] = root
    save_settings(s)
    return True, root


def discover_project_root():
    """解析工程根目录：优先用设置里的值；否则从 exe 所在目录向上查找带工程标记( project.godot / town_npcs.json )的文件夹；
    找不到才回退默认路径。这样把 exe 连同 data 一起发给别人时，无需改设置即可定位。"""
    s = load_settings()
    stored = s.get("project_root", "")
    if stored and _has_project_marker(stored):
        return stored
    # 兜底：设置里的值存在但当前不可达（如工程被挪走），也允许返回它，让前端提示用户重新选择
    if stored:
        return stored
    start = _exe_dir()
    for _ in range(5):
        if _has_project_marker(start):
            s["project_root"] = start
            save_settings(s)
            return start
        parent = os.path.dirname(start)
        if parent == start:
            break
        start = parent
    return DEFAULT_PROJECT_ROOT


def _paths():
    root = discover_project_root()
    return {
        "npc": os.path.join(root, "data", "configs", "npcs", "town_npcs.json"),
        "npc_stats": os.path.join(root, "data", "configs", "npcs", "npc_stats.json"),
        "dlg_index": os.path.join(root, "data", "configs", "npcs", "dialogs", "_index.json"),
        "dlg_dir": os.path.join(root, "data", "configs", "npcs", "dialogs", "shards"),
        "cel": os.path.join(root, "data", "configs", "bond", "celebrations.json"),
        "assets": os.path.join(root, "assets"),
    }


# 半身立绘（动态可导入）资源根目录：assets/characters/half_body/
def _half_body_dir():
    return os.path.join(_paths()["assets"], "characters", "half_body")


def _shard_path(dlg_id):
    return os.path.join(_paths()["dlg_dir"], "%s.json" % dlg_id)


def backlog_get():
    """读取工程 docs/backlog.json（模块化待办清单），返回 dict；缺失/损坏时回退友好信息。"""
    p = os.path.join(discover_project_root(), "docs", "backlog.json")
    if not os.path.exists(p):
        return {"ok": False, "error": "未找到 docs/backlog.json（请先用 tools/gen_backlog.py 生成）"}
    try:
        with open(p, "r", encoding="utf-8") as f:
            data = json.load(f)
        data["ok"] = True
        return data
    except Exception as e:
        return {"ok": False, "error": "backlog.json 解析失败：%s" % e}
