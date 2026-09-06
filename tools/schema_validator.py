# -*- coding: utf-8 -*-
"""schema_validator.py — Phase 3 Schema 系统构建期校验器（03 图 §6.3 / 05 图 VA-2 第一层）

真源 = data/configs/content_schemas.json（与 GDScript 运行期 content_registry/ConfigManager
双端读取同一份，防两套规则漂移）。

校验能力（整改报告 Phase 3 第一批 Schema：NPC / Dialogue / Quest / Localization / Asset）：
  - 字段类型 type：string / number / integer / boolean / array / object
  - required：字段必须存在；required 且非 allow_empty 时值必须非空
  - allow_empty：string 空串 / array / object 空容器放行
  - enum：string 值白名单
  - regex：string 值形态
  - stable_id：值必须过 ID 白名单（data_sink.is_valid_id，03 §3 同源）
  - 引用标注（asset_ref / dialogue_ref / quest_ref / npc_ref / battle_ref / localization_key）：
    本阶段只登记标注（Phase 4 Reference 三件套消费做存在性校验）；悬空兜底现由
    ref_index（GATE06 / DataSink ⑤）承担，不重复实现。
  - CSV 专项：localization/strings.csv 表头与 key 形态。

用法：
  python tools/schema_validator.py            # 全量扫描 data/configs，违规即退出码 1
  python tools/schema_validator.py --quiet    # 只输出违规行（供 verify_all 管道）
"""
import argparse
import fnmatch
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CONFIGS_REL = "data/configs"   # 固定正斜杠（Windows os.path.join 会产生反斜杠，破坏前缀匹配）
SCHEMAS_FILE = "content_schemas.json"

if HERE not in sys.path:
    sys.path.insert(0, HERE)


class Violation:
    __slots__ = ("file", "schema", "path", "message")

    def __init__(self, file, schema, path, message):
        self.file = file
        self.schema = schema
        self.path = path
        self.message = message

    def __str__(self):
        return "%s [%s] %s: %s" % (self.file, self.schema, self.path or "(root)", self.message)


def _load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def load_schemas(root):
    """读取 Schema 真源：目标工程缺失时回退本仓真源（宪法资产随工具走，同 data_sink）。"""
    for base in (root, ROOT):
        p = os.path.join(base, CONFIGS_REL, SCHEMAS_FILE)
        d = _load_json(p)
        if d and isinstance(d, dict) and d.get("schemas"):
            return d
    return {}


def _id_validator():
    """stable_id 口径与 id_validator（GATE06）同源：白名单正则命中 OR 存量基线内。
    基线 = tools/id_baseline.json violations 的 (data/configs/相对路径, id) 对，只减不增。"""
    try:
        import data_sink
        is_valid = data_sink.is_valid_id
    except Exception:
        is_valid = lambda eid: True
    base = _load_json(os.path.join(HERE, "id_baseline.json"), {}) or {}
    baseline = {(str(v.get("file", "")).replace("\\", "/"), str(v.get("id", "")))
                for v in base.get("violations", []) if isinstance(v, dict)}

    def check(eid, rel=""):
        if is_valid(eid):
            return True
        key = ("data/configs/%s" % rel.replace("\\", "/")) if rel else ""
        return (key, eid) in baseline
    return check


_VALID_TYPES = {"string", "number", "integer", "boolean", "array", "object"}


def _type_of(v):
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, int):
        return "integer"
    if isinstance(v, float):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    if isinstance(v, dict):
        return "object"
    return type(v).__name__


def _value_empty(v):
    """空值判定：空串 / 空数组 / 空 dict。number/bool 恒非空。"""
    if isinstance(v, str):
        return v == ""
    if isinstance(v, (list, dict)):
        return len(v) == 0
    return False


