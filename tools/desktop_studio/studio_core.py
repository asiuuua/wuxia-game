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
import csv
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
        from datetime import datetime
        mtime = datetime.fromtimestamp(st.st_mtime).strftime("%Y-%m-%d %H:%M")
        import hashlib
        h = hashlib.md5()
        with open(exe_path, "rb") as f:
            for b in iter(lambda: f.read(1 << 20), b""):
                h.update(b)
        md5 = h.hexdigest()[:8]
        return {"build_time": mtime, "md5": md5, "path": exe_path,
                "root": discover_project_root()}
    except Exception as e:
        return {"build_time": "unknown", "md5": "unknown", "path": str(exe_path), "root": discover_project_root(), "error": str(e)}


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


# ============================ NPC 动态立绘一键导入 ============================
# 合并进 NPC 编辑列：支持「静态图片 / 帧动画(ZIP) / Spine骨骼(ZIP)」三种类型一键导入。
# 导入后写入 NPC 的 half_body_portrait 字段（静态取该图路径；动态取目录），
# 并附带 portrait_type / portrait_frames(NPC 面板与对话框后续按此切换动态立绘)。
# ⚠️ 这些字段是「共享地基纯追加」——旧 NPC 无这些字段时游戏侧 resolve_half_body 会回退占位，零破坏。
import zipfile

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


# ============================ 任务流程图（QuestGraph） ============================
# T2：让编辑器认识 regions 分片里 type == "quest_graph" 的新结构。
# 后端只做「读取 → 平铺成可视化友好列表」，不搬数据、不写回；写回仍走各自任务文件。
def quest_graph_list():
    root = discover_project_root()
    regions_dir = os.path.join(root, "data", "configs", "regions")
    out = []
    if not os.path.isdir(regions_dir):
        return out
    for region in sorted(os.listdir(regions_dir)):
        qs_path = os.path.join(regions_dir, region, "quests.json")
        if not os.path.isfile(qs_path):
            continue
        data = load_json(qs_path, {"quests": []})
        for q in data.get("quests", []):
            if not isinstance(q, dict) or q.get("type") != "quest_graph":
                continue
            graph = q.get("quest_graph") or {}
            nodes = graph.get("nodes") or {}
            out.append({
                "region": region,
                "id": q.get("id", ""),
                "name": q.get("name", q.get("id", "")),
                "start_node": graph.get("start_node", ""),
                "node_count": len(nodes),
                "node_types": sorted({str(n.get("type", "?")) for n in nodes.values() if isinstance(n, dict)}),
                "endings": [e.get("id") for e in (graph.get("endings") or []) if isinstance(e, dict)],
                "nodes": nodes,
                "objectives": q.get("objectives", []),
            })
    return out


def quest_graph_get(qid):
    for q in quest_graph_list():
        if q.get("id") == qid:
            return q
    return None


def _find_graph_refs(start, nodes):
    """找出指向不存在节点的硬引用；存图前校验，防止写坏运行时图。"""
    refs = []
    for nid, n in nodes.items():
        if not isinstance(n, dict):
            continue
        for k in ("next", "on_win_next", "on_lose_next"):
            v = n.get(k)
            if isinstance(v, str) and v and v not in nodes:
                refs.append("%s.%s→%s" % (nid, k, v))
        opts = n.get("options")
        if isinstance(opts, list):
            for j, o in enumerate(opts):
                if isinstance(o, dict) and o.get("jump_id") and o["jump_id"] not in nodes:
                    refs.append("%s.options[%d].jump_id→%s" % (nid, j, o["jump_id"]))
    if start and start not in nodes:
        refs.append("start_node→%s" % start)
    return refs


def quest_graph_save(region, qid, graph):
    """T2 写回：把可视化编辑后的图存回 regions/<region>/quests.json 的对应 quest。
    先校验节点引用，save_json 自带备份；只有 type==quest_graph 且 id 匹配才写。"""
    root = discover_project_root()
    qs_path = os.path.join(root, "data", "configs", "regions", str(region), "quests.json")
    if not os.path.isfile(qs_path):
        return False, "找不到任务文件 regions/%s/quests.json" % region
    graph = graph or {}
    nodes = graph.get("nodes")
    if not isinstance(nodes, dict):
        return False, "quest_graph 缺 nodes（须为字典）"
    start = graph.get("start_node", "")
    bad = _find_graph_refs(start, nodes)
    if bad:
        return False, "存在指向不存在节点的引用，已拦截保存：%s" % "; ".join(sorted(set(bad))[:8])
    data = load_json(qs_path, {"quests": []})
    if not isinstance(data.get("quests"), list):
        return False, "quests.json 缺少 quests 数组"
    for q in data["quests"]:
        if isinstance(q, dict) and q.get("id") == qid and q.get("type") == "quest_graph":
            q["quest_graph"] = graph
            save_json(qs_path, data)
            log_event("quest_graph_save", qid, "区域 %s 保存任务流程图" % region)
            return True, "已保存任务图 %s（区域 %s）" % (qid, region)
    return False, "未找到 quest id=%s（type=quest_graph）" % qid


# ============================ i18n 文案表（strings.csv，多语言只加表） ============================
# 游戏 LocalizationManager 读 data/configs/localization/strings.csv（key,zh_CN,zh_TW,en）注册进
# TranslationServer，之后全局 tr(text_key) 即返回当前语言文案。这里把文案表接回后台，方便小白
# 只改表、不改逻辑地做多语言。
def _i18n_path():
    return os.path.join(discover_project_root(), "data", "configs", "localization", "strings.csv")


def i18n_read():
    path = _i18n_path()
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.reader(f))


def i18n_list():
    rows = i18n_read()
    if not rows:
        return []
    out = []
    for r in rows[1:]:
        if not r or not str(r[0]).strip():
            continue
        def cell(i):
            return str(r[i]).strip() if i < len(r) else ""
        out.append({"key": str(r[0]).strip(), "zh_CN": cell(1), "zh_TW": cell(2), "en": cell(3)})
    return out


def i18n_upsert(key, zh_cn="", zh_tw="", en=""):
    key = str(key or "").strip()
    if not key:
        return False, "key 不能为空"
    rows = i18n_read()
    if not rows:
        rows = [["keys", "zh_CN", "zh_TW", "en"]]
    found = False
    for r in rows[1:]:
        if r and str(r[0]).strip() == key:
            while len(r) < 4:
                r.append("")
            for i, v in ((1, zh_cn), (2, zh_tw), (3, en)):
                if str(v).strip() != "":
                    r[i] = str(v)
            found = True
            break
    if not found:
        rows.append([key, str(zh_cn), str(zh_tw), str(en)])
    path = _i18n_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    _backup(path)
    with open(path, "w", encoding="utf-8", newline="") as f:
        csv.writer(f).writerows(rows)
    log_event("i18n_save", key, "更新文案表")
    return True, "已保存文案 %s（多语言立即生效）" % key


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


# ============================ NPC ============================
def _shard_path(dlg_id):
    return os.path.join(_paths()["dlg_dir"], "%s.json" % dlg_id)


# ---- 区域表感知：NPC 读写统一落脚到 regions/<region>/npcs.json ----
# 背景（两套数据表治理）：旧的 NPC 数据存在全局 town_npcs.json（已迁入区域表并留档备份）。
# 现在 NPC 的读写一律以「区域表」为唯一来源；全局表仅作历史备份不再写入。
# 新增默认落新手村；跨区域选择通过 fields['region'] 指定；跨区保存自动迁移。

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
    p, data = _load_region_file(rid)
    data["npcs"] = [n for n in data.get("npcs", []) if n.get("id") != nid]
    save_json(p, data)


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
    save_json(p, data)
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
        save_json(p, data)
    else:
        save_json(p, {"npcs": kept})
        tp, tdata = _load_region_file(target_region)
        tdata["npcs"].append(entry)
        save_json(tp, tdata)
    log_event("npc_rename", "%s->%s" % (old_id, new_id), "重命名 NPC（区域 %s）" % target_region)
    return True, "已将 %s 重命名为 %s（旧记录已进回收站，可恢复）" % (old_id, new_id)


# ============================ 对话 / 剧情 ============================
# ============================ NPC 详细资料（npc_stats.json） ============================
# 属性/好感/送礼/武学/切磋/背包这类"详细资料"此前与后台完全脱节（孤儿表）。
# 这里把它接回后台：get 读全表供面板渲染，upsert 按 npc_id 写回单个档案（合并、不覆盖未传字段）。
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
    save_json(_paths()["npc_stats"], data)
    log_event("npc_stats_save", nid, "保存 NPC 详细资料")
    return True, "已保存 NPC 详细资料 %s" % nid


def dlg_list():
    idx = load_json(_paths()["dlg_index"], {"shards": {}})
    return list(idx.get("shards", {}).keys())


def dlg_get(dlg_id):
    if not _is_valid_id(dlg_id):
        return {}
    return load_json(_shard_path(dlg_id), {"id": dlg_id, "lines": []})


def dlg_new(dlg_id):
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
    save_json(_shard_path(dlg_id), shard)
    idx["shards"][dlg_id] = {"file": file, "npc_id": "", "chapter": "custom"}
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


