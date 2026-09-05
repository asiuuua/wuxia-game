# APPROVAL 2026-09-06：FROZEN 批准与 Phase1 开工记录

- **性质**：架构 Owner（用户）批准与开工授权的正式留痕，全部施工以本文为凭。
- **批准一（冻结）**：2026-09-05 用户指令「批准 02~18 FROZEN CANDIDATE 升 FROZEN」（当时暂停未落地，2026-09-06 补办状态行，17 份全部升 **FROZEN**）。
- **批准二（开工）**：2026-09-06 用户指令原文：「你现在根据现有的宪法规范和1-18文件，来进行把游戏的重构整改进行逐一落地」。解释与边界：
  1. ACR-0001 依此转 `APPROVED`，按各图 §4 迁移映射分阶段实施（绞杀者分批，每 Phase 可停）。
  2. 各图开放问题带推荐项按**推荐默认执行**（如 RH-1 版本 0.5.0 起步、RH-3 死常量直接退役）；ADR 级裁决（ADR-0002 ID 格式、nv/mt 前缀迁移等 Phase3~4 项）实施前仍单独请示。
  3. 旧存档必须可用（宪法 §32）为不可破红线；每次提交过双闸门（GATE1 零解析 + GATE2 失败 0）+ verify_all。

## Phase1 施工范围（2026-09-06 本批）

| 项 | 蓝图依据 | 内容 |
|---|---|---|
| 版本唯一真源 | 18 图 RH-1 §4 Phase1 | project.godot 补 `application/config/version="0.5.0"` |
| 死常量退役 | 18 图 P-RH8 / RH-3 推荐 | 删 GameConstants.SAVE_VERSION（零消费复核 2026-09-06） |
| 迁移登记口 | 13 图 SV-3 / P-S1 Phase1 | SaveManager 公开 `register_migration({from,to,step})`；patch_manager 弃 has_method 死探测改直连登记 |
| 旧注释退役 | 18 图 Phase1「修注释」 | patch_manager「规范 §4.7」、error_handler「§4.2.3」旧编号注释清理 |
| 退役名单 | 16 图 CP-1 | `data/configs/_retired_ids.json` 建立 + 首登记（town_npcs 体系，实体以 git 历史与区域真源差集为准） |
| ID 基线 | 16 图 CP-2b | `tools/id_baseline.json` 冻结存量违例快照（03 §3.3 冻结正则，基线外零容忍/基线内只减不增） |

## 遗留债登记（非本批）

- MainMenu/Bootstrap 版本显示改读真源 = 18 图 §4 **Phase2**（随构建脚本注入 Build 日期）。
- id_validator 挂 GATE06 = 16 图 CP-5 **Phase2**（基线文件本批先冻结）。
- desktop_studio 工程标记检测仍依赖 town_npcs.json 存在性（studio_core.py L118/L129）= 16 图 CP-1b 关联债，随工作室域整改。
- patch manifest `save_migration` 契约冻结为 SV-3 条目格式（字符串旧格式拒收并响报）；补丁体系本体 = Phase2+。
