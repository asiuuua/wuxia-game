#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
「内容工作室」安全自检（零依赖，标准库）。
跑法：python security_selftest.py
覆盖 2026-08-30 加固的全部防护点，任何一项 FAIL 即退出码 1（防回归）：
  1) 对话 id 白名单（拼文件路径的 id 拒绝穿越）
  2) 按钮 id 白名单
  3) 回收站文件名 basename（防穿越删除/读取）
  4) 立绘 ZIP 解压条目校验（防 Zip Slip）
  5) 服务器 Origin/Referer 校验（防恶意网页 CSRF）
"""
import base64
import io
import os
import shutil
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import studio_core as core
import studio_server as srv

_FAILED = []


def _check(name, ok, detail=""):
    print("%s %s%s" % ("PASS" if ok else "FAIL", name, "  " + detail if detail else ""))
    if not ok:
        _FAILED.append(name)


def _test_ids_and_trash():
    _check("dlg_new 穿越 id 被拒", core.dlg_new("../../evil")[0] is False)
    _check("dlg_get 穿越 id 返回空", core.dlg_get("../../evil") == {})
    _check("dlg_line_upsert 穿越 id 被拒",
           core.dlg_line_upsert("../../evil", {"id": "l1"})[0] is False)
    _check("dlg_line_delete 穿越 id 被拒",
           core.dlg_line_delete("../../evil", "l1")[0] is False)
    _check("login_btn_bg_set 穿越 id 被拒",
           core.login_btn_bg_set("../../evil", os.path.abspath(__file__))[0] is False)
    _check("trash_restore 穿越文件名安全",
           core.trash_restore("../../npc数据文件.json")[0] is False)
    _check("trash_purge 穿越文件名安全", core.trash_purge("../../npc数据文件.json") is False)


def _make_zip(entries):
    buf = io.BytesIO()
    z = zipfile.ZipFile(buf, "w")
    for name, data in entries.items():
        z.writestr(name, data)
    z.close()
    return base64.b64encode(buf.getvalue()).decode()


def _test_zip_slip():
    bad = _make_zip({"../evil.png": b"X"})
    ok, m, _ = core.npc_portrait_import("zz_security_test", {"ptype": "frame", "zip": bad})
    _check("Zip Slip（../ 条目）被拒", ok is False, m[:40])
    bad2 = _make_zip({"/abs.png": b"X"})
    ok2, _, _ = core.npc_portrait_import("zz_security_test", {"ptype": "frame", "zip": bad2})
    _check("Zip Slip（绝对路径条目）被拒", ok2 is False)
    good = _make_zip({"f1.png": b"X" * 8})
    ok3, _, meta = core.npc_portrait_import("zz_valid_test", {"ptype": "frame", "zip": good})
    _check("合法 ZIP 正常导入", ok3 and len(meta.get("portrait_frames", [])) == 1)
    for d in ("zz_security_test_frames", "zz_valid_test_frames"):
        p = os.path.join(core._half_body_dir(), d)
        if os.path.isdir(p):
            shutil.rmtree(p)


class _FakeHandler:
    def __init__(self, headers):
        self.headers = headers


def _test_origin():
    _check("无 Origin（curl/非浏览器）放行", srv._origin_allowed(_FakeHandler({})) is True)
    _check("工具自身 Origin 放行",
           srv._origin_allowed(_FakeHandler({"Origin": "http://127.0.0.1:8765"})) is True)
    _check("恶意网页 Origin 拦截",
           srv._origin_allowed(_FakeHandler({"Origin": "http://evil.com"})) is False)
    _check("恶意网页 Referer 拦截",
           srv._origin_allowed(_FakeHandler({"Referer": "http://evil.com/x"})) is False)
    _check("file:// 本地页放行",
           srv._origin_allowed(_FakeHandler({"Origin": "null"})) is True)


def main():
    _test_ids_and_trash()
    _test_zip_slip()
    _test_origin()
    print("=" * 40)
    if _FAILED:
        print("安全自检：%d 项 FAIL -> %s" % (len(_FAILED), _FAILED))
        sys.exit(1)
    print("安全自检：全部通过")


if __name__ == "__main__":
    main()