def _ensure_gdignore():
    """确保工具目录里有 .gdignore：否则 Godot 会把 studio 目录（含 safety_data/backups 里的
    历史备份图）当游戏资源扫描导入，遇到扩展名错配的备份就刷屏报 ERR_FILE_CORRUPT。"""
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".gdignore")
    if os.path.exists(p):
        return
    try:
        with open(p, "w", encoding="utf-8") as f:
            f.write("# 让 Godot 忽略「内容工作室」工具目录（非游戏资源，且备份区含历史坏图）\n")
    except Exception:
        pass


_ensure_gdignore()


def _login_bg_base():
    return os.path.join(discover_project_root(), "assets", "ui", "main_menu_bg")


def _detect_image_ext(src_path):
    """读文件头判定真实图片格式。返回 'png' / 'jpg' / 'webp'；**无法识别时返回 None**（调用方必须拒绝，
    不能兜底成 jpg —— 曾因兜底把 TIFF 存成 .png，Godot 导入失败，按钮背景静默消失）。"""
    try:
        with open(src_path, "rb") as f:
            head = f.read(16)
    except Exception:
        return None
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if head[:3] == b"\xff\xd8\xff":
        return "jpg"
    # WEBP: "RIFF" + 4 字节长度 + "WEBP"
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "webp"
    return None


def _image_size(path):
    """纯 Python 读取图片像素尺寸 (w, h)，失败返回 (0, 0)。
    刻意不依赖 Pillow —— 打包 exe 用的是精简解释器，装不上第三方库。"""
    try:
        with open(path, "rb") as f:
            head = f.read(64)
        if head[:8] == b"\x89PNG\r\n\x1a\n" and len(head) >= 24:
            import struct as _s
            return _s.unpack(">II", head[16:24])
        if head[:3] == b"\xff\xd8\xff":
            return _jpeg_size(path)
        if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
            return _webp_size(path)
    except Exception:
        pass
    return (0, 0)


def _jpeg_size(path):
    import struct as _s
    with open(path, "rb") as f:
        f.read(2)
        while True:
            b = f.read(1)
            if not b:
                return (0, 0)
            if b != b"\xff":
                continue
            while b == b"\xff":
                b = f.read(1)
                if not b:
                    return (0, 0)
            marker = b[0]
            if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                continue
            ln_bytes = f.read(2)
            if len(ln_bytes) < 2:
                return (0, 0)
            ln = _s.unpack(">H", ln_bytes)[0]
            if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                          0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                seg = f.read(5)
                if len(seg) < 5:
                    return (0, 0)
                h, w = _s.unpack(">HH", seg[1:5])
                return (w, h)
            if ln < 2:
                return (0, 0)
            f.seek(ln - 2, 1)


def _webp_size(path):
    import struct as _s
    with open(path, "rb") as f:
        f.read(12)
        while True:
            chunk = f.read(8)
            if len(chunk) < 8:
                return (0, 0)
            fourcc = chunk[0:4]
            size = _s.unpack("<I", chunk[4:8])[0]
            data = f.read(min(size, 32))
            if fourcc == b"VP8 " and len(data) >= 10:
                return (_s.unpack("<H", data[6:8])[0] & 0x3FFF,
                        _s.unpack("<H", data[8:10])[0] & 0x3FFF)
            if fourcc == b"VP8L" and len(data) >= 5:
                bits = int.from_bytes(data[1:5], "little")
                return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
            if fourcc == b"VP8X" and len(data) >= 12:
                return (int.from_bytes(data[4:7], "little") + 1,
                        int.from_bytes(data[7:10], "little") + 1)
            f.seek(size % 2, 1)


# 清晰度诊断参考分辨率（任务 #47：判断当前图在目标屏上会不会被放大到模糊）
CLARITY_TARGETS = [
    ("1080p", 1920, 1080),
    ("2K", 2560, 1440),
    ("4K", 3840, 2160),
]


def clarity_report(path):
    """给出背景图的清晰度诊断：像素尺寸 + 在各目标屏上的放大倍率与是否模糊。"""
    w, h = _image_size(path)
    if w <= 0 or h <= 0:
        return {"exists": False, "width": 0, "height": 0, "targets": []}
    out = []
    for name, tw, th in CLARITY_TARGETS:
        # 铺满裁切(cover)下要按「较大的那个方向」放大才能填满，取 max 才是真实采样倍率
        scale = max(tw / float(w), th / float(h))
        if scale > 1.25:
            verdict = "模糊"
        elif scale > 1.05:
            verdict = "轻微发虚"
        else:
            verdict = "清晰"
        out.append({"name": name, "width": tw, "height": th,
                    "scale": round(scale, 2), "verdict": verdict})
    return {"exists": True, "width": w, "height": h, "targets": out}


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
        return {"exists": False, "size": 0, "mtime": 0, "ext": "", "width": 0, "height": 0, "targets": []}
    st = os.stat(p)
    w, h = _image_size(p)
    info = {"exists": True, "size": st.st_size, "mtime": st.st_mtime,
            "ext": os.path.splitext(p)[1].lstrip("."), "width": w, "height": h,
            "targets": clarity_report(p).get("targets", [])}
    return info


def login_bg_replace(src_path):
    ext = _detect_image_ext(src_path)
    if ext is None:
        return False, "无法识别的图片格式（Godot 只支持 PNG / JPG / WEBP）。请先把 TIFF、BMP、HEIC 等转成 PNG 再上传。"
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
    # 防路径穿越：按钮 id 白名单校验（字母/数字/下划线/短横线），否则可能把图写出 assets 目录
    btn_id = str(btn_id or "").strip()
    if not _is_valid_id(btn_id):
        return False, "按钮 id 非法（仅允许字母/数字/下划线/短横线）"
    # 关键：先读文件头判真实格式再决定扩展名。Godot 按扩展名选解码器，
    # 扩展名错配（如 TIFF 存成 .png）会导致导入失败、按钮背景静默消失。
    ext = _detect_image_ext(src_path)
    if ext is None:
        return False, "无法识别的图片格式（Godot 只支持 PNG / JPG / WEBP）。请先把 TIFF、BMP、HEIC 等转成 PNG 再上传。"
    d = _login_btn_bg_dir()
    os.makedirs(d, exist_ok=True)
    os.makedirs(os.path.dirname(_login_btn_bg_cfg()), exist_ok=True)
    fname = "%s.%s" % (btn_id, ext)
    dst = os.path.join(d, fname)
    # 清掉其它扩展名的同名残留（上次可能是另一种格式），避免 Godot 导入到旧文件
    for other_ext in ("png", "jpg", "webp"):
        if other_ext == ext:
            continue
        stale = os.path.join(d, "%s.%s" % (btn_id, other_ext))
        if os.path.exists(stale):
            _backup(stale)
            try:
                os.remove(stale)
            except OSError:
                pass
    _backup(dst)
    shutil.copy2(src_path, dst)
    w, h = _image_size(dst)
    cfg = _login_btn_bg_cfg()
    data = {}
    if os.path.exists(cfg):
        try:
            data = json.load(open(cfg, "r", encoding="utf-8"))
        except Exception:
            data = {}
    if "map" not in data:
        data["map"] = {}
    data["map"][btn_id] = "res://assets/ui/main_menu_btn/%s" % fname
    data["_doc"] = "登录主菜单各按钮背景图映射。游戏代码已读取此表（MainMenu._load_btn_bg_map → MenuItem.set_background），上传图片后下次进主菜单即生效。扩展名由工具按文件头真实格式写入，勿手改。"
    with open(cfg, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("login_btn_bg", btn_id, "存储按钮背景图（真实格式=%s，%dx%d）" % (ext, w, h))
    tip = ""
    if w > 0 and h > 0:
        ratio = w / float(h)
        # 按钮是 280x44 的横条，贴图严重竖长会被 cover 裁得只剩中间一条
        if ratio < 1.2:
            tip = " ⚠️ 这张是竖图（%dx%d），按钮是横条，会被裁得只剩中间一小条，建议换横版图。" % (w, h)
    return True, "已存储 %s 的按钮背景图（%s，%dx%d，下次进主菜单即生效）%s" % (btn_id, ext, w, h, tip)


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


# ============================ 主菜单(登录)界面布局（自由拖拽可视化编辑） ============================
def _main_menu_layout_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "main_menu_layout.json")


# 三个可拖拽块（与游戏 MainMenu._apply_layout 的 keys 对应）。
# 坐标统一用「视口归一化 0~1」：x/y 为块左上角位置；w/h 为占视口比例（仅用于预览框尺寸，
# 游戏侧 MenuContainer 用 anchor 四值定位，BottomLeft/BottomRight 用 anchor+offset）。
# separation 仅 MenuContainer 用（按钮间距，像素）。
MAIN_MENU_ELEMS = ["title_group", "menu_container", "bottom_left", "bottom_right"]

_MAIN_MENU_LAYOUT_DEFAULT = {
    "elements": {
        # 标题组：墨影江湖 Logo + 副标题。用绝对 offset 定位（与 .tscn 默认一致）
        "title_group": {"anchor_left": 0.0, "anchor_top": 0.0, "anchor_right": 0.0,
                        "anchor_bottom": 0.0, "offset_left": 60.0, "offset_top": 48.0,
                        "offset_right": 540.0, "offset_bottom": 220.0},
        # MenuContainer：5 个主菜单按钮的纵向容器。anchor 四值定位
        "menu_container": {"anchor_left": 0.06, "anchor_top": 0.32, "anchor_right": 0.42,
                           "anchor_bottom": 0.78, "offset_left": 0.0, "offset_top": 0.0,
                           "offset_right": 0.0, "offset_bottom": 0.0, "separation": 18},
        # 左下角：版本号 / 制作组文字
        "bottom_left": {"anchor_left": 0.0, "anchor_top": 1.0, "anchor_right": 0.0,
                        "anchor_bottom": 1.0, "offset_left": 24.0, "offset_top": -56.0,
                        "offset_right": 360.0, "offset_bottom": -32.0},
        # 右下角：设置 / 音量 / 语言 三个按钮
        "bottom_right": {"anchor_left": 1.0, "anchor_top": 1.0, "anchor_right": 1.0,
                         "anchor_bottom": 1.0, "offset_left": -360.0, "offset_top": -68.0,
                         "offset_right": -80.0, "offset_bottom": -32.0},
    }
}


