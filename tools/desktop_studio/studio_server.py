#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
武侠游戏「内容工作室」桌面版 —— 本地 Web 服务（仅标准库）。
启动后浏览器打开 http://127.0.0.1:端口/ 即可使用，全程零代码改 NPC / 剧情 / 欢庆数据，
并带保险模式（删除进回收站 + 写前自动备份 + 操作日志 + 过期自动清空）。

启动方式：
  - 双击 studio_launcher.bat
  - 或：python studio_server.py

【开发约束铁律·任何 AI 改本文件前必读】
  - 启动入口(__main__)已加 try/except 兜底：启动期异常会打印真实 traceback 并停留，
    禁止再制造"闪一下黑窗口没信息"的体验。
  - 必须保证 `import studio_core` 及所有模块 import 不报错，否则用户双击 bat 闪退。
  - 端口自动顺延(8765→8785)，勿把端口写死或改成需用户手填的常量（本就是本地 Web 服务，
    对外零端口配置；若将来重做成纯桌面应用应彻底去掉 http.server）。
  - 改完请 kill 自己起的测试服务进程，并跑一次启动验证（见 MEMORY.md「开发完必须释放」）。
"""

import os
import sys
import json
import webbrowser
import datetime
import base64
import urllib.parse
import re
import subprocess
import glob
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import studio_core as core

MODULE_DIR = os.path.dirname(os.path.abspath(__file__))

_MIME = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp"}

# 防 CSRF：仅放行本机来源。恶意网页（如浏览器里开着 http://evil.com/x）无法再向 127.0.0.1 接口发指令。
# 放行规则：无 Origin/Referer（curl / 非浏览器）✓；工具自身页面（127.0.0.1:端口）✓；file:// 或 null（本地双击打开的静态页）✓。
_ALLOWED_ORIGIN_PREFIXES = (
    "http://127.0.0.1", "http://localhost",
    "file://", "null",
)


def _origin_allowed(handler):
    origin = handler.headers.get("Origin") or handler.headers.get("Referer") or ""
    if not origin:
        return True
    for ok in _ALLOWED_ORIGIN_PREFIXES:
        if origin.startswith(ok):
            return True
    return False


def _mime_of(path):
    return _MIME.get(os.path.splitext(path)[1].lstrip(".").lower(), "application/octet-stream")


def _send_json(handler, obj, code=200):
    body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_body(handler):
    length = int(handler.headers.get("Content-Length", 0) or 0)
    if length == 0:
        return {}
    raw = handler.rfile.read(length)
    try:
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return {}


def _godot_exe():
    """定位 Godot 可执行文件：优先 settings.godot_path，否则从托管二进制目录候选。"""
    try:
        s = core.load_settings()
        p = (s.get("godot_path") or "").strip()
        if p and os.path.exists(p):
            return p
    except Exception:
        pass
    base = r"C:/Users/Administrator/.workbuddy/binaries/godot"
    for c in ("Godot_v4.7.2-stable_win64_console.exe", "Godot_v4.3-stable_win64_console.exe"):
        fp = os.path.join(base, c)
        if os.path.exists(fp):
            return fp
    return None


def _run_gate():
    """平台化双闸门：调起 Godot headless 跑 GATE1 + GATE2，解析绿/红。只读验证，不改工程。"""
    import subprocess
    import re
    exe = _godot_exe()
    if not exe:
        return {"ok": False, "error": "未找到 Godot 可执行文件（请在设置里配置 godot_path，或确认托管二进制目录存在）"}
    root = core.discover_project_root()
    if not root:
        return {"ok": False, "error": "未找到工程根目录"}
    # GATE1：headless --quit 零 SCRIPT/PARSE/COMPILE ERROR
    try:
        out1 = subprocess.run([exe, "--headless", "--path", root, "--quit"],
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=120).stdout
    except Exception as e:
        return {"ok": False, "error": "GATE1 执行失败: %s" % e}
    g1_errs = [l for l in out1.splitlines()
               if any(k in l for k in ("SCRIPT ERROR", "Parse Error", "Compile Error"))]
    gate1 = {"ran": True, "errors": len(g1_errs), "green": len(g1_errs) == 0, "sample": g1_errs[:10]}
    # GATE2：run_all.tscn 零 ✗ / 失败 0
    try:
        out2 = subprocess.run([exe, "--headless", "--path", root, "res://tests/unit/run_all.tscn"],
                              capture_output=True, text=True, encoding="utf-8",
                              errors="replace", timeout=300).stdout
    except Exception as e:
        return {"ok": False, "error": "GATE2 执行失败: %s" % e}
    suites = failed = xfail = 0
    for l in out2.splitlines():
        if "套件：" in l and "通过" in l:
            m = re.search(r"通过\s+(\d+)\s*·\s*失败\s+(\d+)", l)
            if m:
                suites, failed = int(m.group(1)), int(m.group(2))
        xfail += l.count("✗")
    gate2 = {"ran": True, "suites": suites, "failed": failed, "xfail": xfail,
             "green": (failed == 0 and xfail == 0)}
    return {"ok": True, "godot": exe, "gate1": gate1, "gate2": gate2,
            "green": gate1["green"] and gate2["green"]}


def _orc_match(task):
    """任务驱动知识路由（L3 总控核心）：按任务词匹配经验库分面，返回识别的模块/角色/相关经验。

    解决「知识鲸鱼」——不把全库塞给 AI，只注入与任务相关的 E 级经验。
    复用 _exp_enrich 的 facets（角色/模块/BUG 分面 + 每篇 tags）。
    """
    import re
    from project_loader import get_connector_info
    root = core.discover_project_root()
    kn = _exp_enrich(get_connector_info("wuxia_game").get("knowledge", {}), root)
    q = (task or "").lower()
    # 任务细粒度分词：英文/数字词 + 中文 bi-gram（兼容整词与子串，解决中文整串不匹配）
    en = re.findall(r"[a-z0-9_]+", q)
    han = re.sub(r"[a-z0-9_]+", " ", q)
    grams = set(en)
    for i in range(len(han) - 1):
        g = han[i:i+2].strip()
        if g:
            grams.add(g)
    related = []
    m_roles, m_mods, m_bugs = set(), set(), set()
    for r in kn.get("refs", []):
        if r.get("group") == "notice":
            continue
        hay = " ".join([r.get("title", "")] + r.get("tags", []) + r.get("roles", [])
                        + r.get("modules", []) + r.get("bugs", [])).lower()
        if any(g and g in hay for g in grams):
            related.append(r)
            m_roles.update(r.get("roles", []))
            m_mods.update(r.get("modules", []))
            m_bugs.update(r.get("bugs", []))
    if not related:  # 任务词太泛/无命中，回退全部核心知识（避免空结果）
        related = [r for r in kn.get("refs", []) if r.get("group") != "notice"]
    return {"task": task,
            "matched_roles": sorted(m_roles),
            "matched_modules": sorted(m_mods),
            "matched_bugs": sorted(m_bugs),
            "related": related,
            "facets": kn.get("facets", {})}


# ── 经验库增强检索：服务端实时富化 knowledge.refs ──────────────────────────────
# 解析每篇子文档的「检索关键词」行 → 标签云；扫描正文（标题+前 4000 字）→ 角色/模块/BUG 分面。
# 词表集中维护、与文档解耦：新文档只要含这些词即自动归入对应分面，零 schema 改动、零文档改动。
_EXP_ROLE_KW = {
    "架构": ["架构", "分层", "单向依赖", "依赖注入", "服务实例", "门面", "装配中枢", "分层铁律", "跨模块通信"],
    "程序": ["事务化", "资产守恒", "inventorytransaction", "combatcore", "combatservice", "逻辑内核", "try_consume", "单一真源", "发号器"],
    "前端": ["mouse_filter", "吞点击", "屏幕栈", "前端", "hbox", "vbox", "control节点", "信号接缝", "接缝"],
    "美工": ["纹理压缩", "立绘", "图标", "换皮", "reskin", "美术", "背景图"],
    "运维": ["门禁", "双闸门", "headless", "run_all", "pre-commit", "连接器", "部署", "打包", "studio", "工作室平台", "安全自检"],
    "PM": ["多ai", "协同", "sop", "派单", "changelog", "待办", "治理", "规划", "复盘"],
    "迭代": ["回归", "可复用", "模式", "优化", "扩展", "迭代"],
}
_EXP_MOD_KW = {
    "战斗": ["战斗", "回合制", "战棋", "atb", "网格", "combatcore", "tacticalbattlescene"],
    "经济": ["经济", "背包", "商店", "锻造", "炼药", "资产守恒"],
    "结缘": ["结缘", "好感", "姻缘", "配偶", "结义", "师徒", "关系网"],
    "UI": ["mouse_filter", "屏幕栈", "ui皮肤"],
    "存档": ["读档", "写档", "存档", "脏档", "savemanager"],
    "纹理": ["纹理压缩", "纹理"],
    "信号": ["eventbus", "信号接缝", "notify", "cmd", "接缝"],
    "装配": ["gamemanager", "装配", "场景切换"],
    "门禁": ["门禁", "双闸门"],
    "平台": ["工作室平台", "studio", "连接器"],
    "多AI": ["多ai", "协同", "派单"],
    "数据": ["数值配置", "data/configs", "配置表"],
}


def _exp_derive_facets(scan_text):
    """从一段文本派生 (roles, modules)。BUG 号在调用处从全文单独提取（显式无歧义）。"""
    low = scan_text.lower()
    roles = set()
    for role, kws in _EXP_ROLE_KW.items():
        if any(kw.lower() in low for kw in kws):
            roles.add(role)
    mods = set()
    for mod, kws in _EXP_MOD_KW.items():
        if any(kw.lower() in low for kw in kws):
            mods.add(mod)
    return sorted(roles), sorted(mods)


def _exp_enrich(knowledge, root):
    """把 manifest 的 knowledge 段富化为可检索结构。

    返回：refs(带 tags/roles/modules/bugs) + patterns/mistakes(同结构) + facets(全局分面与标签云)。
    向后兼容：仍保留原始 reusable_patterns / predecessor_mistakes 字符串列表。
    """
    refs_raw = knowledge.get("refs") or []
    refs = []
    facets = {"roles": set(), "modules": set(), "bugs": set(), "tags": {}, "grades": set()}

    def _bump(t):
        t = t.strip()
        if t:
            facets["tags"][t] = facets["tags"].get(t, 0) + 1

    for entry in refs_raw:
        if isinstance(entry, dict):
            p = (entry.get("path") or "")
            extra_tags = entry.get("tags") or []
        else:
            p = entry
            extra_tags = []
        # 支持 glob（如 docs/变更通告_*.md）
        paths = []
        if "*" in p and root:
            paths = sorted(glob.glob(os.path.join(root, p)))
        else:
            paths = [p]
        for rel in paths:
            if not rel:
                continue
            title = os.path.basename(rel).replace(".md", "").replace(".txt", "") or rel
            grp = "notice" if "变更通告" in rel else "core"
            tags = list(extra_tags)
            roles = mods = bugs = []
            if root and (rel.endswith(".md") or rel.endswith(".txt")):
                target = os.path.realpath(os.path.join(root, rel))
                root_real = os.path.realpath(root)
                if (target == root_real or target.startswith(root_real + os.sep)) and os.path.exists(target):
                    try:
                        with open(target, "r", encoding="utf-8") as f:
                            body = f.read()
                        kw_line = ""
                        grade = ""
                        for ln in body.splitlines():
                            if "检索关键词" in ln:
                                kw_line = ln.split("检索关键词", 1)[1].lstrip("：:").strip()
                            elif "等级" in ln:
                                mg = re.findall(r"E[1-4]", ln)
                                if mg:
                                    grade = ",".join(sorted(set(mg)))
                        # 不 break：兼容位于「检索关键词」之后的「等级」行（文档体量小，全扫 header 即可）
                        for tk in re.split(r"[、,，\s]+", kw_line):
                            if tk:
                                tags.append(tk)
                        # 角色/模块：优先用 curated「检索关键词」行（权威意图）；无则回退正文前 4000 字
                        scan = (title + "\n" + kw_line) if kw_line else (title + "\n" + body[:4000])
                        roles, mods = _exp_derive_facets(scan)
                        # BUG 号：全文显式提取（无歧义）
                        bugs = sorted(set(re.findall(r"BUG-\d+", body, re.IGNORECASE)), key=str.lower)
                    except Exception:
                        pass
            # 变更通告数量大，仅作为可检索条目；标签云/分面只统计核心知识，避免污染默认视图
            if grp == "core":
                for t in tags:
                    _bump(t)
                for r in roles:
                    facets["roles"].add(r)
                for m in mods:
                    facets["modules"].add(m)
                for b in bugs:
                    facets["bugs"].add(b)
                for g in grade.split(","):
                    if g:
                        facets["grades"].add(g)
            # 归一化为相对工程根的路径（正向斜杠），保证 /api/experience/doc 能正确解析（含 glob 展开出的绝对路径）
            rpath = rel
            if root and os.path.isabs(rel):
                try:
                    rpath = os.path.relpath(rel, root).replace("\\", "/")
                except Exception:
                    pass
            refs.append({"path": rpath, "title": title, "group": grp, "tags": tags,
                         "roles": roles, "modules": mods, "bugs": bugs, "grade": grade})

    patterns = []
    for t in knowledge.get("reusable_patterns") or []:
        roles, mods = _exp_derive_facets(t)
        bugs = sorted(set(re.findall(r"BUG-\d+", t, re.IGNORECASE)), key=str.lower)
        for r in roles:
            facets["roles"].add(r)
        for m in mods:
            facets["modules"].add(m)
        for b in bugs:
            facets["bugs"].add(b)
        patterns.append({"text": t, "roles": roles, "modules": mods, "bugs": bugs})
    mistakes = []
    for t in knowledge.get("predecessor_mistakes") or []:
        roles, mods = _exp_derive_facets(t)
        bugs = sorted(set(re.findall(r"BUG-\d+", t, re.IGNORECASE)), key=str.lower)
        for r in roles:
            facets["roles"].add(r)
        for m in mods:
            facets["modules"].add(m)
        for b in bugs:
            facets["bugs"].add(b)
        mistakes.append({"text": t, "roles": roles, "modules": mods, "bugs": bugs})

    out = dict(knowledge)
    out["refs"] = refs
    out["patterns"] = patterns
    out["mistakes"] = mistakes
    out["facets"] = {
        "roles": sorted(facets["roles"]),
        "modules": sorted(facets["modules"]),
        "bugs": sorted(facets["bugs"], key=str.lower),
        "grades": sorted(facets["grades"]),
        "tags": sorted(facets["tags"].items(), key=lambda kv: (-kv[1], kv[0])),
    }
    return out


def _handoff_view():
    """读取派单权威快照 handoff_view.json（由 tools/handoff.py export 生成，事件重放合成）。"""
    try:
        root = core.discover_project_root()
        if not root:
            return {"ok": False, "error": "未找到工程根目录"}
        p = os.path.join(root, ".workbuddy", "handovers", "handoff_view.json")
        if not os.path.exists(p):
            return {"ok": False, "missing": True,
                    "hint": "请先运行 python tools/handoff.py export 生成派单快照"}
        with open(p, encoding="utf-8") as f:
            data = json.load(f)
        data["ok"] = True
        return data
    except Exception as e:
        return {"ok": False, "error": str(e)}


def _handoff_cmd(*args):
    """调用 tools/handoff.py 子命令（claim/done/close/export），返回 (ok, out)。"""
    try:
        root = core.discover_project_root()
        if not root:
            return False, "未找到工程根目录"
        hp = os.path.join(root, "tools", "handoff.py")
        if not os.path.exists(hp):
            return False, "handoff.py 不存在"
        r = subprocess.run([sys.executable, hp, *args],
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", cwd=root, timeout=60)
        return (r.returncode == 0), (r.stdout + r.stderr).strip()
    except Exception as e:
        return False, str(e)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _serve_file(self, name, ctype):
        fp = os.path.join(MODULE_DIR, name)
        if not os.path.exists(fp):
            _send_json(self, {"error": "file missing"}, 404)
            return
        with open(fp, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not _origin_allowed(self):
            return _send_json(self, {"error": "forbidden origin"}, 403)
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self._serve_file("index.html", "text/html; charset=utf-8")
            return
        if path.startswith("/js/") and path.endswith(".js"):
            # 静态 JS（第三阶段拆分）：白名单式校验——仅允许 js/ 下单层 .js 文件名，防目录穿越
            name = path[len("/js/"):]
            if re.fullmatch(r"[A-Za-z0-9_\-]+\.js", name) and os.path.exists(os.path.join(MODULE_DIR, "js", name)):
                self._serve_file(os.path.join("js", name), "application/javascript; charset=utf-8")
            else:
                _send_json(self, {"error": "file missing"}, 404)
            return
        parts = [p for p in path.strip("/").split("/") if p]
        if path == "/api/settings":
            return _send_json(self, core.load_settings())
        if path == "/api/project_root":
            return _send_json(self, {"root": core.discover_project_root()})
        if path == "/api/tool_version":
            # 用 exe 文件修改时间 + md5 前8位作为"构建版本"，帮助用户分辨是否最新版
            return _send_json(self, core.tool_version())
        # ---- 登录界面修改插件 ----
        if path == "/api/login/bg":
            return _send_json(self, core.login_bg_info())
        if path == "/api/login/bg/file":
            fp = core._login_bg_path()
            if os.path.exists(fp):
                with open(fp, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", _mime_of(fp))
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            _send_json(self, {"error": "no bg"}, 404)
            return
        if path == "/api/login/btn_bg/file":
            # 按映射表里的真实扩展名回图（扩展名由工具按文件头写入，可能是 png/jpg/webp）
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else "")
            btn_id = (qs.get("btn_id") or [""])[0]
            fp = core.login_btn_bg_file(btn_id)
            if fp:
                with open(fp, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", _mime_of(fp))
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            _send_json(self, {"error": "no btn bg"}, 404)
            return
        if path == "/api/login/bg_variants":
            return _send_json(self, core.login_bg_variants())
        if path == "/api/login/texts":
            return _send_json(self, core.login_texts())
        if path == "/api/login/version":
            return _send_json(self, core.login_version())
        if path == "/api/login/btn_bg":
            return _send_json(self, core.login_btn_bg_list())
        if path == "/api/login/bg_layout":
            return _send_json(self, core.login_bg_layout())
        if path == "/api/loading/layout":
            return _send_json(self, core.loading_layout_get())
        if path == "/api/main_menu/layout":
            return _send_json(self, core.main_menu_layout_get())
        if path == "/api/ui_screens":
            ok, m, screens = core.ui_screens_list()
            return _send_json(self, {"ok": ok, "msg": m, "screens": screens})
        if path == "/api/ui_slot/file":
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else "")
            key = (qs.get("key") or [""])[0]
            fp, err = core.ui_slot_file(key) if key else ("", "缺少参数")
            if fp and os.path.exists(fp):
                with open(fp, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", _mime_of(fp))
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            _send_json(self, {"error": err or "no asset"}, 404)
            return
        if path == "/api/main_menu/assets":
            return _send_json(self, core.main_menu_assets_get())
        if path == "/api/main_menu/assets/file":
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else "")
            key = (qs.get("key") or [""])[0]
            fp = core._main_menu_asset_disk_path(key) if key else ""
            if fp and os.path.exists(fp):
                with open(fp, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", _mime_of(fp))
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            _send_json(self, {"error": "no asset"}, 404)
            return
        if path == "/api/battle_layout/list":
            return _send_json(self, core.battle_layout_list())
        if path == "/api/battle_layout":
            # GET ?id=xxx → 单条；无 id → 列表
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else {})
            lid = (qs.get("id") or [""])[0]
            if lid:
                return _send_json(self, core.battle_layout_get(lid))
            return _send_json(self, core.battle_layout_list())
        if path == "/api/battle_bg/file":
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else {})
            lid = (qs.get("id") or [""])[0]
            fp = core._battle_bg_path_for(lid) if lid else ""
            if fp and os.path.exists(fp):
                with open(fp, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", _mime_of(fp))
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            _send_json(self, {"error": "no bg"}, 404)
            return
        if path == "/api/demo_portrait/list":
            return _send_json(self, core.demo_portrait_list())
        if path == "/api/demo_portrait/file":
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else {})
            kind = (qs.get("kind") or [""])[0]
            fp = core.demo_portrait_file(kind) if kind else ""
            if fp and os.path.exists(fp):
                with open(fp, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", _mime_of(fp))
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            _send_json(self, {"error": "no portrait"}, 404)
            return
        if path == "/api/npc":
            return _send_json(self, core.npc_list())
        if path == "/api/npc_stats":
            return _send_json(self, core.npc_stats_get())
        if path == "/api/i18n":
            return _send_json(self, {"ok": True, "rows": core.i18n_list()})
        if path == "/api/dialog":
            return _send_json(self, core.dlg_list())
        if path == "/api/celebration":
            return _send_json(self, core.cel_list())
        if path == "/api/quest_graph":
            return _send_json(self, {"ok": True, "quests": core.quest_graph_list()})
        if path == "/api/trash":
            return _send_json(self, core.trash_list())
        if path == "/api/log":
            return _send_json(self, core.read_log())
        if path == "/api/startup_card":
            # 只读返回本地 startup_card.json（无路径输入，已被 _origin_allowed 保护，安全）。
            # 数据由 gen_startup_card.py 从 docs/AI协同启动卡.md 生成，作为「协同启动卡」标签页数据源。
            fp = os.path.join(MODULE_DIR, "startup_card.json")
            if not os.path.exists(fp):
                return _send_json(self, {"error": "startup_card.json missing, 请先运行 gen_startup_card.py"}, 404)
            try:
                with open(fp, "r", encoding="utf-8") as f:
                    data = json.load(f)
            except Exception as e:
                return _send_json(self, {"error": "startup_card.json 解析失败: %s" % e}, 500)
            return _send_json(self, data)
        if path == "/api/ui_skin":
            return _send_json(self, core.ui_skin_get())
        if path == "/api/hud/layout":
            return _send_json(self, core.hud_layout_get())
        if path == "/api/settings/layout":
            return _send_json(self, core.settings_screen_layout_get())
        if path == "/api/saveload/layout":
            return _send_json(self, core.saveload_screen_layout_get())
        if path == "/api/backlog":
            return _send_json(self, core.backlog_get())
        if path == "/api/handoff":
            return _send_json(self, _handoff_view())
        if path == "/api/modules":
            # 模块注册中心：返回当前角色可见的 Domain Module 清单（Phase 1a 骨架）。
            # 后续 Phase 3 接入鉴权后，role 从 token 解析；当前 super_admin 返回全部。
            from modules import get_modules_for_role, MODULE_REGISTRY
            role = "super_admin"  # Phase 1 暂无鉴权，默认全量
            return _send_json(self, {
                "modules": get_modules_for_role(role),
                "total_domains": len(MODULE_REGISTRY),
                "roles": list(ROLES.values()),
            })
        if path == "/api/projects":
            # Phase 2 工程适配器：列出所有可对接工程（版本切换下拉数据源）。
            try:
                from project_loader import list_projects
                return _send_json(self, {"ok": True, "projects": list_projects()})
            except Exception as e:
                return _send_json(self, {"ok": False, "error": str(e)}, 500)
        if len(parts) >= 4 and parts[0] == "api" and parts[1] == "project" and parts[2] == "manifest":
            # Phase 2 连接器视图：返回某工程的模块/AI上下文/换皮清单/经验库（不搬工程数据）。
            pid = parts[3]
            try:
                from project_loader import get_connector_info
                info = get_connector_info(pid)
            except Exception as e:
                return _send_json(self, {"ok": False, "error": str(e)}, 500)
            if info is None:
                return _send_json(self, {"ok": False, "error": "未知工程 %s" % pid}, 404)
            return _send_json(self, {"ok": True, **info})
        # ---- 经验库面板（Phase 6 落地）：读取 manifest 的 knowledge 段，并安全返回子文档全文 ----
        if path == "/api/experience":
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else {})
            pid = (qs.get("pid") or ["wuxia_game"])[0]
            try:
                from project_loader import get_connector_info
                info = get_connector_info(pid)
            except Exception as e:
                return _send_json(self, {"ok": False, "error": str(e)}, 500)
            if info is None:
                return _send_json(self, {"ok": False, "error": "未知工程 %s" % pid}, 404)
            root = core.discover_project_root()
            kn = _exp_enrich(info.get("knowledge", {}), root)
            return _send_json(self, {"ok": True, "pid": pid, "knowledge": kn})
        if len(parts) >= 3 and parts[0] == "api" and parts[1] == "experience" and parts[2] == "doc":
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else {})
            rel = (qs.get("path") or [""])[0]
            if not rel:
                return _send_json(self, {"error": "missing path"}, 400)
            root = core.discover_project_root()
            if not root:
                return _send_json(self, {"error": "no project root"}, 404)
            # 安全：解析并限制在工程根内，仅允许 .md/.txt（防穿越 / 任意文件读取）
            target = os.path.realpath(os.path.join(root, rel))
            root_real = os.path.realpath(root)
            if target != root_real and not target.startswith(root_real + os.sep):
                return _send_json(self, {"error": "forbidden path"}, 403)
            if not (target.endswith(".md") or target.endswith(".txt")):
                return _send_json(self, {"error": "only md/txt allowed"}, 403)
            if not os.path.exists(target):
                return _send_json(self, {"error": "not found"}, 404)
            try:
                with open(target, "r", encoding="utf-8") as f:
                    text = f.read()
            except Exception as e:
                return _send_json(self, {"error": str(e)}, 500)
            return _send_json(self, {"ok": True, "path": rel, "text": text})
        # ---- 双闸门验证（平台化：PM 不装 Godot 也能卡质量）----
        if path == "/api/gate/run":
            return _send_json(self, _run_gate())
        # ---- L3 任务总控：知识路由（任务 → 自动识别模块/角色/相关经验）----
        if path == "/api/orchestrate":
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else {})
            task = (qs.get("task") or [""])[0]
            if not task.strip():
                return _send_json(self, {"error": "missing task"}, 400)
            try:
                return _send_json(self, {"ok": True, **_orc_match(task)})
            except Exception as e:
                return _send_json(self, {"ok": False, "error": str(e)}, 500)
        # ---- L1 自动依赖图（平台化：PM 不翻代码也能看架构耦合/向上依赖违例）----
        if path == "/api/deps":
            try:
                import scan_deps as _sd
                root = core.discover_project_root()
                if not root:
                    return _send_json(self, {"ok": False, "error": "no project root"}, 404)
                rep = _sd.scan(root)
                return _send_json(self, {"ok": True, **rep})
            except Exception as e:
                return _send_json(self, {"ok": False, "error": str(e)}, 500)
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "npc":
            n = core.npc_get(parts[2])
            return _send_json(self, n if n is not None else {}, 404 if n is None else 200)
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "dialog":
            return _send_json(self, core.dlg_get(parts[2]))
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "celebration":
            return _send_json(self, core.cel_get(parts[2]))
        _send_json(self, {"error": "not found"}, 404)

    def do_POST(self):
        if not _origin_allowed(self):
            return _send_json(self, {"error": "forbidden origin"}, 403)
        path = self.path.split("?")[0]
        body = _read_body(self)
        parts = [p for p in path.strip("/").split("/") if p]
        if path == "/api/settings":
            s = core.load_settings()
            for k in ("project_root", "port", "retention_days", "safe_mode"):
                if k in body:
                    s[k] = body[k]
            core.save_settings(s)
            return _send_json(self, {"ok": True, "settings": s})
        # ---- L3 任务总控：变更记录闭环（登记到 docs/更改日志.md，复用 change_log.add_row）----
        if path == "/api/changelog":
            try:
                import sys as _sys
                _tools = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                if _tools not in _sys.path:
                    _sys.path.insert(0, _tools)
                import change_log as _cl
                b = body or {}
                module = (b.get("module") or "").strip()
                what = (b.get("what") or "").strip()
                if not module or not what:
                    return _send_json(self, {"ok": False, "error": "module 与 what 必填"}, 400)
                _cl.add_row(b.get("commit", ""), module, b.get("scope", ""),
                            what, b.get("impact", ""), b.get("ref", ""))
                return _send_json(self, {"ok": True, "msg": "已登记到 docs/更改日志.md"})
            except Exception as e:
                return _send_json(self, {"ok": False, "error": str(e)}, 500)
        # ---- 派单传递板：认领 + 刷新快照 ----
        if path == "/api/handoff/claim":
            tid = (body.get("id") or "").strip()
            by = (body.get("by") or "").strip()
            if not tid or not by:
                return _send_json(self, {"ok": False, "error": "id 与 by 必填"}, 400)
            ok, out = _handoff_cmd("claim", "--by", by, "--id", tid)
            if not ok:
                return _send_json(self, {"ok": False, "error": out}, 500)
            _handoff_cmd("export")  # 认领后刷新快照，前端即时可见
            return _send_json(self, {"ok": True, "msg": out, "view": _handoff_view()})
        if path == "/api/handoff/refresh":
            ok, out = _handoff_cmd("export")
            return _send_json(self, {"ok": ok, "msg": out, "view": _handoff_view()})
        if path == "/api/project_root/set":
            ok, m = core.set_project_root(body.get("root", ""))
            return _send_json(self, {"ok": ok, "msg": m,
                                     "root": core.discover_project_root()})
        if path == "/api/project_root/check":
            # 仅校验某路径是否为有效工程，不持久化
            root = (body.get("root", "") or "").strip()
            ok = bool(root) and core._has_project_marker(root)
            return _send_json(self, {"ok": ok,
                                     "msg": "有效工程" if ok else "该目录不是有效的武侠游戏工程"})
        if path == "/api/npc/rename":
            ok, m = core.npc_rename(body.get("old_id", ""), body.get("id", ""), body)
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/npc":
            ok, m = core.npc_upsert(body)
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/npc/half_body/file":
            # 读取 NPC 半身立绘图片给浏览器预览：把 res:// 路径解析成真实图片返回
            qs = urllib.parse.parse_qs(self.path.split("?", 1)[1] if "?" in self.path else {})
            res = (qs.get("res") or [""])[0]
            fp = core.npc_half_body_file(res)
            if fp:
                with open(fp, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", _mime_of(fp))
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(data)
                return
            _send_json(self, {"error": "no portrait"}, 404)
            return
        if path == "/api/npc/asset_upload":
            ok, m, res = core.npc_asset_upload(body)
            return _send_json(self, {"ok": ok, "msg": m, "res": res})
        if path == "/api/npc/portrait":
            nid = body.get("npc_id", "")
            ok, m, meta = core.npc_portrait_import(nid, body)
            if ok:
                # 把导入得到的立绘字段合并写回该 NPC 记录
                f = dict(body.get("fields", {}))
                f["id"] = nid
                f.update(meta)
                ok2, m2 = core.npc_upsert(f)
                return _send_json(self, {"ok": ok and ok2, "msg": m + "；" + m2, "meta": meta})
            return _send_json(self, {"ok": False, "msg": m})
        if path == "/api/npc/portrait_clear":
            nid = body.get("npc_id", "")
            ok, m, meta = core.npc_portrait_clear(nid)
            if ok:
                f = {"id": nid}
                f.update(meta)
                ok2, m2 = core.npc_upsert(f)
                return _send_json(self, {"ok": ok and ok2, "msg": m + "；" + m2})
            return _send_json(self, {"ok": False, "msg": m})
        if path == "/api/dialog":
            action = body.get("action")
            if action == "new":
                ok, m = core.dlg_new(body.get("id", ""))
            elif action == "upsert_line":
                ok, m = core.dlg_line_upsert(body.get("dlg_id", ""), body.get("line", {}))
            elif action == "delete_line":
                ok, m = core.dlg_line_delete(body.get("dlg_id", ""), body.get("line_id", ""))
            elif action == "delete_dialog":
                ok, m = core.dlg_delete(body.get("dlg_id", ""))
            else:
                ok, m = False, "未知 action"
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/npc_stats":
            ok, m = core.npc_stats_upsert(body.get("npc_id", ""), body.get("fields", {}))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/i18n":
            ok, m = core.i18n_upsert(body.get("key", ""), body.get("zh_CN", ""), body.get("zh_TW", ""), body.get("en", ""))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/quest_graph/save":
            ok, m = core.quest_graph_save(body.get("region", ""), body.get("qid", ""), body.get("graph", {}))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/celebration":
            ok, m = core.cel_upsert(body.get("npc_id", ""), body.get("entry", {}))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/trash/restore":
            ok, m = core.trash_restore(body.get("file", ""))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/trash/purge":
            ok = core.trash_purge(body.get("file", ""))
            return _send_json(self, {"ok": ok})
        if path == "/api/trash/cleanup":
            n = core.auto_cleanup()
            return _send_json(self, {"ok": True, "cleaned": n})
        # ---- 登录界面修改插件 (POST) ----
        if path == "/api/login/bg":
            raw = base64.b64decode(body.get("data", "") or b"")
            if not raw:
                return _send_json(self, {"ok": False, "msg": "空数据"}, 400)
            tmp = os.path.join(core.SAFETY_DIR, "up_bg_%d.bin" % int(datetime.datetime.now().timestamp() * 1000))
            with open(tmp, "wb") as f:
                f.write(raw)
            ok, m = core.login_bg_replace(tmp)
            try:
                os.remove(tmp)
            except Exception:
                pass
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/login/texts":
            ok, m = core.login_texts_update(body.get("rows", []))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/login/btn_bg":
            raw = base64.b64decode(body.get("data", "") or b"")
            if not raw:
                return _send_json(self, {"ok": False, "msg": "空数据"}, 400)
            btn_id = body.get("btn_id", "")
            if not btn_id:
                return _send_json(self, {"ok": False, "msg": "缺少 btn_id"}, 400)
            tmp = os.path.join(core.SAFETY_DIR, "up_btn_%s.bin" % btn_id)
            with open(tmp, "wb") as f:
                f.write(raw)
            ok, m = core.login_btn_bg_set(btn_id, tmp)
            try:
                os.remove(tmp)
            except Exception:
                pass
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/login/bg_layout":
            ok, m = core.login_bg_layout_update(body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/loading/layout":
            ok, m = core.loading_layout_update(body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/main_menu/layout":
            ok, m = core.main_menu_layout_update(body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/ui_slot/upload":
            raw = base64.b64decode(body.get("data", "") or b"")
            if not raw:
                return _send_json(self, {"ok": False, "msg": "空数据"}, 400)
            screen_rel = str(body.get("screen", ""))
            node_path = str(body.get("node", ""))
            prop = str(body.get("prop", "texture"))
            if not screen_rel or not node_path:
                return _send_json(self, {"ok": False, "msg": "缺少 screen / node"}, 400)
            tmp = os.path.join(core.SAFETY_DIR,
                               "up_uislot_%d.bin" % int(datetime.datetime.now().timestamp() * 1000))
            with open(tmp, "wb") as f:
                f.write(raw)
            ok, m = core.ui_slot_upload(screen_rel, node_path, prop, tmp)
            try:
                os.remove(tmp)
            except Exception:
                pass
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/ui_slot/clear":
            ok, m = core.ui_slot_clear(str(body.get("screen", "")), str(body.get("node", "")),
                                       str(body.get("prop", "texture")))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/ui_bg/add":
            ok, m = core.ui_bg_add(str(body.get("screen", "")))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/main_menu/assets/replace":
            raw = base64.b64decode(body.get("data", "") or b"")
            if not raw:
                return _send_json(self, {"ok": False, "msg": "空数据"}, 400)
            key = body.get("key", "")
            if not key:
                return _send_json(self, {"ok": False, "msg": "缺少 key"}, 400)
            tmp = os.path.join(core.SAFETY_DIR, "up_mm_%s_%d.bin" % (key, int(datetime.datetime.now().timestamp() * 1000)))
            with open(tmp, "wb") as f:
                f.write(raw)
            ok, m = core.main_menu_asset_replace(key, tmp)
            try:
                os.remove(tmp)
            except Exception:
                pass
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/main_menu/assets/clear_icon":
            ok, m = core.main_menu_asset_clear_icon(int(body.get("idx", 0)))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/main_menu/icon_scales":
            ok, m = core.main_menu_icon_scales_set(body.get("scales", {}) if isinstance(body.get("scales"), dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/main_menu/hover_shift":
            ok, m = core.main_menu_hover_shift_set(body.get("x"), body.get("y"))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/battle_layout/save":
            lid = str(body.get("id", ""))
            ok, m = core.battle_layout_save(lid, body.get("data", {}) if isinstance(body.get("data"), dict) else body)
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/battle_layout/preset":
            ok, m = core.battle_layout_preset(int(body.get("size", 10)))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/battle_layout/delete":
            ok, m = core.battle_layout_delete(str(body.get("id", "")))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/battle_bg/upload":
            ok, m = core.battle_bg_upload(str(body.get("id", "")), body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/battle_bg/clear":
            ok, m = core.battle_bg_clear(str(body.get("id", "")))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/demo_portrait/upload":
            ok, m = core.demo_portrait_upload(str(body.get("kind", "")), body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/demo_portrait/reset":
            ok, m = core.demo_portrait_reset(str(body.get("kind", "")))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/login/btn_bg_clear":
            ok, m = core.login_btn_bg_clear(body.get("btn_id", ""))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/login/btn_bg_fix":
            ok, m = core.login_btn_bg_scan_fix()
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/login/bg_variant":
            raw = base64.b64decode(body.get("data", "") or b"")
            if not raw:
                return _send_json(self, {"ok": False, "msg": "空数据"}, 400)
            tmp = os.path.join(core.SAFETY_DIR, "up_bgvar_%s.bin" % (body.get("tag", "v")))
            with open(tmp, "wb") as f:
                f.write(raw)
            ok, m = core.login_bg_variant_set(tmp, body.get("tag", ""), body.get("min_width", 0))
            try:
                os.remove(tmp)
            except Exception:
                pass
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/login/bg_variant_remove":
            ok, m = core.login_bg_variant_remove(body.get("min_width", -1))
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/ui_skin":
            kind = str(body.get("kind", ""))
            d = body.get("data", {}) if isinstance(body.get("data"), dict) else {}
            ok, m = core.ui_skin_save(kind, d)
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/hud/layout":
            ok, m = core.hud_layout_update(body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/settings/layout":
            ok, m = core.settings_screen_layout_update(body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        if path == "/api/saveload/layout":
            ok, m = core.saveload_screen_layout_update(body if isinstance(body, dict) else {})
            return _send_json(self, {"ok": ok, "msg": m})
        _send_json(self, {"error": "not found"}, 404)

    def do_DELETE(self):
        if not _origin_allowed(self):
            return _send_json(self, {"error": "forbidden origin"}, 403)
        path = self.path.split("?")[0]
        parts = [p for p in path.strip("/").split("/") if p]
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "npc":
            ok, m = core.npc_delete(parts[2])
            return _send_json(self, {"ok": ok, "msg": m})
        if len(parts) == 3 and parts[0] == "api" and parts[1] == "celebration":
            ok, m = core.cel_delete(parts[2])
            return _send_json(self, {"ok": ok, "msg": m})
        _send_json(self, {"error": "not found"}, 404)


def main():
    core.auto_cleanup()
    s = core.load_settings()
    # 支持 --root=路径 / --root 路径：启动即指定工程根目录并持久化，便于跨电脑/换盘使用
    for i, a in enumerate(sys.argv[1:]):
        if a.startswith("--root"):
            val = a.split("=", 1)[1] if "=" in a else (sys.argv[i + 2] if i + 2 < len(sys.argv) else "")
            if val:
                ok, m = core.set_project_root(val)
                if not ok:
                    print("[警告] --root 指定目录无效：%s" % m)
            break
    s = core.load_settings()
    base_port = int(s.get("port", 8765))
    # 端口自动顺延：8765 被占就试 8766..8765+20，用户永远不需要手动调端口。
    server = None
    last_err = None
    for cand in range(base_port, base_port + 21):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", cand), Handler)
            port = cand
            break
        except OSError as e:
            last_err = e
            continue
    if server is None:
        print("[错误] 无法在 %d~%d 绑定本地端口（可能被其他工作室进程占用）：%s" % (base_port, base_port + 20, last_err))
        return
    url = "http://127.0.0.1:%d/" % port
    print("内容工作室 桌面版已启动: %s" % url)
    print("按 Ctrl+C 关闭")
    try:
        webbrowser.open(url)
    except Exception:
        pass
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    try:
        main()
    except Exception as _e:
        # 兜底：任何启动期异常都打印真实错误并停留，避免"黑窗口闪一下就没"看不出原因
        import traceback
        traceback.print_exc()
        sys.stderr.write("\n[启动失败] 内容工作室未能启动，错误信息见上。按任意键关闭本窗口...\n")
        try:
            if sys.stdin.isatty():
                input()
        except Exception:
            pass
