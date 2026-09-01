# -*- coding: utf-8 -*-
"""
UI 场景（.tscn）贴图槽位扫描与写入库 —— 纯标准库实现（可随 PyInstaller 打包）。

设计原则（与「位置由 Godot 拖拽控制」的新架构对齐）：
  * 本库**只读/写贴图**，绝不触碰任何 anchor / offset / size / layout 属性。
    位置、尺寸、层级全都交给用户在 Godot 编辑器里拖拽。
  * 贴图以 ext_resource 形式直接写进 .tscn，不再经过任何 JSON 中间层，
    与用户「UI 底层改为直接绑 .tscn」的改造保持一致。
  * 自动生成配套 .import（含合法 uid 与 ctex 路径），Godot 打开工程即可直接识别。

安全：所有外部传入的 id / 路径必须过 _safe_id 白名单；写 .tscn 前自动备份。
"""
import hashlib
import os
import random
import re
import shutil
import time

# ---------------------------------------------------------------- 常量

#: 可承载贴图的节点类型 -> 该类型支持的贴图属性（按优先级排序，第一个为主贴图槽）
TEX_NODE_TYPES = {
    "TextureRect": ["texture"],
    "TextureButton": ["texture_normal", "texture_pressed", "texture_hover",
                      "texture_disabled", "texture_focused"],
    "TextureProgressBar": ["texture_progress", "texture_under", "texture_over"],
    "Sprite2D": ["texture"],
    "Sprite3D": ["texture"],
    "AnimatedSprite2D": ["sprite_frames"],
    "AnimatedSprite3D": ["sprite_frames"],
    "NinePatchRect": ["texture"],
    "Button": ["icon"],
    "Panel": [],
}

#: SpriteFrames 资源也算贴图资源（AnimatedSprite2D 用）
TEXTURE_RES_TYPES = ("Texture2D", "CompressedTexture2D", "ImageTexture",
                     "AtlasTexture", "SpriteFrames", "GradientTexture2D")

_UID_ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789"
_SAFE_ID_RE = re.compile(r"^[A-Za-z0-9_\-]{1,64}$")
_SAFE_REL_RE = re.compile(r"^[A-Za-z0-9_\-./]{1,256}$")
#: 节点路径：允许 / 与 .（根节点写作 "."），其余同 id 白名单
_SAFE_NODE_RE = re.compile(r"^[A-Za-z0-9_\-./]{0,256}$")


def _safe_id(v):
    """白名单校验：只允许字母数字下划线短横线。防路径穿越。"""
    return bool(_SAFE_ID_RE.match(v or ""))


def _safe_rel(v):
    """校验 res:// 相对路径（可含 / - _），不含 .. 与空格。"""
    if not v or ".." in v or "\\" in v or " " in v:
        return False
    return bool(_SAFE_REL_RE.match(v))


def gen_uid():
    """生成 Godot 风格的 uid：uid:// + 13 位 [a-z0-9]。"""
    return "uid://" + "".join(random.choice(_UID_ALPHABET) for _ in range(13))


def ctex_name(res_path):
    """.godot/imported 下的 ctex 文件名：<basename>-<md5(res://relpath)>.ctex"""
    return "%s-%s.ctex" % (os.path.basename(res_path),
                           hashlib.md5(res_path.encode("utf-8")).hexdigest())


# ---------------------------------------------------------------- .tscn 解析

_EXT_RE = re.compile(r'^\[ext_resource\s+type="([^"]+)"(?:\s+uid="([^"]*)")?\s+path="([^"]+)"\s+id="([^"]+)"\s*\]\s*$')
_NODE_RE = re.compile(r'^\[node\s+name="([^"]+)"(?:\s+type="([^"]+)")?(?:\s+parent="([^"]*)")?')
_SUB_RE = re.compile(r'^\[sub_resource\s+type="([^"]+)"\s+id="([^"]+)"\s*\]\s*$')
_GDSCENE_RE = re.compile(r'^\[gd_scene\b')