def main_menu_layout_get():
    """读取当前主菜单布局（与默认合并，缺字段补默认）。"""
    p = _main_menu_layout_path()
    data = {"elements": {k: dict(v) for k, v in _MAIN_MENU_LAYOUT_DEFAULT["elements"].items()}}
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                parsed = json.load(f)
            if isinstance(parsed, dict) and isinstance(parsed.get("elements"), dict):
                for k in MAIN_MENU_ELEMS:
                    if k in parsed["elements"]:
                        data["elements"][k].update(parsed["elements"][k])
        except Exception:
            pass
    return data


def main_menu_layout_update(d):
    """写入主菜单布局（自动备份旧文件）。d 形如 {"elements": {...}}。"""
    p = _main_menu_layout_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    data = {"elements": {}}
    for k in MAIN_MENU_ELEMS:
        spec = dict(_MAIN_MENU_LAYOUT_DEFAULT["elements"].get(k, {}))
        incoming = (d.get("elements", {}) or {}).get(k, {})
        if isinstance(incoming, dict):
            spec.update(incoming)
        # anchor 裁剪到 0~1；offset 不限（像素，可负）；separation 非负
        for ck in ("anchor_left", "anchor_top", "anchor_right", "anchor_bottom"):
            if ck in spec:
                spec[ck] = max(0.0, min(1.0, float(spec[ck])))
        for ck in ("offset_left", "offset_top", "offset_right", "offset_bottom"):
            if ck in spec:
                spec[ck] = float(spec[ck])
        if "separation" in spec:
            spec["separation"] = max(0, int(spec["separation"]))
        data["elements"][k] = spec
    data["_doc"] = "主菜单(登录)界面元素布局（工作室「登录界面 → 主菜单布局」自由拖拽编辑写入）。" \
                   "menu_container 用 anchor 四值 + offset 定位，separation 为按钮间距(像素)；“bottom_*” 用 anchor + offset 定位。坐标为视口归一化 0~1。"
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("main_menu_layout", p, "更新主菜单布局")
    return True, "已保存主菜单布局（游戏内下次启动生效）"


# ============================ HUD 布局（工作室「UI 模块 → HUD 布局」可视化编辑） ============================
# 四面板默认位置（参考分辨率 1920x1080 下的绝对坐标）。游戏侧按当前视口等比缩放后应用；
# 玩家在游戏内拖拽后落点存 user://ui/hud_positions.json（个人偏好），优先于本默认值。
def _hud_layout_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "hud_layout.json")


# 四面板默认位置（与游戏各面板既有硬编码默认一致，保证「恢复默认」= 当前行为）
# scale: 统一缩放系数（uniform，不改内部布局比例；0.6~2.5 安全区间），默认 1.0
_HUD_LAYOUT_DEFAULT = {
    "panels": {
        "status_card":    {"x": 12.0,   "y": 12.0,   "scale": 1.0},
        "quest_track":    {"x": 12.0,   "y": 362.0,  "scale": 1.0},
        "top_right_menu": {"x": 1700.0, "y": 12.0,   "scale": 1.0},
        "skill_bar":      {"x": 782.0,  "y": 980.0,  "scale": 1.0},
    }
}

_HUD_PANEL_KEYS = ("status_card", "quest_track", "top_right_menu", "skill_bar")
_HUD_REF_W = 1920.0
_HUD_REF_H = 1080.0
_HUD_SCALE_MIN = 0.6
_HUD_SCALE_MAX = 2.5


def _is_num(v):
    # 排除 bool（bool 是 int 子类），只接受真正的数字
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def hud_layout_get():
    """读取 HUD 四面板默认位置（与默认合并，缺字段补默认）。"""
    p = _hud_layout_path()
    data = {"panels": {k: dict(v) for k, v in _HUD_LAYOUT_DEFAULT["panels"].items()}}
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                parsed = json.load(f)
            if isinstance(parsed, dict) and isinstance(parsed.get("panels"), dict):
                for k in _HUD_PANEL_KEYS:
                    spec = parsed["panels"].get(k)
                    if isinstance(spec, dict):
                        cur = data["panels"][k]
                        if _is_num(spec.get("x")):
                            cur["x"] = float(spec["x"])
                        if _is_num(spec.get("y")):
                            cur["y"] = float(spec["y"])
                        if _is_num(spec.get("scale")):
                            cur["scale"] = max(_HUD_SCALE_MIN, min(_HUD_SCALE_MAX, float(spec["scale"])))
        except Exception:
            pass
    data["_doc"] = "HUD 四面板默认位置（工作室「UI 模块 → HUD 布局」拖拽编辑写入）。坐标为参考分辨率 1920x1080 下的屏幕绝对坐标；游戏运行时按当前视口等比缩放（保证任意分辨率下布局比例一致）。玩家在游戏内拖拽后会以 user://ui/hud_positions.json 个人偏好覆盖此处设定；点「恢复默认」即回到此处数值。"
    data["reference_width"] = _HUD_REF_W
    data["reference_height"] = _HUD_REF_H
    return data


def hud_layout_update(d):
    """写入 HUD 布局（自动备份旧文件）。d 形如 {"panels": {"status_card": {"x":..,"y":..}, ...}}。"""
    p = _hud_layout_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    data = {"panels": {}}
    for k in _HUD_PANEL_KEYS:
        spec = dict(_HUD_LAYOUT_DEFAULT["panels"].get(k, {"x": 0.0, "y": 0.0}))
        incoming = (d.get("panels", {}) or {}).get(k, {})
        if isinstance(incoming, dict):
            if _is_num(incoming.get("x")):
                spec["x"] = max(0.0, min(_HUD_REF_W, float(incoming["x"])))
            if _is_num(incoming.get("y")):
                spec["y"] = max(0.0, min(_HUD_REF_H, float(incoming["y"])))
            if _is_num(incoming.get("scale")):
                spec["scale"] = max(_HUD_SCALE_MIN, min(_HUD_SCALE_MAX, float(incoming["scale"])))
        data["panels"][k] = spec
    data["_doc"] = "HUD 四面板默认位置（工作室「UI 模块 → HUD 布局」拖拽编辑写入）。坐标为参考分辨率 1920x1080 下的屏幕绝对坐标；游戏运行时按当前视口等比缩放。玩家拖拽偏好存 user://ui/hud_positions.json，优先于此默认。"
    data["reference_width"] = _HUD_REF_W
    data["reference_height"] = _HUD_REF_H
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("hud_layout", p, "更新 HUD 布局")
    return True, "已保存 HUD 布局（游戏内下次启动生效）"


# ============================ 设置弹窗布局（工作室「UI 模块 → 设置弹窗」数字编辑） ============================
_SETTINGS_SCREEN_LAYOUT_DEFAULT = {
    "_doc": "设置弹窗面板几何（工作室「UI 模块 → 设置弹窗」可拖拽/输入编辑）。panel_max_width/height 为面板在参考分辨率 1920x1080 下的封顶尺寸；游戏运行时按当前视口等比自适应，不超过封顶值。margin_x_ratio / margin_y_ratio 为左右/上下留白比例。category_button_* 为左侧分类按钮最小尺寸。",
    "reference_width": 1920.0,
    "reference_height": 1080.0,
    "panel_max_width": 960.0,
    "panel_max_height": 680.0,
    "margin_x_ratio": 0.08,
    "margin_y_ratio": 0.10,
    "category_button_min_width": 160.0,
    "category_button_min_height": 42.0,
}
_SETTINGS_SCREEN_LAYOUT_KEYS = (
    "panel_max_width", "panel_max_height", "margin_x_ratio", "margin_y_ratio",
    "category_button_min_width", "category_button_min_height",
)


def _settings_screen_layout_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "skin", "settings_screen.layout.json")


def settings_screen_layout_get():
    """读取设置弹窗面板几何（与默认合并，缺字段/坏文件回退默认）。"""
    p = _settings_screen_layout_path()
    data = dict(_SETTINGS_SCREEN_LAYOUT_DEFAULT)
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                stored = json.load(f)
            if isinstance(stored, dict):
                for k in _SETTINGS_SCREEN_LAYOUT_KEYS:
                    if _is_num(stored.get(k)):
                        data[k] = float(stored[k])
        except Exception:
            pass
    return data


