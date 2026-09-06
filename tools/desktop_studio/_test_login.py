#!/usr/bin/env python3
import os, shutil, sys, json, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import studio_core as core

ROOT = "D:/武侠游戏"
T = tempfile.mkdtemp(prefix="logintest_")

def cp(rel):
    src = os.path.join(ROOT, rel)
    dst = os.path.join(T, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)  # verify-allow: 自检夹具复制助手（目标=临时工程 T，非生产写）

cp("data/configs/localization/strings.csv")  # verify-allow: 自检夹具造临时工程，非生产写
cp("scenes/ui/screens/main_menu/MainMenu.gd")
os.makedirs(os.path.join(T, "assets/ui"), exist_ok=True)
open(os.path.join(T, "project.godot"), "w").close()  # 让 discover_project_root 认 T 为合法工程根

import data_sink as _ds
_ds._changelog_enabled = False  # 测试静默 ⑥

import data_sink as _ds
_ds._changelog_enabled = False  # 测试静默 ⑥

core.save_settings({"project_root": T, "port": 8799, "retention_days": 30, "safe_mode": True})

# 1) bg info (no file yet)
info = core.login_bg_info()
assert info["exists"] is False, info
print("[1] bg_info no-file OK ->", info)

# 2) make a tiny png and replace bg
png = os.path.join(T, "x.png")
with open(png, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n")  # fake but valid-enough bytes for copy
ok, m = core.login_bg_replace(png)
assert ok and os.path.exists(os.path.join(T, "assets/ui/main_menu_bg.png")), m
print("[2] bg_replace OK ->", m)

# 3) texts read
txts = core.login_texts()
byk = {t["key"]: t for t in txts}
assert byk["menu_new_game"]["zh_CN"] == "开始游戏", byk["menu_new_game"]  # 2026-09-06 对齐 774707e 水墨重构后的文案真源
print("[3] texts read OK, count=%d (menu_new_game=%s)" % (len(txts), byk["menu_new_game"]["zh_CN"]))

# 4) update one text
ok, m = core.login_texts_update([{"key": "menu_new_game", "zh_CN": "新的征程", "zh_TW": "新的征途", "en": "New Path"}])
assert ok
# re-read raw csv to confirm persisted
import csv
with open(os.path.join(T, "data/configs/localization/strings.csv"), "r", encoding="utf-8-sig") as f:
    rows = list(csv.DictReader(f))
row = next(r for r in rows if r["keys"] == "menu_new_game")
assert row["zh_CN"] == "新的征程", row
print("[4] texts_update OK ->", m, "| csv now:", row["zh_CN"], row["zh_TW"], row["en"])

# 5) version parse
v = core.login_version()
assert v["version"].startswith("v0.5.0"), v  # 2026-09-06 对齐 RH-1：夹具无 provenance → dev 态
print("[5] version OK ->", v["version"])

# 6) btn bg set + list（键须与 LOGIN_TEXT_KEYS 一致，即 menu_new_game）
ok, m = core.login_btn_bg_set("menu_new_game", png)
assert ok and os.path.exists(os.path.join(T, "assets/ui/main_menu_btn/menu_new_game.png")), m
cfg = json.load(open(os.path.join(T, "data/configs/ui/login_button_bg.json"), encoding="utf-8"))
assert cfg["map"]["menu_new_game"].endswith("menu_new_game.png"), cfg
lst = core.login_btn_bg_list()
print("[6-debug] lst =", lst)
assert any(b["key"] == "menu_new_game" for b in lst)
assert lst[0]["path"].endswith("menu_new_game.png"), lst[0]
print("[6] btn_bg OK ->", m, "| list count=", len(lst))

print("ALL_LOGIN_TESTS_PASSED")
shutil.rmtree(T, ignore_errors=True)
# 清理本测试在 desktop_studio/safety_data 留下的设置与备份
sd = core.SAFETY_DIR
shutil.rmtree(sd, ignore_errors=True)
print("cleaned safety_data")