class Node(object):
    __slots__ = ("name", "type", "parent", "path", "line", "props", "end", "is_instance")

    def __init__(self, name, ntype, parent, line):
        self.name = name
        self.type = ntype or ""
        self.parent = parent or ""
        self.path = ""
        self.line = line          # [node ...] 所在行号
        self.end = -1             # 块结束行号（不含）
        self.props = {}           # 属性名 -> (值, 行号)；行号=-1 表示尚不存在
        self.is_instance = False  # instance=ExtResource(...) 实例化的子场景

    @property
    def slot_props(self):
        return TEX_NODE_TYPES.get(self.type, [])


def parse_tscn(path):
    """解析 .tscn，返回 dict：
       {"lines": [...], "ext": [{type,uid,path,id,line}], "nodes": [Node], "gd_scene_line": int}
    """
    with open(path, "r", encoding="utf-8") as f:
        lines = f.read().split("\n")

    ext = []
    nodes = []
    subs = []
    gd_line = 0
    cur = None          # 当前 node 块
    path_of = {}        # 相对路径 -> 完整节点路径

    for i, raw in enumerate(lines):
        if _GDSCENE_RE.match(raw):
            gd_line = i
            cur = None
            continue

        m = _EXT_RE.match(raw)
        if m:
            cur = None
            ext.append({"type": m.group(1), "uid": m.group(2) or "",
                        "path": m.group(3), "id": m.group(4), "line": i})
            continue

        m = _SUB_RE.match(raw)
        if m:
            cur = None
            subs.append({"type": m.group(1), "id": m.group(2), "line": i})
            continue

        m = _NODE_RE.match(raw)
        if m:
            if cur is not None:
                cur.end = i
            name = m.group(1)
            ntype = m.group(2) or ""
            parent = m.group(3) if m.group(3) is not None else ""
            n = Node(name, ntype, parent, i)
            # 计算完整路径
            if parent == "":
                n.path = "."
            elif parent == ".":
                n.path = name
            else:
                base = path_of.get(parent, parent)
                n.path = name if base == "." else base + "/" + name
            path_of[parent + "/" + name if parent else name] = n.path
            nodes.append(n)
            cur = n
            continue

        # 块内属性行
        if cur is not None:
            s = raw.strip()
            if s.startswith("[") or s == "":
                cur.end = i
                cur = None
                continue
            if "=" in s:
                k, _, v = s.partition("=")
                k = k.strip()
                if k and k not in cur.props:
                    cur.props[k] = (v.strip(), i)
                    if k == "instance":
                        cur.is_instance = True

    if cur is not None:
        cur.end = len(lines)

    return {"lines": lines, "ext": ext, "nodes": nodes, "subs": subs,
            "gd_scene_line": gd_line}


def _ext_by_path(parsed, res_path):
    for e in parsed["ext"]:
        if e["path"] == res_path:
            return e
    return None


# ---------------------------------------------------------------- 扫描

def scan_slots(tscn_path, project_root):
    """扫描单个 .tscn 的贴图槽位。返回：
       {"screen": 相对路径, "uid": 场景uid, "slots": [{node, path, type, prop, texture, has_texture}]}
    """
    if not os.path.exists(tscn_path):
        return None
    parsed = parse_tscn(tscn_path)
    rel = os.path.relpath(tscn_path, project_root).replace("\\", "/")

    uid = ""
    m = re.search(r'uid="(uid://[^"]+)"', parsed["lines"][parsed["gd_scene_line"]]
                  if parsed["gd_scene_line"] < len(parsed["lines"]) else "")
    if m:
        uid = m.group(1)

    # 建立 ext id -> path 映射
    extmap = {e["id"]: e for e in parsed["ext"]}

    slots = []
    for n in parsed["nodes"]:
        for prop in n.slot_props:
            val, _ln = n.props.get(prop, ("", -1))
            tex = ""
            if val.startswith("ExtResource("):
                eid = val[val.find('"') + 1: val.rfind('"')]
                e = extmap.get(eid)
                if e:
                    tex = e["path"]
            slots.append({
                "node": n.path,
                "name": n.name,
                "type": n.type,
                "prop": prop,
                "texture": tex,
                "has_texture": bool(tex),
            })
    return {"screen": rel, "uid": uid, "slots": slots,
            "node_count": len(parsed["nodes"])}