def settings_screen_layout_update(d):
    """写入设置弹窗面板几何（自动备份旧文件）。d 为包含可编辑数字字段的字典。"""
    p = _settings_screen_layout_path()
    _backup(p)
    data = dict(_SETTINGS_SCREEN_LAYOUT_DEFAULT)
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                stored = json.load(f)
            if isinstance(stored, dict):
                for k in _SETTINGS_SCREEN_LAYOUT_KEYS:
                    if _is_num(stored.get(k)):
                        data[k] = float(stored[k])
        except Exception:
            pass
    if isinstance(d, dict):
        for k in _SETTINGS_SCREEN_LAYOUT_KEYS:
            if _is_num(d.get(k)):
                data[k] = max(0.0, float(d[k]))
    data["_doc"] = _SETTINGS_SCREEN_LAYOUT_DEFAULT["_doc"]
    data["reference_width"] = _SETTINGS_SCREEN_LAYOUT_DEFAULT["reference_width"]
    data["reference_height"] = _SETTINGS_SCREEN_LAYOUT_DEFAULT["reference_height"]
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("settings_screen_layout", p, "更新设置弹窗布局")
    return True, "已保存设置弹窗布局（游戏内下次启动生效）"


def _SAVELOAD_SCREEN_LAYOUT_DEFAULT():
    return {
        "_doc": "读档界面存档卡片列几何（工作室「UI 模块 → 读档弹窗」可数值编辑）。content_max_width/height 为居中列封顶尺寸；margin_x_ratio/margin_y_ratio 为左右留白/列表顶距比例；card_min_width/height 为单张存档卡最小尺寸。",
        "reference_width": 1920.0,
        "reference_height": 1080.0,
        "content_max_width": 640.0,
        "content_max_height": 724.0,
        "margin_x_ratio": 0.0,
        "margin_y_ratio": 0.15,
        "card_min_width": 640.0,
        "card_min_height": 112.0,
    }


_SAVELOAD_SCREEN_LAYOUT_KEYS = (
    "content_max_width", "content_max_height", "margin_x_ratio", "margin_y_ratio",
    "card_min_width", "card_min_height",
)


def _saveload_screen_layout_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "skin", "saveload_screen.layout.json")


def saveload_screen_layout_get():
    """读取读档界面卡片列几何（与默认合并，缺字段/坏文件回退默认）。"""
    p = _saveload_screen_layout_path()
    data = dict(_SAVELOAD_SCREEN_LAYOUT_DEFAULT())
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                stored = json.load(f)
            if isinstance(stored, dict):
                for k in _SAVELOAD_SCREEN_LAYOUT_KEYS:
                    if _is_num(stored.get(k)):
                        data[k] = float(stored[k])
        except Exception:
            pass
    return data


def saveload_screen_layout_update(d):
    """写入读档界面卡片列几何（自动备份旧文件）。d 为包含可编辑数字字段的字典。"""
    p = _saveload_screen_layout_path()
    _backup(p)
    data = dict(_SAVELOAD_SCREEN_LAYOUT_DEFAULT())
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                stored = json.load(f)
            if isinstance(stored, dict):
                for k in _SAVELOAD_SCREEN_LAYOUT_KEYS:
                    if _is_num(stored.get(k)):
                        data[k] = float(stored[k])
        except Exception:
            pass
    if isinstance(d, dict):
        for k in _SAVELOAD_SCREEN_LAYOUT_KEYS:
            if _is_num(d.get(k)):
                data[k] = max(0.0, float(d[k]))
    data["_doc"] = _SAVELOAD_SCREEN_LAYOUT_DEFAULT()["_doc"]
    data["reference_width"] = _SAVELOAD_SCREEN_LAYOUT_DEFAULT()["reference_width"]
    data["reference_height"] = _SAVELOAD_SCREEN_LAYOUT_DEFAULT()["reference_height"]
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("saveload_screen_layout", p, "更新读档界面布局")
    return True, "已保存读档界面布局（游戏内下次启动生效）"


# ============================ UI 皮肤定制（工作室「UI 皮肤定制」tab，UI 窗口主权） ============================
# 只读写 data/configs/ui/skin/ 下的白名单文件，杜绝路径穿越；游戏侧零依赖、缺省回退。
def _ui_skin_dir():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "skin")


def _ui_skin_path(kind):
    # 白名单：只允许这几个文件，杜绝路径穿越
    allowed = {
        "theme": os.path.join(_ui_skin_dir(), "theme.json"),
        "confirm_dialog_layout": os.path.join(_ui_skin_dir(), "confirm_dialog.layout.json"),
        "main_menu_vfx": os.path.join(_ui_skin_dir(), "main_menu.vfx.json"),
    }
    return allowed.get(kind)


def ui_skin_get():
    """读取 UI 皮肤当前配置：theme.json + confirm_dialog.layout.json + main_menu.vfx.json（缺文件回退内置默认）。"""
    out = {}
    for kind in ("theme", "confirm_dialog_layout", "main_menu_vfx"):
        p = _ui_skin_path(kind)
        if p and os.path.exists(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    out[kind] = json.load(f)
            except Exception:
                out[kind] = {}
        else:
            out[kind] = {}
    out["_defaults"] = {
        "theme": {"panel_bg": [0.071, 0.078, 0.11, 0.62], "panel_border": [1, 1, 1, 0.2],
                  "title_color": [0.831, 0.686, 0.216, 1], "content_color": [0.941, 0.902, 0.82, 1],
                  "accent": [0.55, 0.78, 0.45, 1]},
        "confirm_dialog_layout": {"panel_width": 440, "panel_height": 220},
        "main_menu_vfx": {"enabled_cloud": True, "cloud_speed": 30.0, "enabled_water": True,
                          "water_min_alpha": 0.6, "water_max_alpha": 1.0, "water_period": 2.5,
                          "enabled_boat": True, "boat_speed": 20.0, "enabled_leaves": True,
                          "leaves_amount": 24, "leaves_lifetime": 9.0, "leaves_gravity_y": 26.0,
                          "leaves_vel_min": 18.0, "leaves_vel_max": 55.0, "leaves_scale": 1.6},
    }
    return out


def ui_skin_save(kind, data):
    """保存 UI 皮肤配置。kind 必须在白名单；data 必须为 dict。自动备份旧文件。
    数值类（确认框尺寸）做合理裁剪，避免小白拉到离谱值。"""
    if not isinstance(kind, str) or not isinstance(data, dict):
        return False, "参数非法（kind 需字符串、data 需对象）"
    p = _ui_skin_path(kind)
    if p is None:
        return False, "未知的皮肤类型（仅允许 theme / confirm_dialog_layout）"
    if kind == "confirm_dialog_layout":
        w = int(data.get("panel_width", 440))
        h = int(data.get("panel_height", 220))
        w = max(200, min(1600, w))
        h = max(120, min(1200, h))
        data = {"_doc": "确认框尺寸（工作室「UI 皮肤定制 → 确认框尺寸」滑块写入）。",
                "panel_width": w, "panel_height": h}
    if kind == "main_menu_vfx":
        # 裁剪到合理区间，避免小白把粒子/速度拉到离谱值拖垮性能
        d = {}
        d["enabled_cloud"] = bool(data.get("enabled_cloud", True))
        d["cloud_speed"] = max(2.0, min(120.0, float(data.get("cloud_speed", 30.0))))
        d["enabled_water"] = bool(data.get("enabled_water", True))
        d["water_min_alpha"] = max(0.0, min(1.0, float(data.get("water_min_alpha", 0.6))))
        d["water_max_alpha"] = max(0.0, min(1.0, float(data.get("water_max_alpha", 1.0))))
        d["water_period"] = max(0.5, min(10.0, float(data.get("water_period", 2.5))))
        d["enabled_boat"] = bool(data.get("enabled_boat", True))
        d["boat_speed"] = max(2.0, min(120.0, float(data.get("boat_speed", 20.0))))
        d["enabled_leaves"] = bool(data.get("enabled_leaves", True))
        d["leaves_amount"] = int(max(0, min(200, int(data.get("leaves_amount", 24)))))
        d["leaves_lifetime"] = max(1.0, min(30.0, float(data.get("leaves_lifetime", 9.0))))
        d["leaves_gravity_y"] = max(0.0, min(200.0, float(data.get("leaves_gravity_y", 26.0))))
        d["leaves_vel_min"] = max(0.0, min(200.0, float(data.get("leaves_vel_min", 18.0))))
        d["leaves_vel_max"] = max(0.0, min(300.0, float(data.get("leaves_vel_max", 55.0))))
        d["leaves_scale"] = max(0.2, min(5.0, float(data.get("leaves_scale", 1.6))))
        d["_doc"] = "主菜单（程序化水墨背景）视觉特效参数（工作室「UI 皮肤定制 → 视觉特效」面板可改）。"
        data = d
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("ui_skin", p, "保存 UI 皮肤：%s" % kind)
    return True, "已保存 %s（游戏内下次启动生效）" % kind


# ============================ 主菜单(登录)界面资源映射（工作室可上传替换） ============================
def _main_menu_assets_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "main_menu_assets.json")


def _main_menu_assets_dir():
    return os.path.join(discover_project_root(), "assets", "ui", "main_menu")


_DEFAULT_MAIN_MENU_ASSETS = {
    "title_logo": "res://assets/ui/main_menu/title_logo.png",
    "btn_hover_bg": "res://assets/ui/main_menu/btn_hover_bg.png",
    "icons": [
        "res://assets/ui/main_menu/icon_1.png",
        "res://assets/ui/main_menu/icon_2.png",
        "res://assets/ui/main_menu/icon_3.png",
        "res://assets/ui/main_menu/icon_4.png",
        "res://assets/ui/main_menu/icon_5.png",
    ],
}


