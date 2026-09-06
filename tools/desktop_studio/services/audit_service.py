# -*- coding: utf-8 -*-
"""审计与运维域服务：操作日志 / 回收站 / 过期清理 / 自检（self_test）。

职责边界：Studio 自身设施（safety_data 目录）的读写与核验；
不直接写工程数据（恢复/清理走 _common.save_json 收口）。
"""

import os
import json
import datetime

from services import _common
from services._common import (  # noqa: F401  门面透传用
    _safe_id, _is_valid_id, _ensure_dirs, load_settings, save_settings,
    load_json, save_json, save_text, _backup, _backup_dir,
    SAFETY_DIR, TRASH_DIR, BACKUP_DIR, SETTINGS_PATH, LOG_PATH,
    DEFAULT_PROJECT_ROOT, DEFAULT_PORT, DEFAULT_RETENTION_DAYS, DEFAULT_SAFE_MODE,
    SinkRejected, _SINK_OK,
)
from services.project_service import _paths, _shard_path, discover_project_root


# ============================ 日志 ============================
def log_event(action, target, detail=""):
    _ensure_dirs()
    ts = datetime.datetime.now().isoformat(timespec="seconds")
    line = json.dumps({"ts": ts, "action": action, "target": target, "detail": detail}, ensure_ascii=False)
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


def read_log(limit=300):
    if not os.path.exists(LOG_PATH):
        return []
    out = []
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except Exception:
                    pass
    return out[-limit:]


# ============================ 回收站 ============================
def _now():
    return datetime.datetime.now()


def trash_put(kind, item_id, payload, restore):
    _ensure_dirs()
    ts = _now().strftime("%Y%m%d_%H%M%S")
    rec = {
        "ts": _now().isoformat(timespec="seconds"),
        "kind": kind,
        "id": item_id,
        "payload": payload,
        "restore": restore,
    }
    fname = "%s_%s_%s.json" % (ts, kind, str(item_id).replace("/", "_"))
    with open(os.path.join(TRASH_DIR, fname), "w", encoding="utf-8") as f:
        json.dump(rec, f, ensure_ascii=False, indent=2)
    log_event("trash", "%s:%s" % (kind, item_id), "放入回收站 %s" % fname)
    return fname


def trash_list():
    if not os.path.isdir(TRASH_DIR):
        return []
    out = []
    for fn in sorted(os.listdir(TRASH_DIR)):
        if not fn.endswith(".json"):
            continue
        try:
            with open(os.path.join(TRASH_DIR, fn), "r", encoding="utf-8") as f:
                rec = json.load(f)
            rec["_file"] = fn
            out.append(rec)
        except Exception:
            pass
    return out


def _trash_path(fn):
    # 防路径穿越：只允许文件名本身（丢弃任何目录成分），杜绝 fn=../../任意文件 的删除/读取
    return os.path.join(TRASH_DIR, os.path.basename(str(fn or "")))


def trash_restore(fn):
    p = _trash_path(fn)
    if not os.path.exists(p):
        return False, "回收站文件不存在"
    with open(p, "r", encoding="utf-8") as f:
        rec = json.load(f)
    r = rec.get("restore", {})
    kind = r.get("type")
    try:
        if kind == "npc":
            data = load_json(r["file"], {"npcs": []})
            if "npcs" not in data:
                data["npcs"] = []
            data["npcs"].append(rec["payload"])
            save_json(r["file"], data)
        elif kind == "dlg_line":
            shard_path = _shard_path(r["dlg_id"])
            data = load_json(shard_path, {"id": r["dlg_id"], "lines": []})
            if "lines" not in data:
                data["lines"] = []
            data["lines"].append(rec["payload"])
            save_json(shard_path, data)
        elif kind == "celebration":
            data = load_json(r["file"], {})
            data[r["npc_id"]] = rec["payload"]
            save_json(r["file"], data)
        elif kind == "dlg":
            shard = rec["payload"].get("shard", {})
            idx_entry = rec["payload"].get("index_entry", {})
            save_json(_shard_path(r["dlg_id"]), shard)
            idx = load_json(r["file"], {"shards": {}})
            if "shards" not in idx:
                idx["shards"] = {}
            idx["shards"][r["dlg_id"]] = idx_entry
            save_json(r["file"], idx)
        else:
            return False, "未知的回收站类型"
        os.remove(p)
        log_event("restore", "%s:%s" % (kind, rec.get("id")), "已从回收站恢复 %s" % fn)
        return True, "已恢复"
    except Exception as e:
        return False, str(e)