def scan_ui_screens(project_root, subdir="scenes/ui"):
    """扫描工程下所有 UI 场景。返回界面清单（含槽位）。"""
    base = os.path.join(project_root, subdir.replace("/", os.sep))
    out = []
    if not os.path.isdir(base):
        return out
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in sorted(filenames):
            if not fn.endswith(".tscn"):
                continue
            full = os.path.join(dirpath, fn)
            info = scan_slots(full, project_root)
            if info is None:
                continue
            info["id"] = os.path.splitext(fn)[0]
            info["title"] = _screen_title(info["id"])
            out.append(info)
    out.sort(key=lambda x: x["screen"])
    return out


_TITLE_MAP = {
    "MainMenu": "主菜单", "LoadingScreen": "预加载", "SaveLoadScreen": "存档读档",
    "DifficultySelect": "难度选择", "SettingsScreen": "设置", "EscMenu": "暂停菜单",
    "GameMenuScreen": "游戏主菜单", "InventoryScreen": "背包", "EquipmentScreen": "装备",
    "AbilitiesScreen": "武学", "SkillSlot": "技能槽", "ItemSlot": "物品槽",
    "ForgeScreen": "锻造", "AlchemyScreen": "炼丹", "ShopScreen": "商店",
    "SectScreen": "门派", "NpcPanelScreen": "NPC 面板", "MapScreen": "地图",
    "AttributesScreen": "属性", "BondRomanceScreen": "结缘", "DialogOverlay": "对话",
    "CelebrationOverlay": "欢庆", "Hud": "HUD", "QuestTrackPanel": "任务追踪",
    "SkillBarPanel": "技能栏", "StatusCardPanel": "状态卡", "TopRightMenuPanel": "右上菜单",
    "StatusBar": "状态条", "Tooltip": "提示框", "ConfirmDialog": "确认框",
    "SaveCard": "存档卡片", "SaveNameDialog": "存档命名", "MenuItem": "菜单项",
    "WuxiaMenuButton": "武侠按钮", "UIPreview": "UI 预览",
}


def _screen_title(sid):
    return _TITLE_MAP.get(sid, sid)


# ---------------------------------------------------------------- 写入

def _backup(path, backup_root):
    """把文件备份到 backup_root，返回备份路径。"""
    try:
        os.makedirs(backup_root, exist_ok=True)
        name = os.path.basename(path)
        stamp = time.strftime("%Y%m%d_%H%M%S")
        dst = os.path.join(backup_root, "%s.%s.bak" % (name, stamp))
        shutil.copyfile(path, dst)
        return dst
    except Exception:
        return ""