def main_menu_assets_get():
    """读取主菜单资源映射（与默认合并，缺字段补默认）。"""
    p = _main_menu_assets_path()
    data = dict(_DEFAULT_MAIN_MENU_ASSETS)
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                parsed = json.load(f)
            if isinstance(parsed, dict):
                for k in ("title_logo", "btn_hover_bg"):
                    if k in parsed and parsed[k]:
                        data[k] = str(parsed[k])
                if isinstance(parsed.get("icons"), list):
                    data["icons"] = [str(x) for x in parsed["icons"]]
        except Exception:
            pass
    # 补齐图标数量到 5 个
    while len(data["icons"]) < 5:
        data["icons"].append(_DEFAULT_MAIN_MENU_ASSETS["icons"][len(data["icons"]) % 5])
    return data


def main_menu_assets_update(paths):
    """更新主菜单资源映射中的路径（不移动文件，仅改 JSON）。paths 为 dict。"""
    p = _main_menu_assets_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    data = main_menu_assets_get()
    for k in ("title_logo", "btn_hover_bg"):
        if k in paths and paths[k]:
            data[k] = str(paths[k])
    if "icons" in paths and isinstance(paths["icons"], list):
        data["icons"] = [str(x) for x in paths["icons"]]
    data["_doc"] = "主菜单（登录界面）资源路径映射。标题 Logo、按钮悬停墨迹底板、5 个菜单图标都在这里配置。工作室「登录界面 → 主菜单资源替换」可上传新图替换；游戏启动时 MainMenu.gd 会读取本配置。"
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    log_event("main_menu_assets", p, "更新主菜单资源映射")
    return True, "已保存主菜单资源映射"


def _main_menu_asset_key_to_field(key):
    """把上传 key 映射到 JSON 字段。"""
    if key in ("title_logo", "btn_hover_bg"):
        return key
    if key.startswith("icon_"):
        idx = int(key.split("_")[1]) - 1
        if 0 <= idx < 5:
            return ("icons", idx)
    return None


def _main_menu_asset_disk_path(key):
    """根据 key 返回资源在磁盘上的真实路径（用于工作室预览）。"""
    cfg = main_menu_assets_get()
    field = _main_menu_asset_key_to_field(key)
    if field is None:
        return ""
    if isinstance(field, tuple):
        res = cfg.get("icons", [])[field[1]] if field[1] < len(cfg.get("icons", [])) else ""
    else:
        res = cfg.get(field, "")
    if not res or not res.startswith("res://"):
        return ""
    rel = res[len("res://"):]
    return os.path.join(discover_project_root(), rel.replace("/", os.sep))


def main_menu_asset_replace(key, src_path):
    """上传并替换单张主菜单资源图。key 可为 title_logo/btn_hover_bg/icon_1~5。"""
    field = _main_menu_asset_key_to_field(key)
    if field is None:
        return False, "未知资源 key：%s" % key
    if not os.path.exists(src_path):
        return False, "上传文件不存在"

    # 校验图片格式并写入正确扩展名
    ext = _detect_image_ext(src_path)
    if not ext:
        return False, "无法识别图片格式（请上传 png/jpg/webp）"
    try:
        w, h = _image_size(src_path)
    except Exception as e:
        return False, "无法解析图片尺寸：%s" % e

    d = _main_menu_assets_dir()
    os.makedirs(d, exist_ok=True)
    _backup_dir(d)

    if isinstance(field, tuple):
        fname = "icon_%d.%s" % (field[1] + 1, ext)
        cfg_field = "icons"
        cfg_idx = field[1]
    else:
        fname_map = {"title_logo": "title_logo", "btn_hover_bg": "btn_hover_bg"}
        fname = "%s.%s" % (fname_map[field], ext)
        cfg_field = field
        cfg_idx = None

    dst = os.path.join(d, fname)
    # 若旧文件存在且扩展名不同，备份后清理，避免残留同名不同扩展名
    for old_ext in (".png", ".jpg", ".jpeg", ".webp"):
        old = dst.rsplit(".", 1)[0] + old_ext
        if old != dst and os.path.exists(old):
            _backup(old)
            try:
                os.remove(old)
            except Exception:
                pass

    shutil.copyfile(src_path, dst)

    # 更新 JSON 映射
    cfg = main_menu_assets_get()
    res_path = "res://assets/ui/main_menu/%s" % fname
    if cfg_idx is not None:
        cfg["icons"][cfg_idx] = res_path
    else:
        cfg[cfg_field] = res_path
    main_menu_assets_update(cfg)

    # 触发 Godot 导入：删掉同文件名的 .import，让 Godot 下次启动重建
    import_file = dst + ".import"
    if os.path.exists(import_file):
        try:
            os.remove(import_file)
        except Exception:
            pass

    log_event("main_menu_asset_replace", dst, "替换主菜单资源 %s（%s，%dx%d）" % (key, ext, w, h))
    return True, "已替换 %s（%s，%dx%d），下次进主菜单生效" % (key, ext, w, h)


def main_menu_asset_clear_icon(idx):
    """将某个图标恢复为默认路径（不删文件）。"""
    if not (1 <= idx <= 5):
        return False, "图标编号必须在 1~5 之间"
    cfg = main_menu_assets_get()
    cfg["icons"][idx - 1] = _DEFAULT_MAIN_MENU_ASSETS["icons"][idx - 1]
    main_menu_assets_update(cfg)
    log_event("main_menu_asset_clear", "icon_%d" % idx, "恢复图标默认路径")
    return True, "已恢复 icon_%d 为默认路径" % idx


# ============================ 战棋布局（工作室可视化编辑器） ============================
# 布局文件存于 data/configs/battles/grids/<id>.json，Schema 与 combat_service._build_grid 完全兼容：
#   width/height(int) · obstacles(['x,y']) · heights(['x,y,h']) · deployment({unit:[x,y]})
# 扩展字段：view_mode('iso'|'ortho') · background('res://...'|'') · name(显示名)
# 地形三态映射：可走=不在 obstacles/heights；障碍=在 obstacles；高地=在 heights(h>0)
def _battle_layout_dir():
    return os.path.join(discover_project_root(), "data", "configs", "battles", "grids")


def _battle_bg_dir():
    return os.path.join(discover_project_root(), "assets", "battle_bg")


def _detect_existing_bg(layout_id):
    """若磁盘上已存在该布局的底图文件，返回其 res:// 路径；否则返回空字符串。"""
    d = _battle_bg_dir()
    for ext in (".png", ".jpg", ".webp"):
        fp = os.path.join(d, layout_id + ext)
        if os.path.exists(fp):
            return "res://assets/battle_bg/%s%s" % (layout_id, ext)
    return ""


def battle_layout_list():
    """列出所有战棋布局（id / 尺寸 / 视图模式）。"""
    d = _battle_layout_dir()
    out = []
    if not os.path.isdir(d):
        return out
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".json"):
            continue
        if fn.startswith("_"):
            continue
        lid = fn[:-5]
        data = load_json(os.path.join(d, fn), {})
        out.append({
            "id": lid,
            "name": data.get("name", lid),
            "width": int(data.get("width", 0)),
            "height": int(data.get("height", 0)),
            "view_mode": data.get("view_mode", "iso"),
            "has_bg": bool(data.get("background", "")),
        })
    return out


def battle_layout_get(layout_id):
    """读取单个布局全量（含地形/部署）。不存在返回空 dict。"""
    lid = _safe_id(layout_id)
    if not lid:
        return {}
    p = os.path.join(_battle_layout_dir(), lid + ".json")
    if not os.path.exists(p):
        return {}
    return load_json(p, {})


def battle_layout_save(layout_id, data):
    """写入布局（自动备份旧文件 + 字段归一化）。data 形如完整布局 dict。"""
    lid = _safe_id(layout_id)
    if not lid:
        return False, "布局 id 非法"
    p = os.path.join(_battle_layout_dir(), lid + ".json")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    # 归一化
    norm = {}
    norm["name"] = str(data.get("name", lid))
    norm["view_mode"] = "ortho" if str(data.get("view_mode", "iso")) == "ortho" else "iso"
    norm["width"] = max(2, int(data.get("width", 10)))
    norm["height"] = max(2, int(data.get("height", 8)))
    # 底图路径：优先用传入的 background；若未传但磁盘上已有该布局的底图文件，则保留（防"保存布局"覆盖丢图）
    _bg_in = str(data.get("background", "")).strip()
    if _bg_in == "":
        _bg_in = _detect_existing_bg(lid)
    norm["background"] = _bg_in
    # 棋盘平移（pan_x/pan_y，像素偏移，默认 0）与缩放（zoom，>0，默认 1.0）
    # 编辑器可拖动画布空白区平移、滑块缩放，游戏侧把 grid_node 的 position/scale 套用。
    norm["pan_x"] = int(round(float(data.get("pan_x", 0) or 0)))
    norm["pan_y"] = int(round(float(data.get("pan_y", 0) or 0)))
    norm["zoom"] = max(0.2, min(4.0, float(data.get("zoom", 1.0) or 1.0)))
    # 棋盘旋转（rotation，度，默认 0；保留浮点精度以支持任意精确角度输入，
    # 不再取整/不再归一到 0-360，确保编辑器里用户输入的任意小数角度原样落盘）
    norm["rotation"] = float(data.get("rotation", 0) or 0)
    # 场景底图是否跟随棋盘旋转（bg_rotate，布尔，默认 False = 底图不转，只棋盘转）
    _br = data.get("bg_rotate", False)
    norm["bg_rotate"] = str(_br).lower() not in ("false", "0", "", "none")
    # obstacles: 'x,y' 字符串数组；裁剪到界内
    obs = []
    for o in (data.get("obstacles", []) or []):
        parts = str(o).split(",")
        if len(parts) >= 2:
            x, y = int(parts[0]), int(parts[1])
            if 0 <= x < norm["width"] and 0 <= y < norm["height"]:
                obs.append("%d,%d" % (x, y))
    norm["obstacles"] = obs
    # heights: 'x,y,h' 字符串数组；h>0
    hs = []
    for h in (data.get("heights", []) or []):
        parts = str(h).split(",")
        if len(parts) >= 3:
            x, y, hh = int(parts[0]), int(parts[1]), int(parts[2])
            if 0 <= x < norm["width"] and 0 <= y < norm["height"] and hh > 0:
                hs.append("%d,%d,%d" % (x, y, hh))
    norm["heights"] = hs
    # deployment: unit_id -> [x,y]
    dep = {}
    for uid, pos in (data.get("deployment", {}) or {}).items():
        if isinstance(pos, (list, tuple)) and len(pos) >= 2:
            x, y = int(pos[0]), int(pos[1])
            if 0 <= x < norm["width"] and 0 <= y < norm["height"]:
                dep[str(uid)] = [x, y]
    norm["deployment"] = dep
    with open(p, "w", encoding="utf-8") as f:
        json.dump(norm, f, ensure_ascii=False, indent=2)
    log_event("battle_layout", lid, "保存战棋布局 %dx%d (%s)" % (norm["width"], norm["height"], norm["view_mode"]))
    return True, "已保存战棋布局「%s」" % norm["name"]


