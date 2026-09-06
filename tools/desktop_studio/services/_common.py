# -*- coding: utf-8 -*-
"""共享基础设施层：路径常量 / 设置 / ID 校验 / JSON·文本读写收口 / 备份。

仅依赖标准库与 tools/data_sink，不 import 任何 service，保证无循环依赖。
服务层统一从此处取基础设施，不直接碰 DataSink 细节。
"""

import os
import sys
import json
import copy
import shutil
import threading
import datetime

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS_DIR = os.path.dirname(MODULE_DIR)          # tools/（data_sink 所在层）
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

# 15 图 ST-2 批2：Studio 生产写唯一 DataSink 六步收口。
# frozen exe（旧打包）缺 data_sink 时降级直写并记日志，源码模式/重打包后全量生效。
try:
    import data_sink as _sink
    from data_sink import SinkRejected  # noqa: F401  （studio_server 可经此捕获提示用户）
    _SINK_OK = True
except Exception:  # pragma: no cover
    _SINK_OK = False


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


def save_text(path, text, note="", encoding="utf-8"):
    """ST-2 唯一写口（文本/CSV 版）：降级策略同 save_json。"""
    from services.project_service import discover_project_root
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if _SINK_OK:
        try:
            _sink.write_text(discover_project_root(), path, text,
                             note=note or "Studio save_text", encoding=encoding)
            return
        except _sink.SinkRejected as e:
            _log_event("sink_rejected", path, "%s | %s" % (e.step, "；".join(e.problems[:5])))
            raise
        except Exception as e:
            _log_event("sink_error", path, str(e))
    _backup(path)
    with open(path, "w", encoding=encoding, newline="") as f:
        f.write(text)
    if not _SINK_OK:
        _log_event("sink_degraded", path, "data_sink 不可用，直写降级（请重打包或用源码模式）")


def save_json(path, data, note=""):
    """ST-2 唯一写口：Studio 生产 JSON 写统一经 DataSink 六步收口（15图批2）。

    降级路径：frozen 旧包缺 data_sink 时按旧逻辑直写（③备份+④落盘仍在），
    并写 studio 日志提示重打包。"""
    from services.project_service import discover_project_root
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if _SINK_OK:
        try:
            _sink.write_json(discover_project_root(), path, data, note=note or "Studio save_json")
            return
        except _sink.SinkRejected as e:
            _log_event("sink_rejected", path, "%s | %s" % (e.step, "；".join(e.problems[:5])))
            raise
        except Exception as e:
            _log_event("sink_error", path, str(e))
            # 六步设施异常不阻断编辑器主流程：退回直写并留痕
    _backup(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    if not _SINK_OK:
        _log_event("sink_degraded", path, "data_sink 不可用，直写降级（请重打包或用源码模式）")