def _check_field(violations, file, schema_id, entry_no, field, spec, value, is_valid_id, rel=""):
    t = spec.get("type", "string")
    got = _type_of(value)
    if got != t and not (t == "number" and got == "integer"):
        violations.append(Violation(file, schema_id, "条目#%d.%s" % (entry_no, field),
                                    "类型应为 %s，实际 %s" % (t, got)))
        return
    if isinstance(value, str):
        if spec.get("enum") and value not in spec["enum"]:
            violations.append(Violation(file, schema_id, "条目#%d.%s" % (entry_no, field),
                                        "值「%s」不在枚举 %s 内" % (value, spec["enum"])))
        pat = spec.get("regex")
        if pat:
            try:
                if not re.match(pat, value):
                    violations.append(Violation(file, schema_id, "条目#%d.%s" % (entry_no, field),
                                                "值「%s」不合形态 %s" % (value, pat)))
            except re.error:
                pass
        if spec.get("stable_id") and value and not is_valid_id(value, rel):
            violations.append(Violation(file, schema_id, "条目#%d.%s" % (entry_no, field),
                                        "ID「%s」不合 03§3.3 白名单形态（基线外零容忍）" % value))
    if t == "array" and isinstance(value, list) and spec.get("item_type"):
        for i, el in enumerate(value):
            if _type_of(el) != spec["item_type"] and not (
                    spec["item_type"] == "number" and _type_of(el) == "integer"):
                violations.append(Violation(file, schema_id, "条目#%d.%s[%d]" % (entry_no, field, i),
                                            "数组元素应为 %s，实际 %s" % (spec["item_type"], _type_of(el))))


def _validate_entries(violations, file, schema_id, entries, fields, is_valid_id, loose=False, rel=""):
    for entry_no, e in enumerate(entries):
        if not isinstance(e, dict):
            violations.append(Violation(file, schema_id, "条目#%d" % entry_no,
                                        "条目应为 object，实际 %s" % _type_of(e)))
            continue
        for f, spec in fields.items():
            if f not in e:
                if spec.get("required"):
                    violations.append(Violation(file, schema_id, "条目#%d" % entry_no,
                                                "缺必填字段 %s" % f))
                continue
            _check_field(violations, file, schema_id, entry_no, f, spec, e[f], is_valid_id, rel)


def _validate_file_schema(file, data, schema, is_valid_id, violations):
    """按单条 schema 校验单文件内容（返回是否有命中）。"""
    schema_id = schema.get("title") or file
    fields = schema.get("entry_fields", {})
    loose = bool(schema.get("loose"))
    # 1) 提取条目
    entries = []
    if schema.get("csv"):
        if isinstance(data, dict):   # 已解析的 JSON 不匹配 CSV schema
            return False
        _validate_csv(file, data, schema, violations)
        return True
    if schema.get("root_entry"):
        entries = [data]
    elif schema.get("value_schema"):
        if not isinstance(data, dict):
            violations.append(Violation(file, schema_id, "(root)", "应为 object（键值映射）"))
            return True
        if schema.get("value_key"):
            vals = data.get(schema["value_key"])
            entries = list(vals.items()) if isinstance(vals, dict) else []
        else:
            meta = {"_doc", "version", "_notes"}
            entries = [(k, v) for k, v in data.items() if k not in meta]
        fields = schema.get("value_schema", {})
        tmp_entries = []
        for k, v in entries:
            if isinstance(v, dict):
                tmp_entries.append(v)
            else:
                violations.append(Violation(file, schema_id, "键「%s」" % k,
                                            "映射值应为 object，实际 %s" % _type_of(v)))
        entries = tmp_entries
    else:
        col = schema.get("collection")
        if not isinstance(data, dict) or col not in data:
            if col:
                violations.append(Violation(file, schema_id, "(root)",
                                            "缺少集合键 %s（文件可能不属于本 schema）" % col))
            return True
        entries = data[col] if isinstance(data[col], list) else []
    # 2) 字段校验
    _validate_entries(violations, file, schema_id, entries, fields, is_valid_id, loose, rel=file)
    # 3) 嵌套集合校验
    for nest_name, nest in schema.get("nested", {}).items():
        ncol = nest.get("collection")
        nfields = nest.get("entry_fields", {})
        for entry_no, e in enumerate(entries):
            if not isinstance(e, dict) or ncol not in e:
                if nest.get("required") and e is not None:
                    violations.append(Violation(file, schema_id, "条目#%d" % entry_no,
                                                "缺嵌套集合 %s" % ncol))
                continue
            if not isinstance(e[ncol], list):
                violations.append(Violation(file, schema_id, "条目#%d.%s" % (entry_no, ncol),
                                            "嵌套集合应为 array"))
                continue
            nest_entries = [x for x in e[ncol] if isinstance(x, dict)]
            _validate_entries(violations, file, schema_id, nest_entries, nfields, is_valid_id, rel=file)
    return True


