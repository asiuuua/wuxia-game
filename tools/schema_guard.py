# -*- coding: utf-8 -*-
"""schema_guard.py — 03 图 Contract/Schema 校验器（物理槽 GATE06，2026-09-06 落地）

覆盖 Enforcement（03 图 §8）与 ADR-0004：
  C-R04  顶层 version 字段必须三段 SemVer `MAJOR.MINOR.PATCH`（ERROR）。
  C-R05  内容结构变更必须升版本号（FATAL）：对每个带 version 的 JSON 生成结构指纹
         （形状哈希，忽略标量值只看键结构/类型），与基线比对——
         · 形状同           → 通过（提前升版合法）
         · 形状变 + 已升版  → 通过 + 通报 --update-baseline 收编新指纹
         · 形状变 + 未升版  → FATAL（V-1）
  ADR-0004  data/schemas/*.gd 强类型 Schema 类 → 机器可读摘要（schema_classes 段），
         供工作室/工具消费；.gd 字段漂移需显式 --update-baseline（契约变更留痕）。

基线: tools/schema_digest_baseline.json（首次运行自动生成；C-R05 指纹快照属
      「合法变更即更新」型基线，与 id_baseline 的「违例登记只减不增」型不同）。
用法: python tools/schema_guard.py [--update-baseline]   （退出码 0=通过 1=违规）
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BASELINE = os.path.join(HERE, "schema_digest_baseline.json")
SCHEMA_DIR = os.path.join(ROOT, "data", "schemas")
CFG_DIR = os.path.join(ROOT, "data", "configs")

SEMVER3 = re.compile(r"^\d+\.\d+\.\d+$")

# GDScript 类型 → 摘要类型（机器可读，ADR-0004）
GD_TYPE_MAP = {
    "String": "string", "StringName": "string",
    "int": "integer", "float": "number", "bool": "boolean",
    "Array": "array", "Dictionary": "object", "Vector2": "vector2",
}

RE_EXPORT = re.compile(
    r'^@export\s+var\s+(\w+)\s*:\s*([A-Za-z_][\w]*)(?:\[(.+?)\])?\s*(?:=\s*(.+?))?\s*(?:#.*)?$')


def semver_tuple(v):
    return tuple(int(x) for x in v.split("."))


def shape_sig(obj):
    """结构指纹：dict→排序键+子形状；list→元素形状集合；标量→类型名。值内容不参与。"""
    if isinstance(obj, dict):
        return "{" + ",".join("%s:%s" % (k, shape_sig(obj[k])) for k in sorted(obj)) + "}"
    if isinstance(obj, list):
        if not obj:
            return "[]"
        inner = sorted({shape_sig(x) for x in obj})
        return "[" + ("|".join(inner) if len(inner) > 1 else inner[0]) + "]"
    if isinstance(obj, bool):
        return "bool"
    if isinstance(obj, (int, float)):
        return "num"
    if isinstance(obj, str):
        return "str"
    if obj is None:
        return "null"
    return "?"


def scan_versions():
    """C-R04/R05 扫描面：data/configs/**.json 顶层带 version 字段者。"""
    out = []
    for dirpath, _dirs, files in os.walk(CFG_DIR):
        for fn in sorted(files):
            if not fn.endswith(".json") or fn.startswith("_"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            try:
                data = json.load(open(full, encoding="utf-8"))
            except Exception:
                continue   # 解析失败归 id_validator/ref_index 的 JSON 解析检查报
            if isinstance(data, dict) and "version" in data:
                out.append((rel, str(data.get("version", "")), data))
    return out


def parse_schema_classes():
    """ADR-0004：解析 data/schemas/*.gd 的 @export 字段为机器可读摘要。"""
    digest = []
    if not os.path.isdir(SCHEMA_DIR):
        return digest
    for fn in sorted(os.listdir(SCHEMA_DIR)):
        if not fn.endswith(".gd"):
            continue
        rel = "data/schemas/" + fn
        cls = None
        parent = None
        props = {}
        for i, ln in enumerate(open(os.path.join(SCHEMA_DIR, fn), encoding="utf-8"), 1):
            s = ln.strip()
            m = re.match(r"^class_name\s+(\w+)", s)
            if m:
                cls = m.group(1)
                continue
            m = re.match(r"^extends\s+([\w.]+)", s)
            if m and parent is None:
                parent = m.group(1)
                continue
            m = RE_EXPORT.match(s)
            if m:
                name, gtype, gparam, default = m.groups()
                if gtype in GD_TYPE_MAP:
                    jtype = GD_TYPE_MAP[gtype]
                    if gtype == "Array" and gparam:
                        jtype = {"type": "array", "items": GD_TYPE_MAP.get(gparam, gparam)}
                else:
                    jtype = {"$ref": gtype}   # Resource 子类引用
                props[name] = {"type": jtype, "line": i}
                if default is not None and default != "":
                    props[name]["default"] = default.strip()
        digest.append({
            "file": rel,
            "class_name": cls or fn[:-3],
            "extends": parent,
            "properties": props,
        })
    return digest


def main():
    update = "--update-baseline" in sys.argv
    base = {}
    if os.path.exists(BASELINE):
        base = json.load(open(BASELINE, encoding="utf-8"))
    first = not bool(base)

    violations = []
    notes = []

    # ---- C-R04：版本号三段 SemVer ----
    rows = scan_versions()
    for rel, ver, _data in rows:
        if not SEMVER3.match(ver):
            violations.append(("C-R04", rel, "version=%r 非三段 SemVer（03图§5.1 冻结格式）" % ver))

    # ---- C-R05：结构指纹 vs 基线（形状变必须升版） ----
    old = base.get("content_shapes", {})
    new_shapes = {rel: {"version": ver, "shape": shape_sig(data)} for rel, ver, data in rows}
    stale = False
    if first:
        notes.append("基线首次生成：%d 个带 version 内容文件" % len(new_shapes))
    else:
        for rel, cur in sorted(new_shapes.items()):
            prev = old.get(rel)
            if prev is None:
                notes.append("新纳入 version 管控: %s（--update-baseline 收编）" % rel)
                stale = True
                continue
            if cur["shape"] == prev.get("shape"):
                continue
            try:
                bumped = semver_tuple(cur["version"]) > semver_tuple(prev.get("version", "0.0.0"))
            except ValueError:
                bumped = False
            if bumped:
                notes.append("%s 结构变更已升版 %s→%s ✓（--update-baseline 收编新指纹）"
                             % (rel, prev.get("version"), cur["version"]))
                stale = True
            else:
                violations.append(("C-R05", rel,
                                   "内容结构变更但 version 停留 %s（V-1/C-R05：结构变更必须升版）"
                                   % prev.get("version")))
        for rel in sorted(set(old) - set(new_shapes)):
            notes.append("version 管控对象消失: %s（基线将随之移除）" % rel)
            stale = True

    # ---- ADR-0004：Schema 类摘要漂移检测 ----
    now_cls = parse_schema_classes()
    old_cls = base.get("schema_classes", [])
    if first:
        notes.append("Schema 摘要首次生成：%d 个类（ADR-0004 机器可读）" % len(now_cls))
    elif now_cls != old_cls:
        violations.append(("ADR-0004", "data/schemas/*.gd",
                           "Schema 类签名漂移（字段/类型/默认值变更须显式 --update-baseline 留痕）"))
        stale = True

    # ---- 基线更新 ----
    if update or first:
        base["content_shapes"] = new_shapes
        base["schema_classes"] = now_cls
        base["_doc"] = ("C-R05 结构指纹快照（合法变更升版后 --update-baseline 收编）+ "
                        "ADR-0004 Schema 类摘要。生成器: tools/schema_guard.py")
        json.dump(base, open(BASELINE, "w", encoding="utf-8"), ensure_ascii=False, indent=1, sort_keys=True)
        print("  [schema_guard] 基线已写入 %s" % os.path.relpath(BASELINE, ROOT))

    # ---- 报告 ----
    print("schema_guard · 03图 C-R04/C-R05 + ADR-0004（GATE06）")
    print("  version 管控: %d 文件 | Schema 类摘要: %d 个" % (len(rows), len(now_cls)))
    for n in notes:
        print("  ℹ " + n)
    if violations:
        for rule, f, ev in violations:
            print("  ✗ [%s] %s — %s" % (rule, f, ev))
        print("════ 结论：✗ %d 项违规 ════" % len(violations))
        sys.exit(1)
    if stale and not update:
        print("  （存在待收编变更：跑 --update-baseline 更新基线后此通报消失）")
    print("════ 结论：✓ 通过（版本三段 / 结构变更必升版 / Schema 摘要在位）════")
    sys.exit(0)


if __name__ == "__main__":
    main()