def write_import(project_root, rel_res_path, ext):
    """为新贴图生成合法的 .import（含 uid 与 ctex 路径）。
    rel_res_path 形如 assets/ui/main_menu/xxx.png（不含 res://）。
    """
    res = "res://" + rel_res_path.replace("\\", "/")
    imp_path = os.path.join(project_root, rel_res_path.replace("/", os.sep) + ".import")
    os.makedirs(os.path.dirname(imp_path), exist_ok=True)
    ctex = ctex_name(res)
    txt = (
        '[remap]\n\n'
        'importer="texture"\n'
        'type="CompressedTexture2D"\n'
        'uid="%s"\n'
        'path="res://.godot/imported/%s"\n'
        'metadata={\n'
        '"vram_texture": false\n'
        '}\n\n'
        '[deps]\n\n'
        'source_file="%s"\n'
        'dest_files=["res://.godot/imported/%s"]\n\n'
        '[params]\n\n'
        'compress/mode=0\n'
        'compress/high_quality=false\n'
        'compress/lossy_quality=0.7\n'
        'compress/uastc_level=0\n'
        'compress/rdo_quality_loss=0.0\n'
        'compress/hdr_compression=1\n'
        'compress/normal_map=0\n'
        'compress/channel_pack=0\n'
        'mipmaps/generate=false\n'
        'mipmaps/limit=-1\n'
        'roughness/mode=0\n'
        'roughness/src_normal=""\n'
        'process/channel_remap/red=0\n'
        'process/channel_remap/green=1\n'
        'process/channel_remap/blue=2\n'
        'process/channel_remap/alpha=3\n'
        'process/fix_alpha_border=true\n'
        'process/premult_alpha=false\n'
        'process/normal_map_invert_y=false\n'
        'process/hdr_as_srgb=false\n'
        'process/hdr_clamp_exposure=false\n'
        'process/size_limit=0\n'
        'detect_3d/compress_to=1\n'
    ) % (ext_uid_of(project_root, rel_res_path, ext), ctex, res, ctex)
    with open(imp_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(txt)
    return imp_path


def ext_uid_of(project_root, rel_res_path, ext):
    """取（或生成并记住）该贴图的 uid：优先复用已存在 .import 里的 uid。"""
    imp = os.path.join(project_root, rel_res_path.replace("/", os.sep) + ".import")
    if os.path.exists(imp):
        try:
            with open(imp, "r", encoding="utf-8") as f:
                m = re.search(r'uid="(uid://[^"]+)"', f.read())
            if m:
                return m.group(1)
        except Exception:
            pass
    return gen_uid()


def save_texture(project_root, screen_id, slot_name, src_path, ext):
    """把上传的图片存到 assets/ui/<screen_id>/ 下，返回 (rel_res_path, abs_path)。"""
    if not _safe_id(screen_id) or not _safe_id(slot_name):
        raise ValueError("非法 screen/slot 标识")
    d = os.path.join(project_root, "assets", "ui", screen_id)
    os.makedirs(d, exist_ok=True)
    fname = "%s_%s.%s" % (screen_id.lower(), slot_name.lower(), ext)
    dst = os.path.join(d, fname)
    shutil.copyfile(src_path, dst)
    rel = "assets/ui/%s/%s" % (screen_id, fname)
    return rel, dst


def set_slot_texture(project_root, screen_rel, node_path, rel_res_path,
                     prop="texture", backup_root=None):
    """把某个槽位的贴图写进 .tscn（只改贴图属性，绝不动位置属性）。

    screen_rel: scenes/ui/xxx/yyy.tscn（相对工程根）
    node_path:  节点完整路径，如 "TitleGroup/title_logo" 或 "."（根）
    rel_res_path: assets/ui/.../x.png
    返回 (ok: bool, msg: str)
    """
    if not _safe_rel(screen_rel) or not _safe_rel(rel_res_path):
        return False, "非法路径"
    if not _SAFE_NODE_RE.match(node_path or ""):
        return False, "非法节点路径"
    tscn = os.path.join(project_root, screen_rel.replace("/", os.sep))
    if not os.path.exists(tscn):
        return False, "场景文件不存在：%s" % screen_rel

    if backup_root:
        _backup(tscn, backup_root)

    parsed = parse_tscn(tscn)
    lines = parsed["lines"]
    res = "res://" + rel_res_path.replace("\\", "/")

    # 1) 确保 ext_resource 存在（按 path 去重）
    exist = _ext_by_path(parsed, res)
    if exist:
        eid = exist["id"]
    else:
        eid = _new_ext_id(parsed, rel_res_path)
        # 刻意不写 uid：新贴图的 uid 尚未进 Godot 的 UID 缓存，写了会触发
        # "ext_resource, invalid UID ... using text path instead" 警告。
        # 只写 path 时 Godot 按路径解析并在首次保存场景时自动补 uid，零警告。
        decl = '[ext_resource type="Texture2D" path="%s" id="%s"]' % (res, eid)
        lines = _insert_ext(lines, parsed, decl)
        parsed = parse_tscn_lines(lines)

    # 2) 定位节点块并写 texture 属性
    parsed = parse_tscn_lines(lines)
    target = None
    for n in parsed["nodes"]:
        if n.path == node_path:
            target = n
            break
    if target is None:
        return False, "场景内找不到节点：%s" % node_path

    if prop not in target.slot_props:
        return False, "节点 %s（%s）不支持贴图属性 %s" % (node_path, target.type, prop)

    val = 'ExtResource("%s")' % eid
    if prop in target.props:
        _ln = target.props[prop][1]
        lines[_ln] = "%s = %s" % (prop, val)
    else:
        # 插到该节点块的属性区末尾（块结束前）
        ins = target.end if target.end > 0 else len(lines)
        # 回退跳过块尾空行
        while ins > target.line + 1 and lines[ins - 1].strip() == "":
            ins -= 1
        lines.insert(ins, "%s = %s" % (prop, val))

    with open(tscn, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return True, "已写入 %s.%s = %s" % (node_path, prop, res)


def parse_tscn_lines(lines):
    """parse_tscn 的变体：直接吃行列表（避免反复读盘）。"""
    tmp = "\n".join(lines)
    import io
    parsed = {"lines": lines, "ext": [], "nodes": [], "subs": [], "gd_scene_line": 0}
    cur = None
    path_of = {}
    for i, raw in enumerate(lines):
        if _GDSCENE_RE.match(raw):
            parsed["gd_scene_line"] = i
            cur = None
            continue
        m = _EXT_RE.match(raw)
        if m:
            cur = None
            parsed["ext"].append({"type": m.group(1), "uid": m.group(2) or "",
                                  "path": m.group(3), "id": m.group(4), "line": i})
            continue
        m = _SUB_RE.match(raw)
        if m:
            cur = None
            parsed["subs"].append({"type": m.group(1), "id": m.group(2), "line": i})
            continue
        m = _NODE_RE.match(raw)
        if m:
            if cur is not None:
                cur.end = i
            name, ntype = m.group(1), m.group(2) or ""
            parent = m.group(3) if m.group(3) is not None else ""
            n = Node(name, ntype, parent, i)
            if parent == "":
                n.path = "."
            elif parent == ".":
                n.path = name
            else:
                base = path_of.get(parent, parent)
                n.path = name if base == "." else base + "/" + name
            path_of[parent + "/" + name if parent else name] = n.path
            parsed["nodes"].append(n)
            cur = n
            continue
        if cur is not None:
            s = raw.strip()
            if s.startswith("[") or s == "":
                cur.end = i
                cur = None
                continue
            if "=" in s:
                k, _, v = s.partition("=")
                k = k.strip()
                if k and k not in cur.props:
                    cur.props[k] = (v.strip(), i)
                    if k == "instance":
                        cur.is_instance = True
    if cur is not None:
        cur.end = len(lines)
    return parsed


def _new_ext_id(parsed, rel_res_path):
    """生成一个不与现有冲突的 ext_resource id。"""
    base = os.path.splitext(os.path.basename(rel_res_path))[0]
    base = re.sub(r"[^A-Za-z0-9_]", "_", base)
    used = {e["id"] for e in parsed["ext"]}
    used |= {s["id"] for s in parsed["subs"]}
    cand = base
    i = 1
    while cand in used:
        i += 1
        cand = "%s_%d" % (base, i)
    return cand


def _insert_ext(lines, parsed, decl):
    """把 ext_resource 声明插到最后一个 ext_resource 之后（无则插到 gd_scene 之后）。"""
    if parsed["ext"]:
        pos = parsed["ext"][-1]["line"] + 1
    else:
        pos = parsed["gd_scene_line"] + 1
        # gd_scene 后通常有一个空行
        if pos < len(lines) and lines[pos].strip() == "":
            pos += 1
    lines.insert(pos, decl)
    return lines


# ---------------------------------------------------------------- 新增背景图槽位

def add_background_slot(project_root, screen_rel, backup_root=None):
    """给界面新增一个全屏背景图 TextureRect（插在根节点下最前，位于最底层）。
    不设 texture，只搭好空槽位 —— 用户随后在工作室上传图，再回 Godot 拖拽微调。
    返回 (ok, msg_or_node_path)
    """
    if not _safe_rel(screen_rel):
        return False, "非法路径"
    tscn = os.path.join(project_root, screen_rel.replace("/", os.sep))
    if not os.path.exists(tscn):
        return False, "场景文件不存在"

    parsed = parse_tscn(tscn)
    # 已存在则直接返回
    for n in parsed["nodes"]:
        if n.name == "StudioBg" and n.parent == ".":
            return True, n.path

    if backup_root:
        _backup(tscn, backup_root)

    lines = parsed["lines"]
    # 找到根节点块（path == "."）
    root = None
    for n in parsed["nodes"]:
        if n.path == ".":
            root = n
            break
    if root is None:
        return False, "场景没有根节点"

    # 新节点块：全屏 anchor + 忽略鼠标 + 不拉伸（保留原图比例由用户调）
    block = [
        '',
        '[node name="StudioBg" type="TextureRect" parent="."]',
        'layout_mode = 1',
        'anchors_preset = 15',
        'anchor_right = 1.0',
        'anchor_bottom = 1.0',
        'grow_horizontal = 2',
        'grow_vertical = 2',
        'mouse_filter = 2',
        'expand_mode = 1',
        'stretch_mode = 5',
    ]
    # 插到根节点块属性结束处（即根节点下一块之前）
    ins = root.end if root.end > 0 else len(lines)
    lines[ins:ins] = block
    with open(tscn, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return True, "StudioBg"


def clear_slot_texture(project_root, screen_rel, node_path, prop, backup_root=None):
    """清除某槽位的贴图（删掉该属性行；若其 ext_resource 不再被引用也一并移除）。"""
    if not _safe_rel(screen_rel):
        return False, "非法路径"
    if not _SAFE_NODE_RE.match(node_path or ""):
        return False, "非法节点路径"
    tscn = os.path.join(project_root, screen_rel.replace("/", os.sep))
    if not os.path.exists(tscn):
        return False, "场景文件不存在"
    parsed = parse_tscn(tscn)
    lines = parsed["lines"]

    target = None
    for n in parsed["nodes"]:
        if n.path == node_path:
            target = n
            break
    if target is None or prop not in target.props:
        return False, "该槽位没有贴图"

    if backup_root:
        _backup(tscn, backup_root)

    val, ln = target.props[prop]
    eid = ""
    if val.startswith("ExtResource("):
        eid = val[val.find('"') + 1: val.rfind('"')]
    del lines[ln]

    # 若该 ext_resource 不再被任何地方引用，移除其声明
    if eid:
        still = False
        for l in lines:
            if l.strip().startswith(";"):
                continue
            if 'ExtResource("%s")' % eid in l:
                still = True
                break
        if not still:
            for e in parsed["ext"]:
                if e["id"] == eid:
                    # 删除声明行（注意行号会因前面删除而偏移）
                    idx = e["line"] - (1 if e["line"] > ln else 0)
                    if 0 <= idx < len(lines) and lines[idx].startswith("[ext_resource"):
                        del lines[idx]
                        # 顺带删掉其后紧跟的空行（保持格式整洁）
                        if idx < len(lines) and lines[idx].strip() == "":
                            del lines[idx]
                    break

    with open(tscn, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return True, "已清除 %s.%s" % (node_path, prop)