def _validate_csv(file, text, schema, violations):
    schema_id = schema.get("title") or file
    lines = [ln for ln in text.splitlines() if ln.strip() and not ln.startswith("\ufeff")]
    if not lines:
        violations.append(Violation(file, schema_id, "(csv)", "空表"))
        return
    header = [c.strip() for c in lines[0].split(",")]
    want = list(schema["csv"].get("header", []))
    if header != want:
        violations.append(Violation(file, schema_id, "(csv header)",
                                    "表头应为 %s，实际 %s" % (want, header)))
    key_re = schema["csv"].get("key_regex")
    for i, ln in enumerate(lines[1:], start=2):
        cols = ln.split(",")
        if not cols[0].strip():
            violations.append(Violation(file, schema_id, "(csv:%d)" % i, "key 为空"))
        elif key_re:
            try:
                if not re.match(key_re, cols[0].strip()):
                    violations.append(Violation(file, schema_id, "(csv:%d)" % i,
                                                "key「%s」不合形态 %s" % (cols[0], key_re)))
            except re.error:
                pass


def validate_file(root, rel, data):
    """校验单文件（DataSink ② 步复用入口）。data 为已解析 JSON 或原始文本。返回 violations 列表。"""
    violations = []
    schemas = load_schemas(root)
    if not schemas:
        return violations
    is_valid_id = _id_validator()
    rel = rel.replace("\\", "/")
    if rel.startswith(CONFIGS_REL + "/"):
        rel = rel[len(CONFIGS_REL) + 1:]   # 兼容 data_sink 传入的工程根相对路径
    for schema in schemas.get("schemas", {}).values():
        files = schema.get("files", [])
        if not any(fnmatch.fnmatch(rel, f) for f in files):
            continue
        matched = _validate_file_schema(rel, data, schema, is_valid_id, violations)
        if matched:
            break
    return violations


def validate_all(root):
    """全量扫描 data/configs 下五域文件。返回 violations 列表。"""
    violations = []
    schemas = load_schemas(root)
    if not schemas:
        return violations
    is_valid_id = _id_validator()
    cfg = os.path.join(root, CONFIGS_REL)
    if not os.path.isdir(cfg):
        return violations
    for dirpath, _dirs, files in os.walk(cfg):
        for fn in sorted(files):
            rel = os.path.relpath(os.path.join(dirpath, fn), cfg).replace("\\", "/")
            schema = next((s for s in schemas.get("schemas", {}).values()
                           if any(fnmatch.fnmatch(rel, f) for f in s.get("files", []))), None)
            if schema is None:
                continue
            if schema.get("csv"):
                try:
                    with open(os.path.join(dirpath, fn), encoding="utf-8-sig") as f:
                        text = f.read()
                except Exception:
                    continue
                _validate_file_schema(rel, text, schema, is_valid_id, violations)
                continue
            data = _load_json(os.path.join(dirpath, fn))
            if data is None:
                continue
            _validate_file_schema(rel, data, schema, is_valid_id, violations)
    return violations


def main():
    ap = argparse.ArgumentParser(description="Phase 3 Schema 系统构建期校验器")
    ap.add_argument("--root", default=ROOT, help="被扫描工程根（默认本仓）")
    ap.add_argument("--quiet", action="store_true", help="只输出违规行")
    ap.add_argument("--file", help="只校验单文件（相对 data/configs）")
    args = ap.parse_args()
    if args.file:
        path = os.path.join(args.root, CONFIGS_REL, args.file)
        try:
            if args.file.endswith(".csv"):
                with open(path, encoding="utf-8-sig") as f:
                    data = f.read()
            else:
                data = _load_json(path)
        except Exception:
            data = None
        v = validate_file(args.root, args.file, data) if data is not None else \
            [Violation(args.file, "?", "(root)", "文件不可读或非 JSON")]
    else:
        v = validate_all(args.root)
    for item in v:
        print("  ✗ %s" % item)
    if not args.quiet:
        print("Phase 3 Schema 校验：%d 处违规" % len(v))
    return 1 if v else 0


if __name__ == "__main__":
    sys.exit(main())