def trash_purge(fn):
    p = _trash_path(fn)
    if os.path.exists(p):
        os.remove(p)
        log_event("purge", fn, "已彻底删除")
        return True
    return False


def auto_cleanup():
    s = load_settings()
    days = s.get("retention_days", DEFAULT_RETENTION_DAYS)
    cutoff = _now() - datetime.timedelta(days=days)
    cnt = 0
    for rec in trash_list():
        try:
            ts = datetime.datetime.fromisoformat(rec["ts"])
            if ts < cutoff:
                os.remove(_trash_path(rec["_file"]))
                cnt += 1
        except Exception:
            pass
    # 备份按保留期 *2 清理，避免无限增长
    bcut = _now() - datetime.timedelta(days=days * 2)
    if os.path.isdir(BACKUP_DIR):
        for fn in os.listdir(BACKUP_DIR):
            try:
                fp = os.path.join(BACKUP_DIR, fn)
                if datetime.datetime.fromtimestamp(os.path.getmtime(fp)) < bcut:
                    os.remove(fp)
            except Exception:
                pass
    if cnt:
        log_event("auto_cleanup", "trash", "清理了 %d 个过期回收项" % cnt)
    return cnt


# ============================ 自检（供无头测试） ============================
def self_test(tmp_root):
    """在临时工程根目录上跑一遍增/删/改/回收站/恢复/日志，验证核心逻辑。"""
    from services.npc_service import npc_upsert, npc_get, npc_delete
    from services.dialogue_service import dlg_new, dlg_line_upsert, dlg_line_delete, dlg_get
    from services.npc_service import cel_upsert, cel_delete
    save_settings({"project_root": tmp_root, "port": 8799, "retention_days": 30, "safe_mode": True})
    msgs = []
    # NPC
    ok, m = npc_upsert({"id": "npc_smoke_test", "name": "测试", "pos_x": 100, "pos_y": 200})
    msgs.append(("npc_new", ok, m))
    ok, m = npc_upsert({"id": "npc_smoke_test", "name": "测试2", "pos_x": 10, "pos_y": 20})
    msgs.append(("npc_update", ok, m))
    assert npc_get("npc_smoke_test")["name"] == "测试2"
    ok, m = npc_delete("npc_smoke_test")
    msgs.append(("npc_delete", ok, m))
    assert npc_get("npc_smoke_test") is None
    assert len(trash_list()) >= 1
    # dialog
    ok, m = dlg_new("dlg_test", npc_id="npc_smoke_test")
    msgs.append(("dlg_new", ok, m))
    ok, m = dlg_line_upsert("dlg_test", {"id": "l1", "text": "你好", "speaker_id": "npc", "npc_id": "npc_smoke_test"})
    msgs.append(("dlg_line_new", ok, m))
    ok, m = dlg_line_delete("dlg_test", "l1")
    msgs.append(("dlg_line_del", ok, m))
    assert len(dlg_get("dlg_test").get("lines", [])) == 0
    # celebration
    ok, m = cel_upsert("npc_test", {"cg": {"media_type": "none", "lines": ["x"]}, "end": {"lines": []}})
    msgs.append(("cel_new", ok, m))
    ok, m = cel_delete("npc_test")
    msgs.append(("cel_del", ok, m))
    # restore from trash
    tl = trash_list()
    restored = 0
    for rec in tl:
        if rec["kind"] == "npc" and rec["id"] == "npc_smoke_test":
            ok, m = trash_restore(rec["_file"])
            msgs.append(("trash_restore_npc", ok, m))
            restored += 1
    assert restored == 1 and npc_get("npc_smoke_test") is not None
    msgs.append(("log_lines", len(read_log()), "条日志"))
    return msgs
