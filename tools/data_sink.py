# -*- coding: utf-8 -*-
"""data_sink.py — Studio 写路径唯一 DataSink（15 图 ST-2 六步收口 · 批2，2026-09-06）

ST-2（15 图 V1.4 §ST-2）：所有编辑器写入统一走**单一 DataSink 收口**，固定六步：
  ① ID 校验——03 图白名单正则统一入口（`is_valid_id` 全域形态校验：主正则 +
     ADR-0002 二级形态 extra_patterns，任一命中即合法）+ 退役名单 CP-R02 拒绝。
     规则源 = tools/id_baseline.json + data/configs/_retired_ids.json（双端同源 JSON）。
  ② Schema 校验——05 图 Validation 双通道的运行期端（Python 侧）：
     VA1-REQ-ID（FATAL，内容条目必须有 id）/ VA1-REQ-ADAPTER（ERROR，per_adapter
     必填字段）/ VA4-BINDING（ERROR，对话分片 npc_id 非空，工具侧只校验不代填）。
     规则源 = data/configs/content_validation_rules.json（与 GDScript 运行期同读一份）。
  ③ _backup 留底——写前快照入 `<root>/.sink_backups/`（带时间戳，step⑤ 回滚依据）。
  ④ 落盘——tmp + os.replace 原子写；JSON 统一 ensure_ascii=False + indent=2。
  ⑤ ref_index 增量反查——写后即时悬空检测（ref_index.build/check，05 图 VA3-DANGLING）：
     仅拦截「本次写入新引入」的悬空引用，违例即回滚并提示，不等 GATE6 兜底。
  ⑥ change_log 留痕——tools/change_log.py add_row（best-effort，日志设施异常不阻断写盘）。

边界（与 15 图对齐）：
  - DataSink 抽象层先行于任何目录迁移（ADR-0003 落位时只改根路径，写路径零改动）。
  - ①② 仅对 data/configs 下的内容写生效；⑤ 仅对 data/configs/**/*.json 生效；
    Studio 自身设施（settings/log/trash）不经本口。
  - 多工程：root 为被编辑工程根，契约 JSON 缺失时回退本仓真源（宪法资产随工具走）。
用法：
  from data_sink import write_json, write_text, SinkRejected
  write_json(project_root, "<abs or root-rel path>", data, note="保存 NPC")
"""
import datetime
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
if HERE not in sys.path:
    sys.path.insert(0, HERE)

ID_BASELINE = os.path.join(HERE, "id_baseline.json")
BACKUP_DIRNAME = ".sink_backups"
CONFIGS_REL = os.path.join("data", "configs")

# 内容集合键（VA1-REQ-ID 扫描面：键 id 的值 = 定义候选；id_validator 同口径的写侧子集）
COLLECTION_KEYS = {
    "npcs", "quests", "items", "battles", "enemies", "skills",
    "shards", "status_effects", "recipes", "materials", "regions",
}

_SCHEMA_CACHE = {}
_changelog_enabled = True   # 测试驱动可置 False 静默 ⑥（step⑥ 留痕开关）
_changelog_enabled = True   # 测试驱动可置 False 静默 ⑥（step⑥ 留痕开关）


class SinkRejected(Exception):
    """六步校验未过（step: 失败步骤名；problems: 违例描述列表）。写盘未发生或已回滚。"""

    def __init__(self, step, problems):
        self.step = step
        self.problems = list(problems)
        super(SinkRejected, self).__init__(
            "[DataSink:%s] %s" % (step, "；".join(self.problems[:8])))


def _load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _under(path, parent):
    try:
        return os.path.commonpath([os.path.abspath(path), os.path.abspath(parent)]) \
            == os.path.abspath(parent)
    except ValueError:
        return False


def _rel(root, path):
    return os.path.relpath(os.path.abspath(path), os.path.abspath(root)).replace("\\", "/")


def _abs(root, target):
    return target if os.path.isabs(target) else os.path.join(root, target)


# ---------------------------------------------------------------- ① ID 校验
def load_id_contract():
    """03 §3.3 冻结正则 + ADR-0002 二级形态（extra_patterns）+ 退役名单，双端同源 JSON。"""
    base = _load_json(ID_BASELINE, {}) or {}
    pats = [base.get("pattern", "")] + list(base.get("extra_patterns", []))
    compiled = []
    for p in pats:
        if p:
            try:
                compiled.append(re.compile(p))
            except re.error:
                pass
    retired = set()
    rd = _load_json(os.path.join(REPO_ROOT, "data", "configs", "_retired_ids.json"), {}) or {}
    for r in rd.get("retired", []):
        if isinstance(r, dict) and r.get("id"):
            retired.add(str(r["id"]))
        elif isinstance(r, str):
            retired.add(r)
    return compiled, retired


def is_valid_id(eid, compiled=None):
    """_is_valid_id 全域形态校验（ST-2 ①：03 图白名单正则统一入口）。"""
    if not isinstance(eid, str) or not eid:
        return False
    if compiled is None:
        compiled, _ = load_id_contract()
    return any(p.match(eid) for p in compiled)


