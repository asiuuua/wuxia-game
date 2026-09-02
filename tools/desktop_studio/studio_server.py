#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
武侠游戏「内容工作室」桌面版 —— 本地 Web 服务（仅标准库）。
启动后浏览器打开 http://127.0.0.1:端口/ 即可使用，全程零代码改 NPC / 剧情 / 欢庆数据，
并带保险模式（删除进回收站 + 写前自动备份 + 操作日志 + 过期自动清空）。

启动方式：
  - 双击 studio_launcher.bat
  - 或：python studio_server.py
"""

import os
import sys
import json
import webbrowser
import datetime
import base64
import urllib.parse
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
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not _origin_allowed(self):
            return _send_json(self, {"error": "forbidden origin"}, 403)
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"):
            self._serve_file("index.html", "text/html; charset=utf-8")
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
        if path == "/api/dialog":
            return _send_json(self, core.dlg_list())
        if path == "/api/celebration":
            return _send_json(self, core.cel_list())
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
        if path == "/api/backlog":
            return _send_json(self, core.backlog_get())
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
    main()
