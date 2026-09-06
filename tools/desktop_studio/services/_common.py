# -*- coding: utf-8 -*-
"""共享基础设施层：路径常量 / 设置 / ID 校验 / JSON 读取 / 备份。

仅依赖标准库，不 import 任何 service，保证无循环依赖。
写收口（save_json / save_text + DataSink 六步）已迁至 persistence.py；
本层只保留只读与 Studio 自身设施（settings / trash / backup / log）。
"""

import os
import sys
import json
import copy
import shutil
import threading
import datetime

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _user_data_dir():
    # 打包成单文件 exe 后，__file__ 位于临时解压目录(_MEI)，进程退出即清空；
    # 为保证 设置 / 回收站 / 备份 / 日志 能跨启动保存，改存到用户本地数据目录。
    if getattr(sys, "frozen", False):
        base = os.path.join(os.path.expanduser("~"), "AppData", "Local", "StudioProTool")
    else:
        base = MODULE_DIR
    return base


SAFETY_DIR = os.path.join(_user_data_dir(), "safety_data")
TRASH_DIR = os.path.join(SAFETY_DIR, "trash")
BACKUP_DIR = os.path.join(SAFETY_DIR, "backups")
SETTINGS_PATH = os.path.join(SAFETY_DIR, "settings.json")
LOG_PATH = os.path.join(SAFETY_DIR, "studio_log.jsonl")

DEFAULT_PROJECT_ROOT = "D:/武侠游戏"
DEFAULT_PORT = 8765
DEFAULT_RETENTION_DAYS = 30
DEFAULT_SAFE_MODE = True

_lock = threading.RLock()


def _log_event(action, target, detail=""):
    # 延迟 import：audit_service 顶层依赖 _common，直接顶层导入会成环。
    # 仅在运行期错误/降级路径调用，此时全部模块已加载完毕。
    from services.audit_service import log_event
    log_event(action, target, detail)


# ============================ 目录 / 设置 ============================
def _ensure_dirs():
    for d in (SAFETY_DIR, TRASH_DIR, BACKUP_DIR):
        os.makedirs(d, exist_ok=True)


def load_settings():
    _ensure_dirs()
    s = {}
    if os.path.exists(SETTINGS_PATH):
        try:
            with open(SETTINGS_PATH, "r", encoding="utf-8") as f:
                s = json.load(f)
        except Exception:
            s = {}
    s.setdefault("project_root", DEFAULT_PROJECT_ROOT)
    s.setdefault("port", DEFAULT_PORT)
    s.setdefault("retention_days", DEFAULT_RETENTION_DAYS)
    s.setdefault("safe_mode", DEFAULT_SAFE_MODE)
    return s


def save_settings(s):
    # ST-2 边界：设置是 Studio 自身设施（safety_data），不经 DataSink；
    # 且 discover_project_root ↔ save_settings 互调，走 save_json 会死递归。
    _ensure_dirs()
    with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(s, f, ensure_ascii=False, indent=2)


# ============================ ID 安全 ============================
def _safe_id(nid):
    # 仅保留安全字符，避免路径穿越
    return "".join(ch for ch in str(nid) if ch.isalnum() or ch in ("_", "-"))


def _is_valid_id(nid):
    # 白名单校验（比 _safe_id 严格：含非法字符直接拒绝，不做静默改名）。
    # 凡是会把 id 拼进文件路径的入口（对话 id / 按钮 id / 回收站文件名）必须过这道闸，防路径穿越。
    s = str(nid or "")
    if not s:
        return False
    for ch in s:
        if not (ch.isalnum() or ch in ("_", "-")):
            return False
    return True


# ============================ JSON 读写 / 备份 ============================
def load_json(path, default=None):
    if default is None:
        default = {}
    if not os.path.exists(path):
        return copy.deepcopy(default)
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        _log_event("load_error", path, str(e))
        return copy.deepcopy(default)


def _backup(path):
    if not os.path.exists(path):
        return
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    base = os.path.basename(path)
    dest = os.path.join(BACKUP_DIR, "%s_%s" % (ts, base))
    try:
        shutil.copy2(path, dest)
    except Exception as e:
        _log_event("backup_error", path, str(e))


def _backup_dir(src):
    try:
        ts = int(datetime.datetime.now().timestamp() * 1000)
        dst = os.path.join(BACKUP_DIR, "hb_%s_%d" % (_safe_id(os.path.basename(src)), ts))
        shutil.copytree(src, dst)
    except Exception:
        pass
