# -*- coding: utf-8 -*-
"""NPC 内容域服务：区域表感知的 NPC 读写 / 详细资料 / 半身立绘导入 / 欢庆内容。

写操作一律经 NPCRepository（DataSink 六步收口）；删除走回收站（审计域）。
"""

import os
import io
import zipfile
import base64
import shutil
import datetime

from services import _common
from services._common import (  # noqa: F401  门面透传用
    _safe_id, _is_valid_id, _ensure_dirs, load_settings, save_settings,
    load_json, _backup, _backup_dir,
    SAFETY_DIR, TRASH_DIR, BACKUP_DIR, SETTINGS_PATH, LOG_PATH,
    DEFAULT_PROJECT_ROOT, DEFAULT_PORT, DEFAULT_RETENTION_DAYS, DEFAULT_SAFE_MODE,
)
from services.project_service import _paths, _half_body_dir, discover_project_root
from services.audit_service import log_event, trash_put
from services.asset_service import _detect_image_ext
from services.repositories.npc_repository import npc_repo


# ============================ NPC 动态立绘一键导入 ============================
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
            # 防 Zip Slip：先校验每个条目名，拒绝绝对路径与任何含 .. 的路径，再一次性解压
            out_abs = os.path.abspath(out_dir)
            for info in zf.infolist():
                nm = info.filename.replace("\\", "/")
                if nm.startswith("/") or ".." in nm.split("/"):
                    return False, "ZIP 内含非法路径条目：%s" % info.filename, {}
                target = os.path.normpath(os.path.join(out_abs, nm))
                if not target.startswith(out_abs + os.sep) and target != out_abs:
                    return False, "ZIP 条目越界：%s" % info.filename, {}
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


def npc_asset_upload(payload):
    """通用 NPC 图片资源上传：立绘 sprite / 头像 portrait 的「选文件」入口。
    payload: {"filename": "xxx.png", "data": "<base64 单图>"}
    保存到 assets/characters/ 并返回 res:// 路径；文件名会被清洗防路径穿越。
    """
    raw = base64.b64decode(payload.get("data", b"") or b"")
    if not raw:
        return False, "空图片数据", ""
    fn = os.path.basename(str(payload.get("filename", "") or ""))
    low = fn.lower()
    if not low.endswith((".png", ".webp", ".jpg", ".jpeg")):
        return False, "仅支持 png/webp/jpg 图片", ""
    safe = _safe_id(os.path.splitext(fn)[0]) or "asset"
    ext = ".webp" if low.endswith(".webp") else (".jpg" if low.endswith((".jpg", ".jpeg")) else ".png")
    char_dir = os.path.join(_paths()["assets"], "characters")
    os.makedirs(char_dir, exist_ok=True)
    dst = os.path.join(char_dir, "%s%s" % (safe, ext))
    with open(dst, "wb") as f:
        f.write(raw)
    res = "res://assets/characters/%s%s" % (safe, ext)
    log_event("npc_asset", "upload", "上传 NPC 图片 %s" % res)
    return True, "已上传 %s%s" % (safe, ext), res


def npc_half_body_file(res):
    """把 NPC 半身立绘的 res:// 路径解析为可访问的磁盘图片路径；非法/不存在返回 None。

    仅允许 assets/characters/half_body/ 前缀，并用 realpath 强校验落在该目录内，防路径穿越。
    """
    if not res or not isinstance(res, str) or not res.startswith("res://assets/characters/half_body/"):
        return None
    root = discover_project_root()
    base = os.path.realpath(_half_body_dir())
    rel = res[len("res://"):].replace("/", os.sep)
    candidate = os.path.realpath(os.path.join(root, rel))
    if not (candidate == base or candidate.startswith(base + os.sep)):
        return None
    if not (os.path.isfile(candidate) and _detect_image_ext(candidate)):
        return None
    return candidate


# ============================ NPC（区域表感知） ============================
# ---- 区域表感知：NPC 读写统一落脚到 regions/<region>/npcs.json ----
# 背景（两套数据表治理）：旧的 NPC 数据存在全局 town_npcs.json（已迁入区域表并留档备份）。
# 现在 NPC 的读写一律以「区域表」为唯一来源；全局表仅作历史备份不再写入。