def battle_layout_delete(layout_id):
    """删除布局文件（进回收站保险，不直接销毁）。"""
    lid = _safe_id(layout_id)
    if not lid:
        return False, "布局 id 非法"
    p = os.path.join(_battle_layout_dir(), lid + ".json")
    if not os.path.exists(p):
        return False, "布局不存在"
    _backup(p)
    # 同时清关联底图
    bg_dir = _battle_bg_dir()
    for ext in (".png", ".jpg", ".webp"):
        bp = os.path.join(bg_dir, lid + ext)
        if os.path.exists(bp):
            try:
                os.remove(bp)
            except Exception:
                pass
    os.remove(p)
    log_event("battle_layout", lid, "删除战棋布局（已备份）")
    return True, "已删除战棋布局「%s」（备份在回收站）" % lid


def battle_layout_preset(size):
    """生成 N×N 空预设布局（size 取 6/8/10/12）。返回 (ok, msg, data)。"""
    s = max(2, min(40, int(size)))
    lid = "preset_%dx%d" % (s, s)
    data = {
        "name": "预设 %dx%d" % (s, s),
        "view_mode": "iso",
        "background": "",
        "width": s,
        "height": s,
        "obstacles": [],
        "heights": [],
        "deployment": {},
    }
    return battle_layout_save(lid, data)


# ---- 战棋底图 ----
def _battle_bg_dir():
    return os.path.join(discover_project_root(), "assets", "battle_bg")


def _battle_bg_path_for(layout_id):
    """返回该布局当前底图绝对路径（按扩展名探测）。无图返回 ''。"""
    lid = _safe_id(layout_id)
    if not lid:
        return ""
    d = _battle_bg_dir()
    for ext in (".png", ".jpg", ".webp"):
        fp = os.path.join(d, lid + ext)
        if os.path.exists(fp):
            return fp
    return ""


def battle_bg_upload(layout_id, payload):
    """上传战棋底图：按文件头判真实格式存对扩展名；更新布局 background 字段；清旧 import 缓存。"""
    lid = _safe_id(layout_id)
    if not lid:
        return False, "布局 id 非法"
    import base64
    raw = base64.b64decode(payload.get("data", b"") or b"")
    if not raw:
        return False, "空图片数据"
    # 先落临时文件判真实格式
    d = _battle_bg_dir()
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, "_tmp_bg_%s.bin" % lid)
    with open(tmp, "wb") as f:
        f.write(raw)
    ext = _detect_image_ext(tmp)
    if ext is None:
        try:
            os.remove(tmp)
        except Exception:
            pass
        return False, "无法识别的图片格式（仅支持 png/jpg/webp）"
    # 清旧图（含旧扩展名 + 旧 .import 缓存，避免 Godot 仍用旧图）
    for old_ext in (".png", ".jpg", ".webp"):
        old_fp = os.path.join(d, lid + old_ext)
        if os.path.exists(old_fp):
            old_import = old_fp + ".import"
            if os.path.exists(old_import):
                _purge_import_cache_for(old_import)
                try:
                    os.remove(old_import)
                except Exception:
                    pass
            try:
                os.remove(old_fp)
            except Exception:
                pass
    dst = os.path.join(d, lid + "." + ext)
    shutil.move(tmp, dst)
    # 更新布局 background 字段
    p = os.path.join(_battle_layout_dir(), lid + ".json")
    data = load_json(p, {}) if os.path.exists(p) else {"name": lid, "width": 10, "height": 8,
                                                        "obstacles": [], "heights": [], "deployment": {}}
    data["background"] = "res://assets/battle_bg/%s.%s" % (lid, ext)
    if "view_mode" not in data:
        data["view_mode"] = "iso"
    if "width" not in data:
        data["width"] = 10
    if "height" not in data:
        data["height"] = 8
    battle_layout_save(lid, data)
    log_event("battle_bg", lid, "上传战棋底图 %s" % dst)
    return True, "已上传战棋底图（%s）" % ext


def battle_bg_clear(layout_id):
    """清除战棋底图：删文件 + .import + 缓存，并把布局 background 字段置空。"""
    lid = _safe_id(layout_id)
    if not lid:
        return False, "布局 id 非法"
    d = _battle_bg_dir()
    for ext in (".png", ".jpg", ".webp"):
        fp = os.path.join(d, lid + ext)
        if os.path.exists(fp):
            import_fp = fp + ".import"
            if os.path.exists(import_fp):
                _purge_import_cache_for(import_fp)
                try:
                    os.remove(import_fp)
                except Exception:
                    pass
            try:
                os.remove(fp)
            except Exception:
                pass
    p = os.path.join(_battle_layout_dir(), lid + ".json")
    if os.path.exists(p):
        data = load_json(p, {})
        data["background"] = ""
        battle_layout_save(lid, data)
    return True, "已清除战棋底图"


# ---- 战棋演示立绘临时调换（工作室后台测试用）----
# 用户要在工作室里临时换「教头演示战棋」出场角色的立绘做测试：
#   - 敌人 bandit_001 的战斗头像：resources/icons/enemies/bandit_001.png（走 IconRegistry.get_icon("enemies/bandit_001")）
#   - 教头 tactical_demo_master 的半身立绘：assets/characters/half_body/tactical_demo_master.png（NPC.half_body_portrait）
#   - 主角 matte 的半身立绘：assets/characters/half_body/player.png（玩家立绘固定解析到 player.png；resolve_half_body(is_player)）
# kind 白名单，避免任意路径写入。
_DEMO_PORTRAIT_TARGETS = {
    "enemy_bandit_001": ("resources", "icons", "enemies", "bandit_001"),
    "npc_tactical_demo_master": ("assets", "characters", "half_body", "tactical_demo_master"),
    "protagonist_matte": ("assets", "characters", "half_body", "player"),
}


def demo_portrait_list():
    """列出可测试的演示立绘目标及其当前是否有图。"""
    root = discover_project_root()
    out = []
    for kind, parts in _DEMO_PORTRAIT_TARGETS.items():
        base = os.path.join(root, *parts)
        cur = ""
        for ext in ("png", "jpg", "webp"):
            if os.path.exists(base + "." + ext):
                cur = "res://" + "/".join(parts) + "." + ext
                break
        out.append({
            "kind": kind,
            "label": "敌人 bandit_001 战斗头像" if kind == "enemy_bandit_001"
                     else "教头 tactical_demo_master 半身立绘" if kind == "npc_tactical_demo_master"
                     else "主角 matte 半身立绘",
            "current": cur,
        })
    return out


def _demo_portrait_path_for(kind):
    if kind not in _DEMO_PORTRAIT_TARGETS:
        return None
    return os.path.join(discover_project_root(), *_DEMO_PORTRAIT_TARGETS[kind])


def demo_portrait_file(kind):
    """返回该 kind 当前立绘绝对路径（按扩展名探测），无图返回 ''。"""
    base = _demo_portrait_path_for(kind)
    if base is None:
        return ""
    for ext in ("png", "jpg", "webp"):
        fp = base + "." + ext
        if os.path.exists(fp):
            return fp
    return ""


def demo_portrait_upload(kind, payload):
    """上传/替换某演示立绘：按文件头判真实格式存对扩展名 + 清旧图与 .import/imported 缓存。"""
    if kind not in _DEMO_PORTRAIT_TARGETS:
        return False, "立绘目标非法"
    import base64
    raw = base64.b64decode(payload.get("data", b"") or b"")
    if not raw:
        return False, "空图片数据"
    base = _demo_portrait_path_for(kind)
    d = os.path.dirname(base)
    os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d, "_tmp_demo_pt_%s.bin" % kind)
    with open(tmp, "wb") as f:
        f.write(raw)
    ext = _detect_image_ext(tmp)
    if ext is None:
        try:
            os.remove(tmp)
        except Exception:
            pass
        return False, "无法识别的图片格式（仅支持 png/jpg/webp）"
    # 清旧图（含旧扩展名 + 旧 .import + 缓存）
    for old_ext in ("png", "jpg", "webp"):
        old_fp = base + "." + old_ext
        if os.path.exists(old_fp):
            _backup(old_fp)
            import_fp = old_fp + ".import"
            if os.path.exists(import_fp):
                _purge_import_cache_for(import_fp)
                try:
                    os.remove(import_fp)
                except OSError:
                    pass
            try:
                os.remove(old_fp)
            except OSError:
                pass
    dst = base + "." + ext
    shutil.move(tmp, dst)
    log_event("demo_portrait", kind, "临时替换演示立绘 %s" % dst)
    return True, "已替换演示立绘（%s）" % ext


