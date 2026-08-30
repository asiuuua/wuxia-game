#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
武侠游戏「内容工作室」桌面版 —— 核心逻辑（剧情 / 文本 / NPC / 欢庆 + 保险 / 日志 / 回收站）
仅依赖 Python 标准库，可独立运行，也可被 studio_server.py 调用。

保险机制（用户要求的“误删先提前保存，过一段时间再清空”）：
  - 保险模式（默认开）：任何“删除”操作不直接销毁数据，而是把被删内容连同
    还原信息写进 回收站(safety_data/trash/)，并写操作日志。
  - 每次“保存/覆盖”写文件前，先自动备份一份到 safety_data/backups/（带时间戳），
    即使误改也能回退。
  - 回收站里的项目保留 retention_days 天（默认 30），过期由 auto_cleanup() 自动清空；
    也可在界面里手动“恢复”或“彻底删除”。
"""

import os
import json
import copy
import shutil
import datetime
import threading
import sys
import io
import base64

MODULE_DIR = os.path.dirname(os.path.abspath(__file__))


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
    _ensure_dirs()
    with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
        json.dump(s, f, ensure_ascii=False, indent=2)


def _exe_dir():
    # PyInstaller 打包后是 exe 真实所在目录；脚本模式是 .py 所在目录
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.executable))
    return os.path.dirname(os.path.abspath(sys.argv[0]))


def _has_project_marker(root):
    if not root or not os.path.isdir(root):
        return False
    if os.path.exists(os.path.join(root, "project.godot")):
        return True
    if os.path.exists(os.path.join(root, "data", "configs", "npcs", "town_npcs.json")):
        return True
    return False


def discover_project_root():
    """解析工程根目录：优先用设置里的值；否则从 exe 所在目录向上查找带工程标记( project.godot / town_npcs.json )的文件夹；
    找不到才回退默认路径。这样把 exe 连同 data 一起发给别人时，无需改设置即可定位。"""
    s = load_settings()
    stored = s.get("project_root", "")
    if _has_project_marker(stored):
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
        "dlg_index": os.path.join(root, "data", "configs", "npcs", "dialogs", "_index.json"),
        "dlg_dir": os.path.join(root, "data", "configs", "npcs", "dialogs", "shards"),
        "cel": os.path.join(root, "data", "configs", "bond", "celebrations.json"),
        "assets": os.path.join(root, "assets"),
    }


# 半身立绘（动态可导入）资源根目录：assets/characters/half_body/
def _half_body_dir():
    return os.path.join(_paths()["assets"], "characters", "half_body")


# ============================ NPC 动态立绘一键导入 ============================
# 合并进 NPC 编辑列：支持「静态图片 / 帧动画(ZIP) / Spine骨骼(ZIP)」三种类型一键导入。
# 导入后写入 NPC 的 half_body_portrait 字段（静态取该图路径；动态取目录），
# 并附带 portrait_type / portrait_frames(NPC 面板与对话框后续按此切换动态立绘)。
# ⚠️ 这些字段是「共享地基纯追加」——旧 NPC 无这些字段时游戏侧 resolve_half_body 会回退占位，零破坏。
import zipfile

def _safe_id(nid):
    # 仅保留安全字符，避免路径穿越
    return "".join(ch for ch in str(nid) if ch.isalnum() or ch in ("_", "-"))


def npc_portrait_import(npc_id, payload):
    """payload: {"ptype": "static"|"frame"|"spine",
                 "filename": "xxx.png",
                 "data": "<base64 单图>" 或 "zip": "<base64 zip>"}
    返回 (ok, msg, meta) ；meta 含写入 NPC 的字段。"""
    nid = _safe_id(npc_id)
    if not nid:
        return False, "NPC id 非法", {}
    ptype = str(payload.get("ptype", "static"))
    hb = _half_body_dir()
    os.makedirs(hb, exist_ok=True)
    import base64
    if ptype == "static":
        raw = base64.b64decode(payload.get("data", b"") or b"")
        if not raw:
            return False, "空数据", {}
        # 推断扩展名
        ext = ".png"
        fn = str(payload.get("filename", "")).lower()
        if fn.endswith(".webp"):
            ext = ".webp"
        elif fn.endswith((".jpg", ".jpeg")):
            ext = ".jpg"
        dst = os.path.join(hb, "%s%s" % (nid, ext))
        with open(dst, "wb") as f:
            f.write(raw)
        res = "res://assets/characters/half_body/%s%s" % (nid, ext)
        meta = {"half_body_portrait": res, "portrait_type": "static", "portrait_frames": [], "portrait_skeleton": ""}
        # 同步覆盖占位（保证上帝视角下立即可见）
        log_event("npc_portrait", nid, "导入静态半身立绘 %s" % res)
        return True, "已导入静态半身立绘", meta
    elif ptype in ("frame", "spine"):
        raw = base64.b64decode(payload.get("zip", b"") or b"")
        if not raw:
            return False, "空 ZIP 数据", {}
        sub = "frames" if ptype == "frame" else "spine"
        out_dir = os.path.join(hb, "%s_%s" % (nid, sub))
        # 清空旧目录（保险：先备份再覆盖）
        if os.path.isdir(out_dir):
            _backup_dir(out_dir)
            shutil.rmtree(out_dir)
        os.makedirs(out_dir, exist_ok=True)
        try:
            zf = zipfile.ZipFile(io.BytesIO(raw))
            zf.extractall(out_dir)
        except Exception as e:
            return False, "ZIP 解压失败：%s" % e, {}
        # 列出帧（帧动画按文件名排序；spine 找 .skel/.json + .atlas）
        frames = []
        if ptype == "frame":
            for name in sorted(os.listdir(out_dir)):
                if name.lower().endswith((".png", ".webp", ".jpg", ".jpeg")):
                    frames.append("res://assets/characters/half_body/%s_%s/%s" % (nid, sub, name))
        if ptype == "spine":
            # 记录关键文件，供后续骨骼加载器使用（当前游戏侧占位静态图）
            skel = ""
            atlas = ""
            for name in os.listdir(out_dir):
                low = name.lower()
                if low.endswith((".skel", ".json")) and "skeleton" not in low and skel == "":
                    skel = "res://assets/characters/half_body/%s_%s/%s" % (nid, sub, name)
                if low.endswith(".atlas"):
                    atlas = "res://assets/characters/half_body/%s_%s/%s" % (nid, sub, name)
            meta = {"half_body_portrait": "res://assets/characters/half_body/%s_%s" % (nid, sub),
                    "portrait_type": "spine", "portrait_frames": [],
                    "portrait_skeleton": skel, "portrait_atlas": atlas}
            log_event("npc_portrait", nid, "导入 Spine 骨骼立绘 %s" % sub)
            return True, "已导入 Spine 骨骼立绘（动态播放接口预留）", meta
        meta = {"half_body_portrait": "res://assets/characters/half_body/%s_%s" % (nid, sub),
                "portrait_type": "frame", "portrait_frames": frames, "portrait_skeleton": ""}
        log_event("npc_portrait", nid, "导入帧动画立绘 %s 帧" % len(frames))
        return True, "已导入帧动画立绘（%d 帧，动态播放接口预留）" % len(frames), meta
    return False, "未知立绘类型：%s" % ptype, {}


def npc_portrait_clear(npc_id):
    """清除立绘字段，回退到游戏侧按 id 的占位图（不删文件，仅清字段）。"""
    nid = _safe_id(npc_id)
    if not nid:
        return False, "NPC id 非法"
    meta = {"half_body_portrait": "", "portrait_type": "static", "portrait_frames": [], "portrait_skeleton": ""}
    return True, "已清除立绘字段（游戏将回退占位图）", meta


def _backup_dir(src):
    try:
        ts = int(datetime.datetime.now().timestamp() * 1000)
        dst = os.path.join(BACKUP_DIR, "hb_%s_%d" % (_safe_id(os.path.basename(src)), ts))
        shutil.copytree(src, dst)
    except Exception:
        pass


# ============================ JSON 读写 ============================
def load_json(path, default=None):
    if default is None:
        default = {}
    if not os.path.exists(path):
        return copy.deepcopy(default)
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        log_event("load_error", path, str(e))
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
        log_event("backup_error", path, str(e))


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _backup(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


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
    return os.path.join(TRASH_DIR, fn)


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


# ============================ NPC ============================
def _shard_path(dlg_id):
    return os.path.join(_paths()["dlg_dir"], "%s.json" % dlg_id)


def npc_list():
    data = load_json(_paths()["npc"], {"npcs": []})
    return data.get("npcs", [])


def npc_get(nid):
    for n in npc_list():
        if n.get("id") == nid:
            return n
    return None


def npc_upsert(fields):
    data = load_json(_paths()["npc"], {"npcs": []})
    if "npcs" not in data:
        data["npcs"] = []
    nid = str(fields.get("id", "")).strip()
    if not nid:
        return False, "id 不能为空"
    # 原有基础字段
    entry = {}
    for k in ("id", "name", "sprite", "portrait", "dialog_id", "quest_id", "battle_id"):
        entry[k] = str(fields.get(k, ""))
    try:
        entry["pos_x"] = int(fields.get("pos_x", 0) or 0)
        entry["pos_y"] = int(fields.get("pos_y", 0) or 0)
    except Exception:
        entry["pos_x"] = 0
        entry["pos_y"] = 0
    # 半身立绘（动态可导入）字段：合并进 NPC 列，旧 NPC 无这些字段时保留空值（游戏侧回退占位）
    for k in ("half_body_portrait", "portrait_type", "portrait_skeleton", "portrait_atlas"):
        if k in fields:
            entry[k] = str(fields.get(k, ""))
    if "portrait_frames" in fields and isinstance(fields["portrait_frames"], list):
        entry["portrait_frames"] = list(fields["portrait_frames"])
    found = False
    for i, n in enumerate(data["npcs"]):
        if n.get("id") == nid:
            # 仅当本次请求显式带立绘字段时才覆盖；否则保留旧值（避免保存时清空已导入立绘）
            if "half_body_portrait" not in fields:
                for k in ("half_body_portrait", "portrait_type", "portrait_frames", "portrait_skeleton", "portrait_atlas"):
                    if k in n:
                        entry[k] = n[k]
            data["npcs"][i] = entry
            found = True
            break
    if not found:
        data["npcs"].append(entry)
    save_json(_paths()["npc"], data)
    log_event("npc_save", nid, "保存 NPC")
    return True, ("更新" if found else "新建") + " NPC %s" % nid


def npc_delete(nid):
    data = load_json(_paths()["npc"], {"npcs": []})
    npcs = data.get("npcs", [])
    kept = [n for n in npcs if n.get("id") != nid]
    if len(kept) == len(npcs):
        return False, "未找到该 NPC"
    removed = next(n for n in npcs if n.get("id") == nid)
    s = load_settings()
    data["npcs"] = kept
    save_json(_paths()["npc"], data)
    if s.get("safe_mode", True):
        trash_put("npc", nid, removed, {"type": "npc", "file": _paths()["npc"]})
        return True, "已删除并放入回收站：%s" % nid
    return True, "已彻底删除：%s" % nid


def npc_rename(old_id, new_id, fields):
    """重命名 NPC 的唯一 ID：删除旧记录（进回收站）、以新 ID 插入，避免产生重复记录。"""
    data = load_json(_paths()["npc"], {"npcs": []})
    if "npcs" not in data:
        data["npcs"] = []
    old_id = str(old_id).strip()
    new_id = str(new_id).strip()
    if not old_id or not new_id:
        return False, "新旧 id 都不能为空"
    if old_id == new_id:
        return npc_upsert(fields)
    old_entry = None
    kept = []
    for n in data["npcs"]:
        if n.get("id") == old_id:
            old_entry = n
        else:
            kept.append(n)
    if old_entry is None:
        return False, "未找到原 id：%s" % old_id
    s = load_settings()
    if s.get("safe_mode", True):
        trash_put("npc", old_id, old_entry, {"type": "npc", "file": _paths()["npc"]})
    entry = {}
    for k in ("name", "sprite", "portrait", "dialog_id", "quest_id", "battle_id"):
        entry[k] = str(fields.get(k, ""))
    try:
        entry["pos_x"] = int(fields.get("pos_x", 0) or 0)
        entry["pos_y"] = int(fields.get("pos_y", 0) or 0)
    except Exception:
        entry["pos_x"] = 0
        entry["pos_y"] = 0
    entry["id"] = new_id
    kept.append(entry)
    data["npcs"] = kept
    save_json(_paths()["npc"], data)
    log_event("npc_rename", "%s->%s" % (old_id, new_id), "重命名 NPC（旧记录进回收站）")
    return True, "已将 %s 重命名为 %s（旧记录已进回收站，可恢复）" % (old_id, new_id)


# ============================ 对话 / 剧情 ============================
def dlg_list():
    idx = load_json(_paths()["dlg_index"], {"shards": {}})
    return list(idx.get("shards", {}).keys())


def dlg_get(dlg_id):
    return load_json(_shard_path(dlg_id), {"id": dlg_id, "lines": []})


def dlg_new(dlg_id):
    dlg_id = str(dlg_id).strip()
    if not dlg_id:
        return False, "对话 id 不能为空"
    idx = load_json(_paths()["dlg_index"], {"shards": {}})
    if "shards" not in idx:
        idx["shards"] = {}
    if dlg_id in idx["shards"]:
        return False, "该对话 id 已存在"
    file = "res://data/configs/npcs/dialogs/shards/%s.json" % dlg_id
    shard = {"id": dlg_id, "lines": []}
    save_json(_shard_path(dlg_id), shard)
    idx["shards"][dlg_id] = {"file": file, "npc_id": "", "chapter": "custom"}
    save_json(_paths()["dlg_index"], idx)
    log_event("dlg_new", dlg_id, "新建对话")
    return True, "已新建对话 %s" % dlg_id


def dlg_line_upsert(dlg_id, line):
    lid = str(line.get("id", "")).strip()
    if not lid:
        return False, "台词 id 不能为空"
    p = _shard_path(dlg_id)
    data = load_json(p, {"id": dlg_id, "lines": []})
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
    found = False
    for i, ln in enumerate(data["lines"]):
        if ln.get("id") == lid:
            data["lines"][i] = rec
            found = True
            break
    if not found:
        data["lines"].append(rec)
    save_json(p, data)
    log_event("dlg_line_save", "%s/%s" % (dlg_id, lid), "保存台词")
    return True, ("更新" if found else "新建") + " 台词 %s" % lid


def dlg_line_delete(dlg_id, lid):
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


# ============================ 欢庆模块 ============================
def cel_list():
    data = load_json(_paths()["cel"], {})
    out = []
    for k in data.keys():
        if k.startswith("_") or k in ("default", "over_limit"):
            continue
        out.append(k)
    return out


def cel_get(npc_id):
    data = load_json(_paths()["cel"], {})
    return data.get(npc_id, {
        "cg": {"media_type": "none", "media_path": "", "bgm": "", "lines": []},
        "end": {"media_type": "none", "media_path": "", "lines": []},
    })


def cel_upsert(npc_id, entry):
    npc_id = str(npc_id).strip()
    if not npc_id:
        return False, "NPC id 不能为空"
    data = load_json(_paths()["cel"], {})
    data[npc_id] = entry
    save_json(_paths()["cel"], data)
    log_event("cel_save", npc_id, "保存欢庆内容")
    return True, "已保存 %s 的欢庆内容" % npc_id


def cel_delete(npc_id):
    data = load_json(_paths()["cel"], {})
    if npc_id not in data:
        return False, "未找到该 NPC"
    removed = data[npc_id]
    s = load_settings()
    del data[npc_id]
    save_json(_paths()["cel"], data)
    if s.get("safe_mode", True):
        trash_put("celebration", npc_id, removed,
                  {"type": "celebration", "npc_id": npc_id, "file": _paths()["cel"]})
        return True, "已删除并放入回收站：%s" % npc_id
    return True, "已彻底删除：%s" % npc_id


# ============================ 登录界面（UI 登录界面修改插件） ============================
import re


def _login_bg_base():
    return os.path.join(discover_project_root(), "assets", "ui", "main_menu_bg")


def _detect_image_ext(src_path):
    # 读文件头判定真实图片格式（Godot 按扩展名选解码器，扩展名错配会导入出坏图）
    try:
        with open(src_path, "rb") as f:
            head = f.read(8)
    except Exception:
        return "jpg"
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if head[:3] == b"\xff\xd8\xff":
        return "jpg"
    return "jpg"  # 兜底：按 jpg 处理


# 大背景图写死的资源路径所在文件，换扩展名时需同步更新
_LOGIN_BG_REF_FILES = [
    os.path.join(discover_project_root(), "scenes", "ui", "screens", "main_menu", "MainMenu.gd"),
    os.path.join(discover_project_root(), "scenes", "ui", "screens", "save_load", "SaveLoadScreen.gd"),
    os.path.join(discover_project_root(), "scenes", "ui", "screens", "loading", "LoadingScreen.gd"),
    os.path.join(discover_project_root(), "scenes", "ui", "components", "ui_background", "UIBackground.gd"),
]


def _patch_login_bg_refs(ext):
    # 把游戏里写死的 main_menu_bg.<old> 资源路径同步成新扩展名，避免指向不存在的文件
    new = "res://assets/ui/main_menu_bg.%s" % ext
    for fp in _LOGIN_BG_REF_FILES:
        if not os.path.exists(fp):
            continue
        txt = open(fp, "r", encoding="utf-8").read()
        if "main_menu_bg." not in txt:
            continue
        txt2 = re.sub(r"res://assets/ui/main_menu_bg\.(jpg|png)", new, txt)
        txt2 = re.sub(r"main_menu_bg\.(jpg|png)（或改", "main_menu_bg.%s（或改" % ext, txt2)
        txt2 = re.sub(r"把图命名为 main_menu_bg\.(jpg|png)", "把图命名为 main_menu_bg.%s" % ext, txt2)
        if txt2 != txt:
            _backup(fp)
            open(fp, "w", encoding="utf-8").write(txt2)


def _login_bg_path():
    # 返回当前实际存在的大背景图路径（优先 png，其次 jpg），供信息展示/校验使用
    base = _login_bg_base()
    for ext in ("png", "jpg"):
        p = "%s.%s" % (base, ext)
        if os.path.exists(p):
            return p
    return "%s.png" % base


def _login_strings_path():
    return os.path.join(discover_project_root(), "data", "configs", "localization", "strings.csv")


def _login_btn_bg_dir():
    return os.path.join(discover_project_root(), "assets", "ui", "main_menu_btn")


def _login_btn_bg_cfg():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "login_button_bg.json")


# 登录界面所有可改文案（tr 键 -> 说明 / 点击后打开的窗口）
LOGIN_TEXT_KEYS = [
    ("menu_new_game", "开始新的旅程（主菜单第1项）", "难度选择 DifficultySelect"),
    ("menu_continue", "继续江湖路（主菜单第2项·需有存档）", "读取最新存档"),
    ("menu_load", "读取旧梦（主菜单第3项）", "读档界面 SaveLoadScreen"),
    ("menu_settings", "游戏设置（主菜单第4项）", "设置界面 SettingsScreen"),
    ("menu_archive", "江湖图鉴（主菜单第5项）", "（未实装 TODO）"),
    ("menu_quit", "退出江湖（主菜单第6项）", "（退出游戏）"),
    ("btn_settings", "设置（底部栏按钮）", "设置界面 SettingsScreen"),
    ("btn_language", "语言（底部栏按钮）", "（占位未实装）"),
    ("studio_name", "制作组名（版本行右侧）", "—"),
]


def login_bg_info():
    p = _login_bg_path()
    if not os.path.exists(p):
        return {"exists": False, "size": 0, "mtime": 0, "ext": ""}
    st = os.stat(p)
    return {"exists": True, "size": st.st_size, "mtime": st.st_mtime,
            "ext": os.path.splitext(p)[1].lstrip(".")}


def login_bg_replace(src_path):
    ext = _detect_image_ext(src_path)
    base = _login_bg_base()
    dst = "%s.%s" % (base, ext)
    other = "%s.%s" % (base, "jpg" if ext == "png" else "png")
    # 先备份当前已有的旧背景（任一扩展名），避免覆盖/换扩展名时丢图
    for old in (dst, other):
        if os.path.exists(old):
            _backup(old)
    # 删掉另一种扩展名的残留文件，否则 Godot 可能误导入旧格式
    if os.path.exists(other):
        try:
            os.remove(other)
        except OSError:
            pass
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src_path, dst)
    _patch_login_bg_refs(ext)
    log_event("login_bg", dst, "替换登录界面大背景图（影响主菜单/加载/读档三处共用图），识别格式=%s" % ext)
    return True, "已替换登录界面大背景图（%s，主菜单/加载/读档界面共用，下次进游戏即生效）" % ext


def login_texts():
    path = _login_strings_path()
    data = {}
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8-sig") as f:
            for line in f:
                s = line.strip()
                if not s or s.startswith("#"):
                    continue
                parts = [x.strip() for x in s.split(",")]
                while len(parts) < 4:
                    parts.append("")
                data[parts[0]] = {"zh_CN": parts[1], "zh_TW": parts[2], "en": parts[3]}
    out = []
    for (k, desc, target) in LOGIN_TEXT_KEYS:
        r = data.get(k, {})
        out.append({"key": k, "desc": desc, "target": target,
                    "zh_CN": r.get("zh_CN", ""), "zh_TW": r.get("zh_TW", ""), "en": r.get("en", "")})
    return out


def login_texts_update(rows):
    path = _login_strings_path()
    if not os.path.exists(path):
        return False, "未找到 strings.csv"
    _backup(path)
    updates = {r.get("key"): r for r in rows if r.get("key")}
    with open(path, "r", encoding="utf-8-sig") as f:
        lines = f.readlines()
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            parts = [x.strip() for x in stripped.split(",")]
            key = parts[0]
            if key in updates and len(parts) >= 1:
                u = updates[key]
                zh = u.get("zh_CN", parts[1] if len(parts) > 1 else "")
                tw = u.get("zh_TW", parts[2] if len(parts) > 2 else "")
                en = u.get("en", parts[3] if len(parts) > 3 else "")
                line = "%s,%s,%s,%s\n" % (key, zh, tw, en)
        new_lines.append(line)
    with open(path, "w", encoding="utf-8-sig") as f:
        f.writelines(new_lines)
    log_event("login_texts", path, "更新 %d 条登录界面文案" % len(rows))
    return True, "已保存 %d 条文案" % len(rows)


def login_version():
    p = os.path.join(discover_project_root(), "scenes", "ui", "screens", "main_menu", "MainMenu.gd")
    ver = "(未找到)"
    if os.path.exists(p):
        txt = open(p, "r", encoding="utf-8").read()
        m = re.search(r'const\s+VERSION_TEXT\s*:?=\s*"([^"]*)"', txt)
        if m:
            ver = m.group(1)
    return {"version": ver, "editable": False,
            "note": "版本号写死在 MainMenu.gd:16（const VERSION_TEXT）。你已选择“不动游戏代码”，此值只读；如需改请告诉我（低风险，会跑双闸门保证不出错）。"}


def login_btn_bg_list():
    cfg = _login_btn_bg_cfg()
    data = {}
    if os.path.exists(cfg):
        try:
            data = json.load(open(cfg, "r", encoding="utf-8")).get("map", {})
        except Exception:
            data = {}
    out = []
    for (k, desc, target) in LOGIN_TEXT_KEYS:
        if k in ("btn_settings", "btn_language", "studio_name"):
            continue  # 底部栏/制作组不是主菜单项按钮
        out.append({"key": k, "desc": desc, "path": data.get(k, "")})
    return out


def login_btn_bg_set(btn_id, src_path):
    d = _login_btn_bg_dir()
    os.makedirs(d, exist_ok=True)
    os.makedirs(os.path.dirname(_login_btn_bg_cfg()), exist_ok=True)
    dst = os.path.join(d, "%s.png" % btn_id)
    _backup(dst)
    shutil.copy2(src_path, dst)
    cfg = _login_btn_bg_cfg()
    data = {}
    if os.path.exists(cfg):
        try:
            data = json.load(open(cfg, "r", encoding="utf-8"))
        except Exception:
            data = {}
    if "map" not in data:
        data["map"] = {}
    data["map"][btn_id] = "res://assets/ui/main_menu_btn/%s.png" % btn_id
    data["_doc"] = "登录主菜单各按钮背景图映射。游戏代码已读取此表（MainMenu._load_btn_bg_map → MenuItem.set_background），上传图片后下次进主菜单即生效。"
    with open(cfg, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("login_btn_bg", btn_id, "存储按钮背景图（待代码启用）")
    return True, "已存储 %s 的按钮背景图（游戏代码已读取，下次进主菜单即生效）" % btn_id


# === 登录背景布局（方案B：游戏 UIBackground 运行时读取此 JSON） ===
def _login_bg_layout_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "login_bg_layout.json")


# 默认值：铺满裁切(cover) + 自动取图边色填缝，保证任意窗口比例都无黑边/无绿缝
_LOGIN_BG_LAYOUT_DEFAULT = {
    "stretch_mode": "keep_aspect_covered",
    "scrim_alpha": 0.55,
    "edge_auto": True,
    "leaves_enabled": True,
    "edge_color": [194, 195, 181],
}


def login_bg_layout():
    """读取当前登录背景布局设置（与默认值合并，缺字段补默认）。"""
    p = _login_bg_layout_path()
    data = dict(_LOGIN_BG_LAYOUT_DEFAULT)
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                data.update(json.load(f))
        except Exception:
            pass
    return {
        "stretch_mode": data.get("stretch_mode", "keep_aspect_covered"),
        "scrim_alpha": float(data.get("scrim_alpha", 0.55)),
        "edge_auto": bool(data.get("edge_auto", True)),
        "leaves_enabled": bool(data.get("leaves_enabled", True)),
        "edge_color": data.get("edge_color", [194, 195, 181]),
    }


def login_bg_layout_update(d):
    """写入登录背景布局设置（自动备份旧文件）。"""
    p = _login_bg_layout_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    cur = login_bg_layout()
    for k in ("stretch_mode", "scrim_alpha", "edge_auto", "leaves_enabled", "edge_color"):
        if k in d:
            cur[k] = d[k]
    with open(p, "w", encoding="utf-8") as f:
        json.dump(cur, f, ensure_ascii=False, indent=2)
    log_event("login_bg_layout", p, "更新登录背景布局：%s" % cur.get("stretch_mode"))
    return True, "已保存登录背景布局（游戏内立即生效）"


# ============================ 预加载(加载)界面布局（自由拖拽可视化编辑） ============================
def _loading_layout_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "loading_layout.json")


# 四个可拖拽元素（与游戏 LoadingScreen._apply_layout 的 keys 对应）
LOADING_ELEMS = ["progress_bar", "progress_label", "tip_label", "version_label"]

_LOADING_LAYOUT_DEFAULT = {
    "elements": {
        "progress_bar":  {"x": 0.5,  "y": 0.86, "w": 0.5,  "h": 0.02},
        "progress_label":{"x": 0.5,  "y": 0.81, "align": "center"},
        "tip_label":     {"x": 0.5,  "y": 0.66, "align": "center"},
        "version_label": {"x": 0.97, "y": 0.97, "align": "right"},
    }
}


def loading_layout_get():
    """读取当前加载界面布局（与默认合并，缺字段补默认）。"""
    p = _loading_layout_path()
    data = {"elements": {k: dict(v) for k, v in _LOADING_LAYOUT_DEFAULT["elements"].items()}}
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                parsed = json.load(f)
            if isinstance(parsed, dict) and isinstance(parsed.get("elements"), dict):
                for k in LOADING_ELEMS:
                    if k in parsed["elements"]:
                        data["elements"][k].update(parsed["elements"][k])
        except Exception:
            pass
    return data


def loading_layout_update(d):
    """写入加载界面布局（自动备份旧文件）。d 形如 {"elements": {...}}。"""
    p = _loading_layout_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    data = {"elements": {}}
    for k in LOADING_ELEMS:
        spec = dict(_LOADING_LAYOUT_DEFAULT["elements"].get(k, {}))
        incoming = (d.get("elements", {}) or {}).get(k, {})
        if isinstance(incoming, dict):
            spec.update(incoming)
        # 归一化裁剪到 0~1
        for ck in ("x", "y", "w", "h"):
            if ck in spec:
                spec[ck] = max(0.0, min(1.0, float(spec[ck])))
        data["elements"][k] = spec
    data["_doc"] = "加载界面元素布局（工作室「预加载界面」自由拖拽编辑写入）。坐标为视口归一化 0~1；progress_bar 用 w/h 控制条宽高。"
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("loading_layout", p, "更新预加载界面布局")
    return True, "已保存预加载界面布局（游戏内下次启动生效）"


# === 各按钮背景图「存空/清除」（Task #42） ===
def login_btn_bg_clear(btn_id):
    """把某按钮背景图清空为 null：删映射表项 + 删图片文件，回退到游戏默认样式。"""
    cfg = _login_btn_bg_cfg()
    data = {}
    if os.path.exists(cfg):
        try:
            data = json.load(open(cfg, "r", encoding="utf-8"))
        except Exception:
            data = {}
    if "map" in data and btn_id in data["map"]:
        del data["map"][btn_id]
        with open(cfg, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    d = _login_btn_bg_dir()
    fp = os.path.join(d, "%s.png" % btn_id)
    if os.path.exists(fp):
        _backup(fp)
        try:
            os.remove(fp)
        except Exception:
            pass
    log_event("login_btn_bg_clear", btn_id, "清除按钮背景图（设为默认）")
    return True, "已清除 %s 的按钮背景图（回退默认）" % btn_id


# ============================ 自检（供无头测试） ============================
def self_test(tmp_root):
    """在临时工程根目录上跑一遍增/删/改/回收站/恢复/日志，验证核心逻辑。"""
    save_settings({"project_root": tmp_root, "port": 8799, "retention_days": 30, "safe_mode": True})
    msgs = []
    # NPC
    ok, m = npc_upsert({"id": "test_npc", "name": "测试", "pos_x": 100, "pos_y": 200})
    msgs.append(("npc_new", ok, m))
    ok, m = npc_upsert({"id": "test_npc", "name": "测试2", "pos_x": 10, "pos_y": 20})
    msgs.append(("npc_update", ok, m))
    assert npc_get("test_npc")["name"] == "测试2"
    ok, m = npc_delete("test_npc")
    msgs.append(("npc_delete", ok, m))
    assert npc_get("test_npc") is None
    assert len(trash_list()) >= 1
    # dialog
    ok, m = dlg_new("dlg_test")
    msgs.append(("dlg_new", ok, m))
    ok, m = dlg_line_upsert("dlg_test", {"id": "l1", "text": "你好", "speaker_id": "npc"})
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
        if rec["kind"] == "npc" and rec["id"] == "test_npc":
            ok, m = trash_restore(rec["_file"])
            msgs.append(("trash_restore_npc", ok, m))
            restored += 1
    assert restored == 1 and npc_get("test_npc") is not None
    msgs.append(("log_lines", len(read_log()), "条日志"))
    return msgs


if __name__ == "__main__":
    import tempfile
    d = tempfile.mkdtemp()
    # 造最小工程数据，避免读不到真实文件
    os.makedirs(os.path.join(d, "data", "configs", "npcs"), exist_ok=True)
    os.makedirs(os.path.join(d, "data", "configs", "npcs", "dialogs", "shards"), exist_ok=True)
    os.makedirs(os.path.join(d, "data", "configs", "bond"), exist_ok=True)
    json.dump({"npcs": []}, open(os.path.join(d, "data", "configs", "npcs", "town_npcs.json"), "w", encoding="utf-8"))
    json.dump({"shards": {}}, open(os.path.join(d, "data", "configs", "npcs", "dialogs", "_index.json"), "w", encoding="utf-8"))
    json.dump({}, open(os.path.join(d, "data", "configs", "bond", "celebrations.json"), "w", encoding="utf-8"))
    for name, ok, msg in self_test(d):
        print("[%s] %s -> %s" % (name, "OK" if ok else "FAIL", msg))
    print("SELF_TEST_DONE")
