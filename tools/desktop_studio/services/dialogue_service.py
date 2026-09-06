# -*- coding: utf-8 -*-
"""对话/剧情内容域服务：对话分片（shard）与台词行的增删改查。

写操作一律经 _common.save_json（DataSink 六步收口）；删除走回收站（审计域）。
"""

import os

from services import _common
from services._common import (  # noqa: F401  门面透传用
    _safe_id, _is_valid_id, _ensure_dirs, load_settings, save_settings,
    load_json, save_json, save_text, _backup, _backup_dir,
    SAFETY_DIR, TRASH_DIR, BACKUP_DIR, SETTINGS_PATH, LOG_PATH,
    DEFAULT_PROJECT_ROOT, DEFAULT_PORT, DEFAULT_RETENTION_DAYS, DEFAULT_SAFE_MODE,
    SinkRejected, _SINK_OK,
)
from services.project_service import _paths, _shard_path
from services.audit_service import log_event, trash_put


def dlg_list():
    idx = load_json(_paths()["dlg_index"], {"shards": {}})
    return list(idx.get("shards", {}).keys())


def dlg_get(dlg_id):
    if not _is_valid_id(dlg_id):
        return {}
    return load_json(_shard_path(dlg_id), {"id": dlg_id, "lines": []})


def dlg_new(dlg_id, npc_id=""):
    dlg_id = str(dlg_id).strip()
    if not _is_valid_id(dlg_id):
        return False, "对话 id 非法（仅允许字母/数字/下划线/短横线）"
    idx = load_json(_paths()["dlg_index"], {"shards": {}})
    if "shards" not in idx:
        idx["shards"] = {}
    if dlg_id in idx["shards"]:
        return False, "该对话 id 已存在"
    file = "res://data/configs/npcs/dialogs/shards/%s.json" % dlg_id
    shard = {"id": dlg_id, "lines": []}
    # npc_id 透传（C-3 主权：调用方提供才写入，工具不代填）；空置仍走 VA4-BINDING 登记放行
    if npc_id:
        shard["npc_id"] = str(npc_id)
    save_json(_shard_path(dlg_id), shard)
    idx["shards"][dlg_id] = {"file": file, "npc_id": str(npc_id or ""), "chapter": "custom"}
    save_json(_paths()["dlg_index"], idx)
    log_event("dlg_new", dlg_id, "新建对话")
    return True, "已新建对话 %s" % dlg_id


def dlg_line_upsert(dlg_id, line):
    if not _is_valid_id(dlg_id):
        return False, "对话 id 非法（仅允许字母/数字/下划线/短横线）"
    lid = str(line.get("id", "")).strip()
    if not lid:
        return False, "台词 id 不能为空"
    p = _shard_path(dlg_id)
    data = load_json(p, {"id": dlg_id, "lines": []})
    # npc_id 透传（C-3 主权：调用方提供才写入，工具不代填）
    if line.get("npc_id"):
        data["npc_id"] = str(line["npc_id"])
    if "lines" not in data:
        data["lines"] = []
    rec = {
        "id": lid,
        "speaker_id": str(line.get("speaker_id", "")),
        "speaker_name": str(line.get("speaker_name", "")),
        "text": str(line.get("text", "")),
        "next_id": str(line.get("next_id", "")),
        "trigger_events": [str(x).strip() for x in line.get("trigger_events", []) if str(x).strip()],
    }

    def _norm_options(opts):
        out = []
        if not isinstance(opts, list):
            return out
        for o in opts:
            if not isinstance(o, dict):
                continue
            opt = {k: o[k] for k in ("text", "text_key", "jump_id") if k in o}
            if "cond" in o and isinstance(o["cond"], dict):
                opt["cond"] = dict(o["cond"])
            out.append(opt)
        return out

    found = False
    for i, ln in enumerate(data["lines"]):
        if ln.get("id") == lid:
            # 分支保护：请求没带 options 时沿用该行已存分支（防止旧编辑器/旧代码清空分支）
            if "options" in line:
                rec["options"] = _norm_options(line["options"])
            elif isinstance(ln.get("options"), list) and ln["options"]:
                rec["options"] = ln["options"]
            data["lines"][i] = rec
            found = True
            break
    if not found:
        if "options" in line:
            rec["options"] = _norm_options(line["options"])
        data["lines"].append(rec)
    save_json(p, data)
    log_event("dlg_line_save", "%s/%s" % (dlg_id, lid), "保存台词")
    return True, ("更新" if found else "新建") + " 台词 %s" % lid


def dlg_line_delete(dlg_id, lid):
    if not _is_valid_id(dlg_id):
        return False, "对话 id 非法（仅允许字母/数字/下划线/短横线）"
    p = _shard_path(dlg_id)
    data = load_json(p, {"id": dlg_id, "lines": []})
    lines = data.get("lines", [])
    kept = [ln for ln in lines if ln.get("id") != lid]
    if len(kept) == len(lines):
        return False, "未找到该台词"
    removed = next(ln for ln in lines if ln.get("id") == lid)
    s = load_settings()
    data["lines"] = kept
    save_json(p, data)
    if s.get("safe_mode", True):
        trash_put("dlg_line", "%s/%s" % (dlg_id, lid), removed, {"type": "dlg_line", "dlg_id": dlg_id})
        return True, "已删除并放入回收站：%s" % lid
    return True, "已彻底删除：%s" % lid


def dlg_delete(dlg_id):
    idx = load_json(_paths()["dlg_index"], {"shards": {}})
    if dlg_id not in idx.get("shards", {}):
        return False, "未找到该对话"
    entry = idx["shards"][dlg_id]
    shard = load_json(_shard_path(dlg_id), {"id": dlg_id, "lines": []})
    s = load_settings()
    del idx["shards"][dlg_id]
    save_json(_paths()["dlg_index"], idx)
    if s.get("safe_mode", True):
        trash_put("dlg", dlg_id, {"shard": shard, "index_entry": entry},
                  {"type": "dlg", "dlg_id": dlg_id, "file": _paths()["dlg_index"]})
        return True, "已从索引删除并放入回收站：%s" % dlg_id
    try:
        os.remove(_shard_path(dlg_id))
    except Exception:
        pass
    return True, "已彻底删除对话：%s" % dlg_id
