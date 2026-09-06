# -*- coding: utf-8 -*-
"""localization_validator.py — GATE18 Localization 物理化（2026-09-06 F5）

宪法 §88 LN-GATE18 / 03 图 C-R12 + 05 图规则表 VA5-DISPLAY-KEY（双端同读）。
  C-R12  内容配置禁止硬编码中文（面向玩家的文本须存本地化键，03 图 D-3/宪法 §123）——
         存量 346 处中文内联（P-Q9 同族）按项目既定「基线禁新增」模式管理：
         tools/loc_baseline.json 基线只减不增，基线外零容忍（新增即红）。
  VA5    display 文本键（*_text_id）必须存在于 strings.csv——规则表 severity=WARN，
         VA-3 处置表：通报不拦。
扫描面：data/configs/**/*.json（localization/ 目录豁免）；递归对象键值字符串 + 数组元素。
挂槽：物理槽 GATE43（verify_all GATES[43]）；contract_registry / manifest / PROJECT_STATUS 三同步。
用法：
  python tools/localization_validator.py                # 校验（基线外新增=退出码1）
  python tools/localization_validator.py --fix-baseline # 首次生成/收编基线（人工确认后用）
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CFG = os.path.join(ROOT, "data", "configs")
BASELINE = os.path.join(HERE, "loc_baseline.json")
STRINGS = os.path.join(CFG, "localization", "strings.csv")

CJK = re.compile(r"[\u4e00-\u9fff]")
TEXT_ID_SUFFIX = "_text_id"

violations = []
warns = []
notes = []


def _walk(node, out, key=""):
    """递归收集 (键名, 字符串值)。数组元素记键名 (array)。"""
    if isinstance(node, dict):
        for k, v in node.items():
            _walk(v, out, str(k))
    elif isinstance(node, list):
        for el in node:
            _walk(el, out, "(array)")
    elif isinstance(node, str):
        out.append((key, node))


def _strings_keys():
    keys = set()
    if os.path.exists(STRINGS):
        for line in open(STRINGS, encoding="utf-8-sig"):
            s = line.strip()
            if s and not s.startswith("#"):
                keys.add(s.split(",")[0].strip())
    return keys


def scan():
    known = set()
    if os.path.exists(BASELINE):
        try:
            known = set(json.load(open(BASELINE, encoding="utf-8")).get("c_r12", []))
        except Exception:
            known = set()
    current = set()
    display_bad = []
    skeys = _strings_keys()

    for dirpath, dirs, files in os.walk(CFG):
        dirs[:] = [d for d in dirs if d != "localization"]
        for fn in files:
            if not fn.endswith(".json"):
                continue
            fp = os.path.join(dirpath, fn)
            rel = os.path.relpath(fp, ROOT).replace(os.sep, "/")
            try:
                data = json.load(open(fp, encoding="utf-8"))
            except Exception:
                continue
            pairs = []
            _walk(data, pairs)
            for key, val in pairs:
                if CJK.search(val):
                    current.add("%s | %s | %s" % (rel, key, val.strip()[:60]))
                if key.endswith(TEXT_ID_SUFFIX) and val.strip():
                    if val.strip() not in skeys:
                        display_bad.append("%s | %s = %s（strings.csv 无此键）"
                                           % (rel, key, val.strip()))

    new = current - known
    for sig in sorted(new)[:12]:
        violations.append(("C-R12", sig.split(" | ")[0], "硬编码中文（基线外新增）: %s" % sig))
    for d in display_bad[:8]:
        warns.append("VA5-DISPLAY-KEY: " + d)
    notes.append("C-R12: 存量基线 %d 条 / 当前 %d 处 / 基线外新增 %d（基线只减不增）"
                 % (len(known), len(current), len(new)))
    notes.append("VA5: display 文本键核对 %d 键（strings.csv），违例 %d（WARN 通报不拦）"
                 % (len(skeys), len(display_bad)))
    return current


def fix_baseline(current):
    json.dump({"_doc": "GATE18 C-R12 硬编码中文基线（只减不增；新增即红。收编流程=修一条删一条）",
               "frozen_at": "2026-09-06", "c_r12": sorted(current)},
              open(BASELINE, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("--fix-baseline 已写基线: c_r12 %d 条" % len(current))


def main():
    current = scan()
    if "--fix-baseline" in sys.argv:
        fix_baseline(current)
        sys.exit(0)
    print("localization_validator · 物理槽 GATE43（LN GATE18：03图 C-R12 + VA5-DISPLAY-KEY）")
    for w in warns:
        print("  ⚠ " + w)
    for n in notes:
        print("  ℹ " + n)
    if violations:
        for rule, f, ev in violations:
            print("  ✗ [%s] %s — %s" % (rule, f, ev))
        print("════ 结论：✗ %d 项基线外新增（本地化契约）════" % len(violations))
        sys.exit(1)
    print("════ 结论：✓ 通过（基线外零新增 / display 键核对完成）════")
    sys.exit(0)


if __name__ == "__main__":
    main()