def extract_candidate_ids(data):
    """从待写数据提取定义候选 ID：根 id + 集合键元素 id（id_validator 写侧子集口径）。"""
    out = []
    if isinstance(data, dict):
        if isinstance(data.get("id"), str) and data["id"]:
            out.append(data["id"])
        for k, v in data.items():
            if k in COLLECTION_KEYS and isinstance(v, list):
                for el in v:
                    if isinstance(el, dict) and isinstance(el.get("id"), str) and el["id"]:
                        out.append(el["id"])
    return out


# ---------------------------------------------------------------- ② Schema 校验
def load_schema_rules(root):
    """05 图规则表双端同读：目标工程缺失时回退本仓真源。"""
    key = os.path.abspath(root)
    if key in _SCHEMA_CACHE:
        return _SCHEMA_CACHE[key]
    rules = _load_json(os.path.join(root, CONFIGS_REL, "content_validation_rules.json"))
    if not rules:
        rules = _load_json(os.path.join(REPO_ROOT, CONFIGS_REL, "content_validation_rules.json"))
    _SCHEMA_CACHE[key] = rules or {}
    return _SCHEMA_CACHE[key]


def _entry_kind(rel, data):
    r = rel.lower()
    if "/abilities/" in r or (isinstance(data, dict) and "skills" in data):
        return "ability"
    if "/items/" in r or (isinstance(data, dict) and "items" in data and "/regions/" not in r):
        return "item"
    if "/dialogs/" in r or (isinstance(data, dict) and "lines" in data):
        return "dialog"
    return ""


def _content_entries(data):
    """摊平内容条目：根实体自身 + 集合键元素。"""
    entries = []
    if isinstance(data, dict):
        if "id" in data:
            entries.append(data)
        for k, v in data.items():
            if k in COLLECTION_KEYS and isinstance(v, list):
                entries.extend(el for el in v if isinstance(el, dict))
    return entries


def step2_schema_check(root, rel, data):
    """05 图 VA-3 处置表对齐：FATAL 拒写；ERROR/WARN 登记放行（warns，stderr 提示）。
    依据：D1 批注「ERROR=登记不拒载，数据治理补齐后升 FATAL」+ C-3 追认
    「对话分片 npc_id 空置=Dialogue 主权，工具侧只校验不代填」——ERROR 不拦写。"""
    items = []   # (severity, message)
    rules = load_schema_rules(root)
    if not rules:
        return [], []
    kind = _entry_kind(rel, data)
    entries = _content_entries(data)

    def sev(code):
        for l in rules.get("layers", []):
            for r in l.get("rules", []):
                if r.get("rule_code") == code:
                    return r.get("severity", "ERROR")
        return "ERROR"

    # VA1-REQ-ID（FATAL：缺 id 的内容条目不得落盘）
    s_id = sev("VA1-REQ-ID")
    for i, e in enumerate(entries):
        if not isinstance(e.get("id"), str) or not e["id"]:
            items.append((s_id, "VA1-REQ-ID(%s): 内容条目 #%d 缺 id" % (s_id, i)))
    # VA1-REQ-ADAPTER（ERROR=登记放行，VA-3 处置表）
    for l in rules.get("layers", []):
        for r in l.get("rules", []):
            if r.get("rule_code") == "VA1-REQ-ADAPTER" and kind and r.get("required_fields_by_kind"):
                req = r["required_fields_by_kind"].get(kind, [])
                for i, e in enumerate(entries):
                    for f in req:
                        if f not in e:
                            items.append(("ERROR", "VA1-REQ-ADAPTER(%s): %s 条目 #%d 缺必填字段 %s"
                                          % (sev("VA1-REQ-ADAPTER"), kind, i, f)))
    # VA4-BINDING（ERROR=登记放行：npc_id 空置=C-3 Dialogue 主权，工具只校验不代填不拒载）
    if kind == "dialog" and isinstance(data, dict) and "lines" in data:
        if not data.get("npc_id"):
            items.append((sev("VA4-BINDING"),
                          "VA4-BINDING(%s): 对话分片 npc_id 空置（C-3 Dialogue 主权，登记放行；归属由对话域裁定）"
                          % sev("VA4-BINDING")))
    # Phase 3 Schema 系统（03 §6.3 / 整改报告 Phase 3）：字段级校验（content_schemas.json 真源）。
    # 与构建期 schema_validator.py 同源（同一份 JSON），写路径 FATAAL 拒写（正式内容必须 Schema PASS）。
    try:
        from schema_validator import validate_file as _schema_validate_file
        for v in _schema_validate_file(root, rel, data):
            items.append(("FATAL", "VA1-SCHEMA: %s" % v))
    except Exception:
        pass  # Schema 系统不可用时降级为既有 VA1-REQ-ID/ADAPTER（不阻断既有写路径）
    hard = [m for s, m in items if s == "FATAL"]
    warns = [m for s, m in items if s != "FATAL"]
    return hard, warns


# ---------------------------------------------------------------- ③④⑤ 六步本体
def _backup(root, rel):
    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    bdir = os.path.join(root, BACKUP_DIRNAME, os.path.dirname(rel))
    os.makedirs(bdir, exist_ok=True)
    src = os.path.join(root, rel)
    dst = os.path.join(bdir, "%s_%s" % (ts, os.path.basename(rel)))
    if os.path.exists(src):
        shutil.copy2(src, dst)
        return dst
    return None