def demo_portrait_reset(kind):
    """清除临时立绘，恢复为无图（交由游戏侧缺图占位/默认逻辑）。"""
    if kind not in _DEMO_PORTRAIT_TARGETS:
        return False, "立绘目标非法"
    base = _demo_portrait_path_for(kind)
    for ext in ("png", "jpg", "webp"):
        fp = base + "." + ext
        if os.path.exists(fp):
            _backup(fp)
            import_fp = fp + ".import"
            if os.path.exists(import_fp):
                _purge_import_cache_for(import_fp)
                try:
                    os.remove(import_fp)
                except OSError:
                    pass
            try:
                os.remove(fp)
            except OSError:
                pass
    log_event("demo_portrait", kind, "清除临时演示立绘")
    return True, "已清除临时立绘，恢复默认"


def _purge_import_cache_for(import_fp):
    """读取 .import 的 dest_files，删除 .godot/imported/ 下对应的缓存纹理与 md5。"""
    try:
        import configparser
        cp = configparser.ConfigParser()
        cp.read(import_fp, encoding="utf-8")
        deps = cp.get("remap", "dest_files", fallback="")
        if not deps:
            return
        paths = json.loads(deps)
        root = discover_project_root()
        for p in paths:
            if not isinstance(p, str) or not p.startswith("res://"):
                continue
            cache_fp = os.path.join(root, p.replace("res://", "").replace("/", os.sep))
            for target in (cache_fp, cache_fp + ".md5"):
                if os.path.exists(target):
                    try:
                        os.remove(target)
                    except OSError:
                        pass
    except Exception:
        pass


# === 各按钮背景图「存空/清除」（Task #42） ===
def login_btn_bg_clear(btn_id):
    """把某按钮背景图清空为 null：删映射表项 + 删图片文件 + 删 .import + 删 .godot/imported 缓存，彻底回退默认。"""
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
    # 图片可能是 png/jpg/webp 任一真实格式，逐个清掉同名残留
    for ext in ("png", "jpg", "webp"):
        fp = os.path.join(d, "%s.%s" % (btn_id, ext))
        if os.path.exists(fp):
            _backup(fp)
            try:
                os.remove(fp)
            except OSError:
                pass
        # 同时删除 Godot 导入配置及已生成的导入缓存，否则编辑器/运行时仍可能使用旧纹理
        import_fp = fp + ".import"
        if os.path.exists(import_fp):
            try:
                _purge_import_cache_for(import_fp)
                os.remove(import_fp)
            except OSError:
                pass
    log_event("login_btn_bg_clear", btn_id, "清除按钮背景图（含 .import 与导入缓存）")
    return True, "已清除 %s 的按钮背景图（回退默认）" % btn_id