def _all_region_ids():
    """所有已建区域的目录名（含 npcs.json 的）列表，按目录名排序。"""
    regions_dir = os.path.join(discover_project_root(), "data", "configs", "regions")
    out = []
    if os.path.isdir(regions_dir):
        for rid in sorted(os.listdir(regions_dir)):
            if os.path.isfile(os.path.join(regions_dir, rid, "npcs.json")):
                out.append(rid)
    return out


def _default_region():
    """默认区域：优先新手村，否则第一个有 npcs.json 的区域；都无则回退 newbie_village。"""
    ids = _all_region_ids()
    if "newbie_village" in ids:
        return "newbie_village"
    return ids[0] if ids else "newbie_village"


def _region_npc_file(rid):
    root = discover_project_root()
    return os.path.join(root, "data", "configs", "regions", str(rid), "npcs.json")


def _load_region_file(rid):
    """读某区域 NPC 表；目录/文件缺失则返回空结构并确保父目录存在。"""
    p = _region_npc_file(rid)
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
    except Exception:
        pass
    data = load_json(p, {"npcs": []})
    if not isinstance(data, dict):
        data = {"npcs": []}
    data.setdefault("npcs", [])
    return p, data


def _load_all_region_npcs():
    """聚合所有区域 NPC：npc_id -> (region_id, npc_dict)。"""
    agg = {}
    for rid in _all_region_ids():
        _, data = _load_region_file(rid)
        for n in data.get("npcs", []):
            if isinstance(n, dict) and n.get("id"):
                agg[str(n["id"])] = (rid, n)
    return agg


def _remove_npc_from_region(rid, nid):
    _, data = _load_region_file(rid)
    data["npcs"] = [n for n in data.get("npcs", []) if n.get("id") != nid]
    npc_repo.save_region(rid, data)


def npc_list():
    out = []
    for rid in _all_region_ids():
        _, data = _load_region_file(rid)
        for n in data.get("npcs", []):
            if not isinstance(n, dict):
                continue
            e = dict(n)
            e["region"] = rid
            out.append(e)
    return out


def npc_get(nid):
    for n in npc_list():
        if n.get("id") == nid:
            return n
    return None


def _upsert_target_region(fields):
    """决定写入哪个区域：优先 fields['region']，其次已存在所在区域，否则默认区域。"""
    rid = str(fields.get("region", "") or "").strip()
    if rid and rid in _all_region_ids():
        return rid
    nid = str(fields.get("id", "") or "").strip()
    if nid:
        agg = _load_all_region_npcs()
        if nid in agg:
            return agg[nid][0]
    return _default_region()


def npc_upsert(fields):
    nid = str(fields.get("id", "")).strip()
    if not nid:
        return False, "id 不能为空"
    rid = _upsert_target_region(fields)
    p, data = _load_region_file(rid)
    # 跨区移动：若该 NPC 当前在其它区域，从旧区域文件里移除
    agg = _load_all_region_npcs()
    old_region = agg.get(nid, (None,))[0]
    if old_region and old_region != rid:
        _remove_npc_from_region(old_region, nid)
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
    entry["scene"] = rid
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
    npc_repo.save_region(rid, data)
    log_event("npc_save", nid, "保存 NPC（区域 %s）" % rid)
    return True, ("更新" if found else "新建") + " NPC %s（区域 %s）" % (nid, rid)


def npc_delete(nid):
    agg = _load_all_region_npcs()
    if nid not in agg:
        return False, "未找到该 NPC"
    rid, removed = agg[nid]
    p, _ = _load_region_file(rid)
    s = load_settings()
    _remove_npc_from_region(rid, nid)
    if s.get("safe_mode", True):
        trash_put("npc", nid, dict(removed), {"type": "npc", "file": p})
        return True, "已删除并放入回收站：%s（区域 %s）" % (nid, rid)
    return True, "已彻底删除：%s" % nid