def _ref_dangling(root):
    """ref_index 增量反查（返回悬空集合；ref_index 不可用/范围外 = 空集放行）。"""
    try:
        import ref_index
        defs, refs = ref_index.build(root)
        dangling, _warned, _known = ref_index.check(defs, refs)
        return {(k, f, t) for (k, f, t, _fp) in dangling}
    except Exception:
        return set()


def _changelog(rel, note, source):
    if not _changelog_enabled:
        return
    try:
        import change_log
        change_log.add_row(commit="", module=source or "studio", scope=rel,
                           what=note or "DataSink 写入", impact="DataSink 六步收口",
                           ref="15图ST-2")
    except Exception as e:
        sys.stderr.write("[DataSink] change_log 留痕失败（不阻断写盘）: %s\n" % e)


def _check_configs_json(root, rel, data, compiled, retired):
    """①+②（仅 data/configs 下内容写生效）。返回 (hard_problems, warns)。"""
    hard, warns = [], []
    if not _under(os.path.join(root, rel), os.path.join(root, CONFIGS_REL)):
        return hard, warns
    # ① ID 形态 + 退役复用
    for eid in extract_candidate_ids(data):
        if eid in retired:
            hard.append("CP-R02: 退役 ID 复用违例「%s」（永不复用）" % eid)
        elif not is_valid_id(eid, compiled):
            hard.append("CP-R01: ID「%s」不合 03§3.3 白名单形态" % eid)
    # ② Schema
    h2, w2 = step2_schema_check(root, rel, data)
    hard.extend(h2)
    warns.extend(w2)
    return hard, warns


def write_json(root, target, data, note="", source="studio"):
    """六步收口写 JSON。root=被编辑工程根；target=绝对路径或 root 相对路径。"""
    path = _abs(root, target)
    rel = _rel(root, path)
    compiled, retired = load_id_contract()
    hard, warns = _check_configs_json(root, rel, data, compiled, retired)
    if hard:
        raise SinkRejected("①②ID/Schema", hard)

    in_configs = _under(path, os.path.join(root, CONFIGS_REL)) and rel.endswith(".json")
    pre_dangling = _ref_dangling(root) if in_configs else set()

    backup = _backup(root, rel)                       # ③
    existed = os.path.exists(path)
    os.makedirs(os.path.dirname(path) or root, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:   # ④
            json.dump(data, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except Exception:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise

    if in_configs:                                    # ⑤ 增量反查
        post_dangling = _ref_dangling(root)
        introduced = {(k, f, t) for (k, f, t) in post_dangling - pre_dangling}
        if introduced:
            if backup and existed:                    # 回滚
                shutil.copy2(backup, path)
            elif not existed:
                try:
                    os.remove(path)
                except OSError:
                    pass
            raise SinkRejected("⑤ref_index 增量反查", [
                "本次写入新引入悬空引用 %d 处（已回滚）：" % len(introduced)]
                + ["  [%s] %s → %s" % (k, f, t) for (k, f, t) in sorted(introduced)[:10]])

    _changelog(rel, note, source)                     # ⑥
    for w in warns:
        sys.stderr.write("[DataSink][WARN] %s: %s\n" % (rel, w))
    return {"rel": rel, "backup": backup, "warns": warns}


def write_text(root, target, text, note="", source="studio", encoding="utf-8"):
    """六步收口写文本（CSV 等）：①② 仅在内容可解析为 JSON 时适用，③~⑥ 恒走。"""
    path = _abs(root, target)
    rel = _rel(root, path)
    payload = None
    if rel.endswith(".json"):
        try:
            payload = json.loads(text)
        except Exception:
            raise SinkRejected("④落盘", ["非合法 JSON 文本：%s" % rel])
    if payload is not None:
        compiled, retired = load_id_contract()
        hard, warns = _check_configs_json(root, rel, payload, compiled, retired)
        if hard:
            raise SinkRejected("①②ID/Schema", hard)
    else:
        warns = []

    in_configs = _under(path, os.path.join(root, CONFIGS_REL)) and rel.endswith(".json")
    pre_dangling = _ref_dangling(root) if in_configs else set()

    backup = _backup(root, rel)                       # ③
    existed = os.path.exists(path)
    os.makedirs(os.path.dirname(path) or root, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:   # ④
            f.write(text)
        os.replace(tmp, path)
    except Exception:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise

    if in_configs:                                    # ⑤
        post_dangling = _ref_dangling(root)
        introduced = post_dangling - pre_dangling
        if introduced:
            if backup and existed:
                shutil.copy2(backup, path)
            elif not existed:
                try:
                    os.remove(path)
                except OSError:
                    pass
            raise SinkRejected("⑤ref_index 增量反查", [
                "本次写入新引入悬空引用 %d 处（已回滚）" % len(introduced)])

    _changelog(rel, note, source)                     # ⑥
    return {"rel": rel, "backup": backup, "warns": warns}
