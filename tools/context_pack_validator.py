# -*- coding: utf-8 -*-
"""context_pack_validator.py — GATE30 Context Integrity & Freshness（宪法 0-G.5/0-G.6，C2②③ 2026-09-06）

物理槽 GATE42（双命名空间纪律：新物理槽 40+，LN-G30 → GATE42，禁裸引物理号）。

职责（宪法 0-G.6：Context Pack 必须携带六字段，与 Freeze Manifest 不一致 → STALE；
STALE Context 不得用于 Foundation 修改）：
  ① 从工程真源生成/校验 docs/context_pack.json 六字段：
     constitution_version / architecture_version / contract_versions / schema_versions /
     save_schema_version / verified_revision
  ② 与 Freeze Manifest（本仓真源版本指纹）一致性校验——不一致即 STALE 红
  ③ GATE21~32 硬性验收对账（01 图 §127 直修）：docs/PROJECT_STATUS.md 必须存在且
     覆盖当前 verify_all 物理槽清单（Gate 状态单一真源，防纸面门禁）

用法:
  python tools/context_pack_validator.py              # 校验模式（verify_all 挂槽）
  python tools/context_pack_validator.py --generate   # 生成/刷新 context_pack.json（真源变更后手动）
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACK_PATH = os.path.join(ROOT, "docs", "context_pack.json")

CONSTITUTION = os.path.join(ROOT, "docs", "constitution", "PROJECT_CONSTITUTION_V1.4.md")
ARCH_01 = os.path.join(ROOT, "docs", "architecture", "01_总体架构施工图_V1.4修复版.md")
PROJECT_STATUS = os.path.join(ROOT, "docs", "PROJECT_STATUS.md")
SAVE_MANAGER = os.path.join(ROOT, "autoload", "SaveManager.gd")

# 施工厂 V1.4 修复版清单（contract_versions/schema_versions 的载体指纹）
V14_DOCS = [
    "docs/architecture/01_总体架构施工图_V1.4修复版.md",
    "docs/architecture/02_Domain_Kernel施工图_V1.4修复版.md",
    "docs/architecture/03_Contract_Schema_DataContract施工图_V1.4修复版.md",
    "docs/architecture/04_Test_Infrastructure_Architecture_Gate施工图_V1.4修复版.md",
    "docs/architecture/05_Content_Registry_Content_Pipeline施工图_V1.4修复版.md",
    "docs/architecture/06_Actor_Player_NPC施工图_V1.4修复版.md",
    "docs/architecture/07_World_Time_Schedule施工图_V1.4修复版.md",
    "docs/architecture/08_Relationship_Faction施工图_V1.4修复版.md",
    "docs/architecture/09_Item_Inventory_Equipment施工图_V1.4修复版.md",
    "docs/architecture/10_Economy_Shop_Crafting施工图_V1.4修复版.md",
    "docs/architecture/11_Ability_Combat_CombatAI施工图_V1.4修复版.md",
    "docs/architecture/12_Quest_Dialogue_Story施工图_V1.4修复版.md",
    "docs/architecture/13_Save_Persistence_Migration施工图_V1.4修复版.md",
    "docs/architecture/14_Presentation_Input_ViewModel施工图_V1.4修复版.md",
    "docs/architecture/15_Studio_Authoring_Validator_Preview施工图_V1.4修复版.md",
    "docs/architecture/16_Content_Production施工图_V1.4修复版.md",
    "docs/architecture/17_Simulation_Balance_Performance施工图_V1.4修复版.md",
    "docs/architecture/18_Release_Hardening_Compatibility_Migration施工图_V1.4修复版.md",
]

violations = []
notes = []


def _doc_fingerprint(path: str) -> str:
    try:
        with open(path, "rb") as f:
            import hashlib
            return hashlib.sha256(f.read()).hexdigest()[:16]
    except OSError:
        return "MISSING"


def _git_head() -> str:
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                             encoding="utf-8", timeout=10)
        return out.stdout.strip()[:12] if out.returncode == 0 else "no-git"
    except (OSError, subprocess.TimeoutExpired):
        return "no-git"


def _save_schema_version() -> str:
    try:
        with open(SAVE_MANAGER, encoding="utf-8") as f:
            for ln in f:
                m = re.match(r'^const SAVE_VERSION\s*:?=\s*"([^"]+)"', ln.strip())
                if m:
                    return m.group(1)
    except OSError:
        pass
    return "MISSING"


def build_truth() -> dict:
    """从工程真源构造 Context Pack 应然值（Freeze Manifest 指纹）。"""
    contracts = {}
    for rel in V14_DOCS:
        contracts[os.path.basename(rel)] = _doc_fingerprint(rel)
    return {
        "constitution_version": "V1.4" if os.path.exists(CONSTITUTION) else "MISSING",
        "architecture_version": ("01_V1.4修复版" if os.path.exists(ARCH_01) else "MISSING")
                                + "#" + _doc_fingerprint(ARCH_01),
        "contract_versions": contracts,
        "schema_versions": {"content_pack_manifest": _doc_fingerprint(
            os.path.join(ROOT, "data", "configs", "pack_manifest.json"))},
        "save_schema_version": _save_schema_version(),
        "verified_revision": _git_head(),
    }


def main() -> int:
    generate = "--generate" in sys.argv
    truth = build_truth()

    if generate or not os.path.exists(PACK_PATH):
        with open(PACK_PATH, "w", encoding="utf-8") as f:
            json.dump(truth, f, ensure_ascii=False, indent=2, sort_keys=True)
        notes.append("context_pack.json 已生成/刷新（verified_revision=%s）" % truth["verified_revision"])

    with open(PACK_PATH, encoding="utf-8") as f:
        pack = json.load(f)

    # ① 六字段齐备（0-G.5）
    required = ["constitution_version", "architecture_version", "contract_versions",
                "schema_versions", "save_schema_version", "verified_revision"]
    for k in required:
        if k not in pack:
            violations.append("[G30] Context Pack 缺字段 %s（0-G.5）" % k)

    # ② Freeze Manifest 一致性（0-G.6：不一致 = STALE，禁 Foundation 修改）
    # verified_revision 为留痕字段（每次提交必然前进），不参与 STALE 判定；
    # STALE 只看内容版本字段（版本号/指纹）。
    stale = []
    for k in required:
        if k == "verified_revision":
            continue
        if k in pack and pack[k] != truth[k]:
            stale.append(k)
    if pack.get("verified_revision") != truth["verified_revision"]:
        notes.append("verified_revision 落后于 HEAD（%s → %s），--generate 可刷新（仅留痕，不判 STALE）"
                     % (pack.get("verified_revision"), truth["verified_revision"]))
    if stale:
        violations.append(
            "[G30] STALE：Context Pack 与真源不一致：%s —— 先跑 --generate 刷新，"
            "STALE 期间禁 Foundation 修改（0-G.6）" % ", ".join(stale))

    # ③ GATE21~32 硬性验收对账（01 §127 直修：Gate 状态单一真源必须覆盖物理槽清单）
    if not os.path.exists(PROJECT_STATUS):
        violations.append("[G127] docs/PROJECT_STATUS.md 缺失——GATE21~32 硬性验收无状态真源")
    else:
        with open(PROJECT_STATUS, encoding="utf-8") as f:
            ps = f.read()
        for slot in ["GATE21", "GATE22", "GATE26", "GATE27", "GATE28", "GATE30", "GATE32",
                     "GATE25", "GATE03", "GATE23", "GATE24", "GATE11"]:
            if slot not in ps:
                violations.append("[G127] PROJECT_STATUS 缺 %s 状态行（硬性验收对账不完整）" % slot)

    print("context_pack_validator · GATE30（物理槽 GATE42，0-G.5/0-G.6 + 01§127 对账）")
    for n in notes:
        print("  ℹ " + n)
    if violations:
        for v in violations:
            print("  ✗ " + v)
        print("════ 结论：✗ STALE/对账失败 %d 项 ════" % len(violations))
        return 1
    print("════ 结论：✓ Context Fresh（六字段齐备 / Freeze 一致 / Gate 对账完整）════")
    return 0


if __name__ == "__main__":
    sys.exit(main())