def npc_rename(old_id, new_id, fields):
    """重命名 NPC 的唯一 ID：删除旧记录（进回收站）、以新 ID 插入，避免产生重复记录。"""
    old_id = str(old_id).strip()
    new_id = str(new_id).strip()
    if not old_id or not new_id:
        return False, "新旧 id 都不能为空"
    if old_id == new_id:
        return npc_upsert(fields)
    agg = _load_all_region_npcs()
    if old_id not in agg:
        return False, "未找到原 id：%s" % old_id
    rid, old_entry = agg[old_id]
    old_entry = dict(old_entry)
    s = load_settings()
    p, data = _load_region_file(rid)
    if s.get("safe_mode", True):
        trash_put("npc", old_id, old_entry, {"type": "npc", "file": p})
    kept = [n for n in data["npcs"] if n.get("id") != old_id]
    entry = {}
    for k in ("name", "sprite", "portrait", "dialog_id", "quest_id", "battle_id"):
        entry[k] = str(fields.get(k, ""))
    try:
        entry["pos_x"] = int(fields.get("pos_x", 0) or 0)
        entry["pos_y"] = int(fields.get("pos_y", 0) or 0)
    except Exception:
        entry["pos_x"] = 0
        entry["pos_y"] = 0
    # 立绘字段在重命名时随旧记录迁移
    for k in ("half_body_portrait", "portrait_type", "portrait_skeleton", "portrait_atlas"):
        if old_entry.get(k):
            entry[k] = old_entry[k]
    if isinstance(old_entry.get("portrait_frames"), list):
        entry["portrait_frames"] = list(old_entry["portrait_frames"])
    entry["id"] = new_id
    target_region = str(fields.get("region", "") or "").strip()
    if not (target_region and target_region in _all_region_ids()):
        target_region = rid
    entry["scene"] = target_region
    if target_region == rid:
        kept.append(entry)
        data["npcs"] = kept
        npc_repo.save_region(rid, data)
    else:
        npc_repo.save_region(rid, {"npcs": kept})
        tp, tdata = _load_region_file(target_region)
        tdata["npcs"].append(entry)
        npc_repo.save_region(target_region, tdata)
    log_event("npc_rename", "%s->%s" % (old_id, new_id), "重命名 NPC（区域 %s）" % target_region)
    return True, "已将 %s 重命名为 %s（旧记录已进回收站，可恢复）" % (old_id, new_id)


# ============================ NPC 详细资料（npc_stats.json） ============================
def npc_stats_get(nid="", merged=False):
    data = load_json(_paths()["npc_stats"], {})
    if not nid:
        return data
    entry = data.get(nid, {})
    if merged and isinstance(entry, dict):
        # 基础字段以区域表为唯一来源（全局表已迁空留档）
        base = npc_get(nid) or {}
        out = dict(base)
        out.pop("region", None)
        out.update(entry)
        return out
    return entry


def npc_stats_upsert(nid, fields):
    nid = str(nid or "").strip()
    if not nid:
        return False, "NPC id 不能为空"
    data = load_json(_paths()["npc_stats"], {})
    if not isinstance(data, dict):
        data = {}
    cur = data.get(nid, {})
    if not isinstance(cur, dict):
        cur = {}
    entry = dict(cur)
    if "title" in fields:
        entry["title"] = str(fields.get("title", ""))
    for k in ("level", "attack", "defense", "hp"):
        if k in fields and fields.get(k) is not None and fields[k] != "":
            try:
                entry[k] = int(fields[k])
            except (TypeError, ValueError):
                entry[k] = 0
    for k in ("martial_arts", "gift_prefs"):
        if k in fields:
            v = fields.get(k)
            entry[k] = [str(x).strip() for x in (v if isinstance(v, list) else []) if str(x).strip()] if isinstance(v, list) else []
    if "can_spar" in fields:
        entry["can_spar"] = bool(fields.get("can_spar"))
    if "backpack_note" in fields:
        entry["backpack_note"] = str(fields.get("backpack_note", ""))
    data[nid] = entry
    npc_repo.save_npc_stats(data)
    log_event("npc_stats_save", nid, "保存 NPC 详细资料")
    return True, "已保存 NPC 详细资料 %s" % nid


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
    npc_repo.save_celebrations(data)
    log_event("cel_save", npc_id, "保存欢庆内容")
    return True, "已保存 %s 的欢庆内容" % npc_id


def cel_delete(npc_id):
    data = load_json(_paths()["cel"], {})
    if npc_id not in data:
        return False, "未找到该 NPC"
    removed = data[npc_id]
    s = load_settings()
    del data[npc_id]
    npc_repo.save_celebrations(data)
    if s.get("safe_mode", True):
        trash_put("celebration", npc_id, removed,
                  {"type": "celebration", "npc_id": npc_id, "file": _paths()["cel"]})
        return True, "已删除并放入回收站：%s" % npc_id
    return True, "已彻底删除：%s" % npc_id