def login_btn_bg_scan_fix():
    """体检：扫描所有按钮背景图，找出「文件内容真实格式 ≠ 文件扩展名」的错配并自动改名修复。

    背景：Godot 按扩展名选解码器。JPEG 数据存成 .png 会导致导入失败（生成不出 .ctex），
    游戏侧 ResourceLoader.exists() 判定为假，按钮背景**静默消失**且不报错，极难排查。
    本函数按文件头重新定扩展名，同步更新映射表，救回图片且不丢数据。
    """
    d = _login_btn_bg_dir()
    cfg = _login_btn_bg_cfg()
    data = {}
    if os.path.exists(cfg):
        try:
            data = json.load(open(cfg, "r", encoding="utf-8"))
        except Exception:
            data = {}
    mp = data.get("map", {})
    if not isinstance(mp, dict):
        mp = {}
    fixed, clean = [], []
    for btn_id, rel in list(mp.items()):
        if not rel:
            continue
        disk = os.path.join(discover_project_root(), rel.replace("res://", "").replace("/", os.sep))
        if not os.path.exists(disk):
            continue
        real = _detect_image_ext(disk)
        if real is None:
            # 既不是 png/jpg/webp —— Godot 无论如何都读不了，只能提示用户换图
            fixed.append({"btn_id": btn_id, "action": "unsupported", "detail": os.path.basename(disk)})
            continue
        cur = os.path.splitext(disk)[1].lstrip(".").lower()
        if cur == real:
            clean.append(btn_id)
            continue
        new_disk = "%s.%s" % (os.path.splitext(disk)[0], real)
        try:
            _backup(disk)
            shutil.move(disk, new_disk)
            # 清掉可能残留的 .import（指向旧扩展名，留着会让 Godot 认错文件）
            stale_import = disk + ".import"
            if os.path.exists(stale_import):
                try:
                    os.remove(stale_import)
                except OSError:
                    pass
            mp[btn_id] = "res://assets/ui/main_menu_btn/%s" % os.path.basename(new_disk)
            fixed.append({"btn_id": btn_id, "action": "renamed",
                          "detail": "%s → %s" % (os.path.basename(disk), os.path.basename(new_disk))})
        except Exception as e:
            fixed.append({"btn_id": btn_id, "action": "failed", "detail": str(e)})
    data["map"] = mp
    if os.path.exists(cfg) or mp:
        os.makedirs(os.path.dirname(cfg), exist_ok=True)
        _backup(cfg)
        data["_doc"] = ("登录主菜单各按钮背景图映射。游戏代码已读取此表（MainMenu._load_btn_bg_map → "
                        "MenuItem.set_background），上传图片后下次进主菜单即生效。扩展名由工具按文件头真实格式写入，勿手改。")
        with open(cfg, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    for it in fixed:
        if it["action"] == "renamed":
            log_event("btn_bg_fix", it["btn_id"], "修复扩展名错配：%s" % it["detail"])
    n_bad = len([x for x in fixed if x["action"] in ("renamed", "unsupported")])
    if n_bad == 0:
        return True, "体检完成：所有按钮背景图的扩展名都与真实格式一致，无需修复。"
    return True, "体检完成：修复 %d 处错配（%s）。Godot 需要重新导入一次才会生效。" % (
        n_bad, "；".join("%s %s" % (x["btn_id"], x["detail"]) for x in fixed if x["action"] != "failed"))


def login_btn_bg_file(btn_id):
    """返回该按钮背景图的真实磁盘路径（按映射表里的真实扩展名），不存在返回 None。"""
    cfg = _login_btn_bg_cfg()
    data = {}
    if os.path.exists(cfg):
        try:
            data = json.load(open(cfg, "r", encoding="utf-8")).get("map", {})
        except Exception:
            data = {}
    rel = data.get(btn_id, "")
    if not rel:
        return None
    p = os.path.join(discover_project_root(), rel.replace("res://", "").replace("/", os.sep))
    return p if os.path.exists(p) else None


# ============================ 登录背景多分辨率变体（任务 #47） ============================
# 思路：准备 1080p / 2K / 4K 三档图，游戏按当前视口宽度自动挑最合适的一档。
# 好处：4K 屏不吃 1080p 图的放大模糊；1080p 屏也不必白扛一张 4K 图的内存。
def _bg_variants_cfg_path():
    return os.path.join(discover_project_root(), "data", "configs", "ui", "login_bg_variants.json")


def _bg_variant_base():
    return os.path.join(discover_project_root(), "assets", "ui", "main_menu_bg")


def _load_variants():
    p = _bg_variants_cfg_path()
    if not os.path.exists(p):
        return {"variants": []}
    try:
        d = json.load(open(p, "r", encoding="utf-8"))
        if isinstance(d, dict) and isinstance(d.get("variants"), list):
            return d
    except Exception:
        pass
    return {"variants": []}


def _save_variants(d):
    p = _bg_variants_cfg_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    _backup(p)
    d["_doc"] = ("登录背景多分辨率变体。游戏按视口宽度挑选 min_width 最大且不超过视口宽的那一档；"
                 "配置缺失或文件不存在时回退主图 main_menu_bg.png，零破坏。由工作室「登录界面→清晰度」面板维护。")
    with open(p, "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)


def login_bg_variants():
    """返回主图清晰度诊断 + 已配置的变体列表。"""
    base_path = _login_bg_path()
    info = clarity_report(base_path) if os.path.exists(base_path) else {"exists": False, "width": 0, "height": 0, "targets": []}
    out = []
    for v in _load_variants().get("variants", []):
        rel = v.get("path", "")
        disk = os.path.join(discover_project_root(), rel.replace("res://", "").replace("/", os.sep))
        w, h = _image_size(disk) if os.path.exists(disk) else (0, 0)
        out.append({"min_width": v.get("min_width", 0), "path": rel,
                    "exists": os.path.exists(disk), "width": w, "height": h,
                    "size": os.path.getsize(disk) if os.path.exists(disk) else 0})
    out.sort(key=lambda x: x["min_width"])
    return {"base": info, "base_path": ("res://assets/ui/%s" % os.path.basename(base_path)) if info.get("exists") else "",
            "variants": out}


def login_bg_variant_set(src_path, tag, min_width):
    """上传一档变体：存成 assets/ui/main_menu_bg_<tag>.<真实格式>，并写入变体表。"""
    ext = _detect_image_ext(src_path)
    if ext is None:
        return False, "无法识别的图片格式（Godot 只支持 PNG / JPG / WEBP）。请转成 PNG 再上传。"
    tag = re.sub(r"[^0-9A-Za-z_\-]", "", str(tag or "").strip())
    if not tag:
        return False, "档位名不能为空（例如 1080p / 2k / 4k）"
    try:
        min_width = int(min_width)
    except Exception:
        return False, "生效宽度必须是数字（例如 1080p 填 0，2K 填 1921，4K 填 3000）"
    if min_width < 0:
        return False, "生效宽度不能为负"
    dst = "%s_%s.%s" % (_bg_variant_base(), tag, ext)
    _backup(dst)
    shutil.copy2(src_path, dst)
    w, h = _image_size(dst)
    d = _load_variants()
    rel = "res://assets/ui/main_menu_bg_%s.%s" % (tag, ext)
    hit = None
    for v in d["variants"]:
        if v.get("min_width") == min_width:
            hit = v
            break
    if hit is None:
        d["variants"].append({"min_width": min_width, "path": rel})
        hit = d["variants"][-1]
    else:
        hit["path"] = rel
    d["variants"].sort(key=lambda x: x.get("min_width", 0))
    _save_variants(d)
    log_event("bg_variant", tag, "设置登录背景变体 min_width=%d（%dx%d）" % (min_width, w, h))
    return True, "已保存 %s 档（视口宽 ≥ %d 时启用，%dx%d）" % (tag, min_width, w, h)


def login_bg_variant_remove(min_width):
    """删除一档变体（文件进回收站，配置项移除）。"""
    try:
        min_width = int(min_width)
    except Exception:
        return False, "档位标识无效"
    d = _load_variants()
    hit = None
    for v in d["variants"]:
        if v.get("min_width") == min_width:
            hit = v
            break
    if hit is None:
        return False, "没有这一档"
    disk = os.path.join(discover_project_root(), hit["path"].replace("res://", "").replace("/", os.sep))
    if os.path.exists(disk):
        _backup(disk)
        try:
            os.remove(disk)
        except OSError:
            pass
    d["variants"] = [v for v in d["variants"] if v.get("min_width") != min_width]
    _save_variants(d)
    log_event("bg_variant_remove", str(min_width), "删除登录背景变体")
    return True, "已删除该档变体（游戏回退到主图）"


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

# -*- coding: utf-8 -*-


# ============================ UI 界面贴图（.tscn 直写） ============================
# 与用户「UI 底层改为直接绑 .tscn、位置交给 Godot 拖拽」的改造对齐：
#   * 本模块**只读写贴图**，绝不动任何 anchor / offset / size / layout 属性。
#     位置、尺寸、层级一律由用户在 Godot 编辑器里拖拽调整。
#   * 贴图以 ext_resource 形式直接写进 .tscn，不再经过任何 JSON 中间层。
#   * 新图不预生成 .import（交给 Godot 打开工程时自动导入，避免残缺 .import
#     导致 Godot 跳过导入而加载失败）。
# 典型流程：工作室选界面 → 传图 → 回 Godot 编辑器拖拽摆位置。

try:
    if MODULE_DIR not in sys.path:
        sys.path.insert(0, MODULE_DIR)
    import tscn_assets as tscn
except Exception as e:  # pragma: no cover
    tscn = None
    _TSCN_IMPORT_ERR = str(e)


def _tscn_backup_dir():
    d = os.path.join(BACKUP_DIR, "tscn")
    try:
        os.makedirs(d, exist_ok=True)
    except Exception:
        pass
    return d


def _tscn_ready():
    if tscn is None:
        return False, "贴图库加载失败：%s" % globals().get("_TSCN_IMPORT_ERR", "未知原因")
    return True, ""


def ui_screens_list():
    """扫描工程内所有 UI 场景及其贴图槽位。返回 (ok, msg, screens)。"""
    ok, m = _tscn_ready()
    if not ok:
        return False, m, []
    root = discover_project_root()
    try:
        screens = tscn.scan_ui_screens(root)
    except Exception as e:
        return False, "扫描场景失败：%s" % e, []
    # 附加槽位预览信息（前端按 key 请求图片）
    for s in screens:
        for sl in s["slots"]:
            sl["key"] = "%s|%s|%s" % (s["screen"], sl["node"], sl["prop"])
    return True, "共 %d 个界面" % len(screens), screens


def _slot_to_fname(node_path):
    """节点路径 -> 安全文件名片段（不含 / 与 .）。"""
    if node_path in (".", ""):
        return "root"
    return node_path.replace("/", "_").replace(".", "_")


def ui_slot_upload(screen_rel, node_path, prop, src_path):
    """上传贴图并写进 .tscn 的指定槽位。返回 (ok, msg)。

    screen_rel: scenes/ui/.../Xxx.tscn（相对工程根）
    node_path : 节点完整路径，如 "TitleGroup/title_logo" 或 "."（根）
    prop      : 贴图属性，如 texture / icon / texture_normal
    """
    ok, m = _tscn_ready()
    if not ok:
        return False, m
    if not tscn._safe_rel(screen_rel):
        return False, "非法场景路径"
    if not os.path.exists(src_path):
        return False, "上传文件不存在"

    root = discover_project_root()
    ext = _detect_image_ext(src_path)
    if not ext:
        return False, "无法识别图片格式（请上传 png / jpg / webp）"
    try:
        w, h = _image_size(src_path)
    except Exception as e:
        return False, "无法解析图片尺寸：%s" % e

    screen_id = os.path.splitext(os.path.basename(screen_rel))[0]
    slot = _slot_to_fname(node_path)
    try:
        rel, dst = tscn.save_texture(root, screen_id, slot, src_path, ext)
    except Exception as e:
        return False, "保存图片失败：%s" % e

    # 清掉可能残留的旧 .import，确保 Godot 重新导入（扩展名变化时尤其重要）
    try:
        d = os.path.dirname(dst)
        stem = os.path.splitext(os.path.basename(dst))[0]
        for fn in os.listdir(d):
            if fn.startswith(stem + ".") and fn.endswith(".import"):
                os.remove(os.path.join(d, fn))
    except Exception:
        pass

    ok2, msg2 = tscn.set_slot_texture(root, screen_rel, node_path, rel, prop,
                                      backup_root=_tscn_backup_dir())
    if not ok2:
        return False, msg2
    log_event("ui_slot_upload", "%s::%s.%s" % (screen_rel, node_path, prop),
              "上传贴图 %s（%s %dx%d）" % (rel, ext, w, h))
    return True, "已替换 %s.%s（%s %dx%d）。回 Godot 编辑器即可看到，位置可拖拽调整" % (
        node_path, prop, ext, w, h)


def ui_slot_clear(screen_rel, node_path, prop):
    """清除槽位贴图（只删属性引用，不删磁盘图片）。"""
    ok, m = _tscn_ready()
    if not ok:
        return False, m
    if not tscn._safe_rel(screen_rel):
        return False, "非法场景路径"
    root = discover_project_root()
    ok2, msg2 = tscn.clear_slot_texture(root, screen_rel, node_path, prop,
                                        backup_root=_tscn_backup_dir())
    if ok2:
        log_event("ui_slot_clear", "%s::%s.%s" % (screen_rel, node_path, prop), "清除贴图引用")
    return ok2, msg2


def ui_bg_add(screen_rel):
    """给界面新增一张全屏背景图槽位（空槽，随后上传图片）。"""
    ok, m = _tscn_ready()
    if not ok:
        return False, m
    if not tscn._safe_rel(screen_rel):
        return False, "非法场景路径"
    root = discover_project_root()
    ok2, msg2 = tscn.add_background_slot(root, screen_rel, backup_root=_tscn_backup_dir())
    if ok2:
        log_event("ui_bg_add", screen_rel, "新增背景图槽位 StudioBg")
        return True, "已新增背景图槽位，选它上传图片后回 Godot 拖拽调整"
    return False, msg2


def ui_slot_disk_path(screen_rel, node_path, prop):
    """取槽位当前贴图在磁盘上的绝对路径（供预览）；无贴图返回空串。"""
    ok, _m = _tscn_ready()
    if not ok or not tscn._safe_rel(screen_rel):
        return ""
    root = discover_project_root()
    full = os.path.join(root, screen_rel.replace("/", os.sep))
    if not os.path.exists(full):
        return ""
    try:
        info = tscn.scan_slots(full, root)
    except Exception:
        return ""
    for sl in info.get("slots", []):
        if sl["node"] == node_path and sl["prop"] == prop and sl["texture"]:
            res = sl["texture"]
            if not res.startswith("res://"):
                return ""
            return os.path.join(root, res[len("res://"):].replace("/", os.sep))
    return ""


def ui_slot_file(key):
    """按 key（screen|node|prop）定位贴图文件，返回磁盘路径；找不到返回 ('', errmsg)。"""
    if not key or key.count("|") < 2:
        return "", "缺少参数"
    screen_rel, node_path, prop = key.split("|", 2)
    if not tscn or not tscn._safe_rel(screen_rel):
        return "", "非法参数"
    p = ui_slot_disk_path(screen_rel, node_path, prop)
    if not p or not os.path.exists(p):
        return "", "该槽位暂无贴图"
    return p, ""


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
