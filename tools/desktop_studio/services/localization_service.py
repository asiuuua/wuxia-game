# -*- coding: utf-8 -*-
"""本地化内容域服务：strings.csv 文案表的读 / 列表 / 写回。

游戏 LocalizationManager 读 data/configs/localization/strings.csv（key,zh_CN,zh_TW,en）注册进
TranslationServer，之后全局 tr(text_key) 即返回当前语言文案。这里把文案表接回后台，方便小白
只改表、不改逻辑地做多语言。
"""

import os
import csv
import io

from services import _common
from services._common import (  # noqa: F401  门面透传用
    _safe_id, _is_valid_id, _ensure_dirs, load_settings, save_settings,
    load_json, _backup, _backup_dir,
    SAFETY_DIR, TRASH_DIR, BACKUP_DIR, SETTINGS_PATH, LOG_PATH,
    DEFAULT_PROJECT_ROOT, DEFAULT_PORT, DEFAULT_RETENTION_DAYS, DEFAULT_SAFE_MODE,
)
from services.project_service import discover_project_root
from services.audit_service import log_event
from services.repositories.localization_repository import localization_repo


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
    buf = io.StringIO()
    csv.writer(buf).writerows(rows)
    localization_repo.save_csv(buf.getvalue(), note="i18n_upsert %s" % key)
    log_event("i18n_save", key, "更新文案表")
    return True, "已保存文案 %s（多语言立即生效）" % key
