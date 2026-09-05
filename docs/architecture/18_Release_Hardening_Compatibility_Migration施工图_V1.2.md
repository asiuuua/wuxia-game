# 18 Release Hardening / Compatibility / Migration Verification 施工图 V1.2

> 状态：FROZEN（2026-09-06 用户以架构 Owner 批准；已开工）
> 序列位置：宪法 §128 Phase A 施工图序列 **18/18（收官）**；依据宪法 L5973 点名《18 Release Hardening / Compatibility / Migration Verification》。
> 证据基线：2026-09-05 全库实扫（project.godot / patch_manager / SaveManager / error_handler / game_constants / EventBus / MainMenu / tools / export 配置存在性 / 触摸适配面 / 13 图 SV 锚 / 宪法 §32·§130·§211·§212·§214）。
> 铁律：本图只产出文档与契约，**不动任何生产源码**；施工范围待 ACR-0001 Phase0-6 用户批准。

---

## §0 命名空间与撞号声明

- 本图契约编号 **RH-1~RH-8**；实锤缺陷 **P-RH1~P-RH10**；Enforcement **RH-R01~RH-R12**。
- **撞号检查**：01(T) / 02(I·O·K-DB·K-R) / 03(C-R·S-1~6) / 04(门禁族 GATE) / 05(CT·CO·VA·PK·VE·DM·C) / 06(AC) / 07(WT) / 08(RF) / 09(IE) / 10(EC) / 11(AB) / 12(QD) / 13(SV) / 14(PV) / 15(ST) / 16(CP) / 17(SBP)。**RH 无撞号**；P-RH / RH-R 同样无撞号。
- **引用不接管声明**：
  - 存档迁移链**定义权在 13 图**（SV-3 显式注册表 / register_migration / 未知版本拒读 / golden 对）；本图只做其**发布级验证产物化**（RH-5）。
  - `patch_manager` 死接线修复（P-S1）归 13 图 SV-3 Phase1（随 12 图 QD-6 has_method 防线同批）；本图只冻结补丁发布物契约（RH-8 附带）。
  - EventBus 信号契约归 02 图；`patch_applied` 死信号是否清理由 02/GATE0b 基线管辖，本图登记观测（P-RH7）。
  - 错误通知的 UI 字符串本地化归 14 图（PV 域）；本图只管错误处理**发布面**（RH-6）。
  - ID 校验（GATE06）归 16 图；性能基准双 PASS（GATE40+）归 17 图；本图把它们纳入 Release Gate **清单编排**，不重定义。
  - 工作室工具打包链（PyInstaller）归 15 图 / desktop-studio skill；本图只管**游戏本体**发布链。

---

## §1 定位与宪法锚

本图是序列最后一份横向收口图：**把前 17 份冻结契约收拢为"可以放心发货"的验证面**。三个域：

1. **Release Hardening（发布加固）**：版本真源、Build 追溯、导出配置、发布门禁。
2. **Compatibility（兼容治理）**：兼容等级声明、数据兼容四考虑、弃用流程。
3. **Migration Verification（迁移验证）**：旧存档红线在**发布产物级**的机器验证。

宪法锚（全读实锤）：
- **§32 Save Migration 原则**（L2979-2994）：「禁止：旧存档不能用了，除非经过明确版本策略」——迁移链 v1→v2→v3→Current；**每次 Migration 必须测试 Input / Expected Output**。本图 RH-5 将此要求机器化。
- **§130 数据兼容原则**（L4667-4678）：修改字段/枚举/ID/结构必须考虑旧 Content / 旧 Save / DLC / Mod。
- **§211 Compatibility Policy**（L6201-6233）：长期公共结构必须声明兼容等级 **BACKWARD_COMPATIBLE / FORWARD_TOLERANT / BREAKING**；涉及 Command DTO / Event Payload / Repository Contract / Content Schema / Save DTO / Module Manifest / Content Pack Manifest 七类；**BREAKING 五要求**：Version Bump、Migration、Compatibility Test、Affected Consumer Scan、Rollback Plan；「增加一个字段不能自动假设兼容」。
- **§212 Deprecation Policy**（L6235-6253）：ACTIVE → DEPRECATED → MIGRATION WINDOW → REMOVED；DEPRECATED 必须记录 replacement / deprecated_since / removal_not_before / migration_guide / affected_consumers；**禁止同一提交中无迁移地删除广泛使用的 STABLE API**。
- **§214 Build / Content Provenance**（L6273-6284）：正式 Build 与 Content Package 必须可追溯八字段：build_id / source_revision / game_version / constitution_version / architecture_version / content_version / schema_version / save_schema_version。
- **§216**（L6321-6337）：性能超 Release Budget = FUNCTIONAL PASS 而非 RELEASE PASS（17 图 GATE40+ 承接，本图编排进 Release Gate）。
- **§230 VS-001**：热更/补丁机制不在第一阶段禁止项内（禁的是 NPC 社会模拟/全量多线程），patch_manager 骨架可 FROZEN 保留。

---

## §2 资产盘点与实锤

### 2.1 资产表（发布/兼容/迁移域，全部实扫）

| # | 资产 | 现状证据 | 判定 |
|---|------|---------|------|
| 1 | `project.godot` | 65 行；config_version=5；features ("4.7","GL Compatibility")；**18 个 Autoload**（L24-41）；`PerformanceMonitor` 直挂 `res://tools/performance_monitor.gd`（L38，tools 层文件作 Autoload=分层越位）；渲染 `gl_compatibility` 桌面+mobile 双端（L62-63）；stretch canvas_items/expand 1920×1080 min 960×540；**无 `application/config/version` 字段** | 好坏参半 |
| 2 | `export_presets.cfg` | **不存在**（项目根 Glob 零命中） | 缺失 |
| 3 | `autoload/SaveManager.gd` | SAVE_VERSION "1.1.0"（L8，2026-09-04 last_region_id 升版）；L3 自注「存档版本号独立于游戏版本号」；`_migrations` **空数组**（L13-15）；L243 注释自认「1.0.0→1.1.0 无破坏性结构变化（last_region_id 由 GameState.load 默认值兜底）」；未来版本拒读（L233-234）/无版本遗留兼容/L240-242 未知版本 warn 后**盖章放行**；原子写 .tmp + .bak 备份回退（L18-19, L195-201）；MAX_SLOTS=6 | 正资产+隐患 |
| 4 | `tests/unit/test_save_migration.gd` | 6 用例：当前版本直通/无版本迁移/1.0.0 迁移/未来版本拒绝 等 | 正资产 |
| 5 | `core/patch_manager.gd` | 81 行热更骨架；L2 引「规范 §4.7」（**V1.2 宪法无此编号**）；patch 目录=exe 同级 /patches/；L42 版本真源=`ProjectSettings.get_setting("application/config/version","0.0.0")` → **永远拿 0.0.0**；L52 `has_method("register_migration")` 探测不存在方法（13 图 P-S1 死接线同源确认）；L57 emit patch_applied；manifest 契约字段 min_game_version/save_migration/version | FROZEN 候选 |
| 6 | `user://patch_history.json` | 运行时产物（patch_manager L71-80）；仓库无静态文件；13 图 SV-6 已归入 user:// 五域 PatchManager 名下 | 正常 |
| 7 | `core/constants/game_constants.gd` | `SAVE_VERSION := "1.0.0"`（L7）——**全库零消费 + 与 SaveManager 1.1.0 撞名**；同文件 MAX_PLAYER_LEVEL/TARGET_FPS 等有消费 | 死常量 |
| 8 | `scenes/ui/screens/main_menu/MainMenu.gd` | `VERSION_TEXT := "v0.5.0 Build 20250827"`（L17）硬编码；L319/L454 两处渲染（版本行+关于页）；Build 日期 2025-08-27 已过期一年 | 硬编码 |
| 9 | `scenes/bootstrap/Bootstrap.gd` | `BOOTSTRAP_VERSION := "1.0.0"`（L8）；L92 启动日志 `游戏服务已就绪 (v%s)` | 第三处版本常量 |
| 10 | `autoload/error_handler.gd` | 37 行三级兜底：FATAL 弹窗+退出 / ERROR 日志+通知 / WARN 日志（L15-25）；L2 引「规范 §4.2.3」旧编号；FATAL 弹窗文案**不含版本号与日志路径**（L30） | 正资产+小缺 |
| 11 | `core/utils/game_logger.gd` | L73 日志头记 `Engine.get_version_info()`（**引擎版本非游戏版本**）；启动无 provenance 行 | 小缺 |
| 12 | `tools/performance_monitor.gd` | L18 `if not OS.has_feature("debug")` ——全库**唯一** OS.has_feature 调用 | 正资产 |
| 13 | `EventBus.gd` L150 | `signal patch_applied(patch_id, version)`：声明+patch_manager 唯一 emit+**零 connect** | 死信号 |
| 14 | `autoload/save_validator.gd` | 读档后修复器（订阅 game_loaded）；与 13 图 SV-7 定位一致 | 正资产（13 图管） |
| 15 | `tools/export_ai_context.py` | tools 全库唯一 "export" 脚本=AI 上下文导出，**非游戏构建**；PyInstaller 链属工作室 exe（15 图/桌面工具域） | 非发布链 |
| 16 | `data/runtime/item_instance.gd` | `SCHEMA_VERSION := 1`（L18）+ `"ver"` 字段落档（L22）——DTO 自版本先例，13 图 SV-2 同源 | 正资产 |

### 2.2 实锤缺陷（P-RH1~P-RH10）

- **P-RH1【P0·游戏版本真源碎片化×4+1缺】** 「游戏版本号」当前有四个互相矛盾的书写处 + 一处缺失：① `project.godot` 缺 `application/config/version`（patch_manager L42 兜底 "0.0.0"，补丁版本校验**形同虚设**）；② MainMenu L17 `v0.5.0 Build 20250827`；③ Bootstrap L8 `BOOTSTRAP_VERSION "1.0.0"`；④ game_constants L7 `SAVE_VERSION "1.0.0"`（死常量）；真源候选仅 SaveManager SAVE_VERSION 合法（但那是**存档**版本，SaveManager L3 明确两者独立）。任何一处展示/校验都与其余不符。SaveManager L3 已立的「存档版本独立」原则**正确且保留**——缺的是游戏版本自己的唯一真源。
- **P-RH2【P0·零导出配置】** `export_presets.cfg` 不存在。项目宣称平台 Win+安卓，但**从未配置过任何导出预设**——发布能力为零，双平台目标目前只是口号。
- **P-RH3【P1·Provenance 八字段全缺】** §214 要求的 build_id / source_revision / game_version / constitution_version / architecture_version / content_version / schema_version / save_schema_version 无一处记录；无 provenance 生成物；GameLogger 启动行只记引擎版本。当前任何一个 exe/json 都无法回答「我从哪份源码哪个配置构建而来」。
- **P-RH4【P1·平台适配零证据】** 全库 `OS.has_feature` 仅 performance_monitor L18 一处（debug 门禁，合理保留）；grep InputEventScreenTouch / emulate_mouse / 虚拟键盘 **全库零命中**——触摸输入、安卓返回键、权限声明、移动端 UI 适配**无任何一行代码**。GL Compatibility 渲染底座（project.godot L62-63）与 stretch 自适应是仅有的平台正资产。
- **P-RH5【P1·游戏本体零构建发布脚本】** tools 全库无 build/package/export/release 游戏脚本（唯一 export_ai_context.py 是 AI 工具）；15 图管辖的工作室打包链不覆盖游戏本体。发布链在 18 号之前**无人接管**。
- **P-RH6【P2·旧规范编号引用残留】** patch_manager L2「规范 §4.7」、error_handler L2「规范 §4.2.3」——V1.2 宪法无这些编号，代码-宪法失联；修复时一并更新为真实条款号（error_handler → §33/错误域相关，patch_manager → 本图 RH-8）。
- **P-RH7【P2·patch_applied 死信号】** EventBus L150 声明、patch_manager L57 唯一 emit、全库零 connect。GATE0b 基线范围；补丁发布物若要有「已应用补丁」UI 呈现需消费方（归 14 图 PV），或退役该信号（归 02 图裁决）。
- **P-RH8【P2·GameConstants.SAVE_VERSION 死常量撞名】** 与 SaveManager.SAVE_VERSION 同名不同值（1.0.0 vs 1.1.0），零消费——今天无害，明天有人 `GameConstants.SAVE_VERSION` 就埋雷。处理：退役或改为转发（开放问题 RH-3）。
- **P-RH9【P1·迁移验证无发布级产物】** 迁移骨架健康（资产 3/4/16），但 §32「每次 Migration 必须测试 Input/Expected Output」目前只有 6 个单元用例，**没有 golden 样本档产物**：无「老档样本集→期望输出」回归文件，无发布前「老档读入验证」步骤。13 图 SV-3 golden 对尚未落地；本图把它产物化并挂进 Release Gate（RH-5）。
- **P-RH10【P2·版本显示双轨+过期】** MainMenu L319/L454 两处渲染同一硬编码常量，Build 日期 20250827 已过期一年；Bootstrap 启动日志又是另一个版本号。玩家看到的版本、日志里的版本、补丁校验用的版本三者互不相认（P-RH1 的表象层）。

---

## §3 冻结契约（RH-1~RH-8）

### RH-1 游戏版本唯一真源（P-RH1/P-RH10 收口）
- 唯一真源 = **`ProjectSettings` 的 `application/config/version`**（project.godot 补字段，初始值 `0.5.0`，与 MainMenu 现显示对齐；SemVer 三段，随 03 图统一 SemVer 契约）。
- 读取规则：任何代码需要游戏版本一律 `ProjectSettings.get_setting("application/config/version")`（或经 Bootstrap 启动时读入的 `GameVersion` 单例常量，Phase3 归 Kernel 装配）。
- **禁止**再新增任何硬编码版本字符串常量：MainMenu VERSION_TEXT / Bootstrap BOOTSTRAP_VERSION 全部改读真源；版本显示行格式冻结为 `v{semver} Build {YYYYMMDD}`，Build 日期由构建脚本注入（RH-2 provenance 生成时写入），**禁手写日期**。
- 存档版本继续独立于游戏版本（SaveManager L3 原则不动，13 图 SV 管辖）。

### RH-2 Build Provenance（P-RH3 收口，§214 全词落位）
- 每次正式构建生成 `provenance.json`（随包根目录或嵌入 exe 同级）：八字段必填 `build_id`（构建时间+短 hash）/ `source_revision`（git HEAD）/ `game_version`（RH-1 真源）/ `constitution_version`（V1.2）/ `architecture_version` / `content_version`（05 图 content_fingerprint 同源）/ `schema_version` / `save_schema_version`（=SaveManager.SAVE_VERSION）。
- GameLogger 初始化行追加 provenance 摘要（`[Boot] build={build_id} game={game_version} save_schema={save_schema_version}`），替代现在只记引擎版本的现状（引擎版本保留并行）。
- 生成器 = 构建脚本的一部分（RH-7 的 tools/build_release.py），禁手写。

### RH-3 导出配置与产物命名（P-RH2 收口）
- `export_presets.cfg` 补齐两预设：**Windows Desktop**（x86_64）+ **Android**（ARM64；keystore/签名归用户操作，AI 只留配置位与文档说明）。
- 导出产物命名冻结：`wuxiajianghu_{game_version}_{build_id}_{platform}.{exe|apk}`（例：`wuxiajianghu_0.5.0_b202609051849_win64.exe`）。
- 安卓导出模板（debug/release keystore、包名、权限）建空位 + README，实测归 Phase4（开放问题 RH-4）。

### RH-4 Release Gate（发布门禁清单，编排不重定义）
正式发布前必须全绿的勾选清单（每项指向既有门禁，本图只做编排）：
1. **双闸门**：Godot headless `--quit` 零 ERROR + `run_all.tscn` 零 ✗（04 图 verify_all 群）。
2. **ID 校验**：GATE06 全绿（16 图 CP-5 校验器群）。
3. **性能 PASS**：GATE40+ 基准不超 Release Budget——FUNCTIONAL PASS 不算 RELEASE PASS（17 图 SBP-6，§216）。
4. **迁移验证 PASS**：RH-5 golden 对全绿。
5. **Provenance 完整**：RH-2 八字段非空且 source_revision=当前 HEAD。
6. **门禁非绿即阻断**：任何一项 FAIL 禁止出包（与 pre-commit 同族纪律，升级到发布级）。

### RH-5 迁移验证产物化（P-RH9 收口，§32 机器化）
- 每个 SAVE_VERSION 升版时，随提交产出 **golden 对**：`tests/fixtures/save_golden/v{from}_sample.json`（真实老档脱敏样本）+ `v{from}_expected.json`（迁移后期望输出）。
- 回归测试：golden 对进 Regression Suite（`test_save_migration` 扩展），断言 `迁移(from_sample) == expected`；**只增不减**（§216 修复后不删除纪律同源）。
- 发布前由 Release Gate 第 4 项强制执行；golden 对生产器脚本归 13 图 SV-3 Phase2（本图消费其产物）。
- 红线重申：**旧存档必须可用**（宪法 §32）；「未知版本盖章放行」（SaveManager L240-242，13 图 P-S3）按 13 图 Phase1 拒读路线收口，本图不重复裁决。

### RH-6 错误处理发布面（P-RH6/P-RH10 部分收口）
- FATAL 弹窗文案追加两行：当前游戏版本（RH-1 真源）+ 日志文件完整路径（user://logs/，13 图 SV-6 五域同源），让玩家能自助反馈。
- GameLogger 加**滚动上限**（单文件大小/个数上限，超限轮转），防发布版长期运行日志膨胀——具体阈值开放问题 RH-2。
- error_handler 三级结构冻结保留（FATAL 弹窗退出 / ERROR 日志+通知 / WARN 日志）；通知文案走本地化（14 图 PV 管辖）；修复 reason 用 ErrorCode（02 图管辖）。

### RH-7 构建发布脚本（P-RH5 收口）
- 新增 `tools/build_release.py`：一条命令串联「双闸门 → Release Gate 清单 → 生成 provenance.json → 注入 Build 日期 → 调 Godot 导出（Win/安卓）→ 产物命名（RH-3）→ 校验和输出」。脚本失败任一步即中止。
- 与工作室工具链（15 图）完全解耦；不修改任何生产源码，只编排既有门禁。

### RH-8 兼容等级与弃用声明制（§211+§212 全词落位）
- **兼容等级标注**：七类长期结构（Command DTO / Event Payload / Repository Contract / Content Schema / Save DTO / Module Manifest / Content Pack Manifest）发生变更时，提交说明必须标注三等级之一；**BREAKING 五要求**（Version Bump / Migration / Compatibility Test / Affected Consumer Scan / Rollback Plan）缺一即审查不通过。
- 「加一个字段≠自动兼容」的六考虑清单（旧 Content / 旧 Save / DLC / Mod / 旧客户端工具 / 测试 Fixture）作为变更检查单固化进 change_log 模板（多 AI 协同 change-tracking 同源）。
- **弃用流程**：任何 STABLE API/字段弃用走 ACTIVE→DEPRECATED→MIGRATION WINDOW→REMOVED；DEPRECATED 六字段（replacement / deprecated_since / removal_not_before / migration_guide / affected_consumers）必填；**禁止同提交无迁移删除 STABLE API**。
- 补丁发布物契约（patch_manager manifest）冻结：`{version, min_game_version, save_migration, patch.pck}` 四件套；`save_migration` 接线修复归 13 图 SV-3；在热更实际启用前 patch_manager 保持 FROZEN 不投入（§230 未禁止但也不鼓励提前实装）。
- 平台适配登记制（P-RH4 治理面）：新增平台分支必须 `OS.has_feature()` 显式声明并在本图 §2.1 登记；禁用版本号/路径字符串嗅探平台。安卓适配项（触摸、返回键、权限、emulate_mouse 决策）建 checklist 归 Phase4 实测。

---

## §4 迁移映射（绞杀者分批，获批后执行）

| 现状 | 目标 | Phase |
|------|------|-------|
| project.godot 缺 version 字段 | 补 `application/config/version="0.5.0"`（RH-1） | Phase1 |
| GameConstants.SAVE_VERSION 死常量 | 退役（随 ADR 复核，RH-3 开放问题） | Phase1 |
| patch_manager/error_handler 旧规范注释 | 更新真实条款号引用 | Phase1 |
| MainMenu/Bootstrap 硬编码版本 | 改读 ProjectSettings 真源（RH-1） | Phase2 |
| 6 用例单测 | golden 对样本集+回归扩展（RH-5，随 13 SV-3 Phase2） | Phase2 |
| GameLogger 无 provenance | 启动行 provenance 摘要（RH-2） | Phase2 |
| FATAL 弹窗无版本/日志指引 | 文案追加（RH-6） | Phase2 |
| export_presets.cfg 缺失 | Win 预设+provenance（RH-3/RH-2）；build_release.py（RH-7） | Phase2（Win）/Phase4（安卓实测） |
| GameVersion 读取面散落 | 归 Kernel 装配（随 Phase3 ApplicationRoot） | Phase3 |
| 安卓触摸/返回键/权限/性能实测 | checklist 逐项落地（RH-8 登记制） | Phase4 |
| 安卓导出全链+渠道包 | RH-3 完整执行 | Phase5+ |

每 Phase 是可安全停下的决策点；Phase4/5 依赖真机与渠道决策，未批不动。

---

## §5 Freeze 清单（本图冻结后即不可单方面变更）

1. 游戏版本唯一真源 = ProjectSettings `application/config/version`，SemVer 三段。
2. 存档版本与游戏版本永久分离（SaveManager L3 原则上升为全工程纪律）。
3. provenance.json 八字段不可缺省。
4. Release Gate 六项全绿才可出包。
5. golden 对只增不减。
6. 版本显示格式 `v{semver} Build {YYYYMMDD}`，日期由构建注入。
7. 兼容三等级词汇表（BACKWARD_COMPATIBLE / FORWARD_TOLERANT / BREAKING）全工程唯一。
8. DEPRECATED 六字段必填。
9. 产物命名模板 `wuxiajianghu_{game_version}_{build_id}_{platform}.{ext}`。

## §6 DoD（本图完成的判据）

1. project.godot 含 version 字段且 patch_manager 读取非 0.0.0（可测）。
2. 全库 grep 无第二处硬编码游戏版本常量。
3. export_presets.cfg 存在且含 Windows Desktop 预设。
4. provenance.json 生成器可运行且八字段全产出。
5. Release Gate 清单脚本化（checklist 可执行或 verify_all 扩展项）。
6. golden 对至少 1 组（v1.0.0 遗留档→1.1.0）进 Regression Suite。
7. FATAL 弹窗含版本号与日志路径（UI 断言或截图记录）。

## §7 开放问题（AI 不自决，附推荐）

- **RH-1【游戏版本号语义】** 当前 MainMenu 显示 v0.5.0（0.x 阶段）。推荐：维持 0.x 语义（0.5.0 起步），1.0.0 = 首个对外完整版；与 03 图统一 SemVer 裁决联动。
- **RH-2【日志滚动阈值】** 单文件上限与保留个数。推荐：单文件 5MB × 保留 3 个轮转，超限静默轮转不弹窗（WARN 一次）。
- **RH-3【GameConstants 处置】** 死常量退役 vs 改转发真源。推荐：直接退役（删常量；文件其余常量有消费保留），转发徒增一层间接。
- **RH-4【安卓适配批次】** 触摸/返回键/权限/性能四项是否随 Phase4 一批做。推荐：Phase4 仅做「可安装可启动可玩通新手村」最小闭环，触摸精度与性能调优按真机实测另开任务卡。

## §8 Enforcement（RH-R01~RH-R12）

| 编号 | 规则 | 机器化 |
|------|------|--------|
| RH-R01 | project.godot 必含 `application/config/version` 且 SemVer 格式 | 构建脚本前置检查（GATE 新项） |
| RH-R02 | 禁硬编码版本字符串（MainMenu 模式回归） | grep 门禁：`VERSION_TEXT|BOOTSTRAP_VERSION` 新增即拦 |
| RH-R03 | provenance 八字段非空 | build_release.py 内建断言 |
| RH-R04 | export_presets 含 Windows Desktop 预设 | 构建脚本检查 |
| RH-R05 | 产物命名符合冻结模板 | build_release.py 内建断言 |
| RH-R06 | Release Gate 六项全绿才可出包 | build_release.py 顺序门 |
| RH-R07 | golden 对随 SAVE_VERSION 升版只增不减 | Regression Suite 计数断言 |
| RH-R08 | GameLogger 启动含 provenance 摘要行 | 双闸门日志 grep |
| RH-R09 | 平台分支必须 OS.has_feature + 登记 | grep 门禁：禁 feature 字符串嗅探模式 |
| RH-R10 | 七类结构变更须带兼容等级标注 | change_log 模板 + 审查项 |
| RH-R11 | 弃用走四阶段+六字段 | 审查项（GATE0c 同族非阻断警告） |
| RH-R12 | 双闸门+GATE06+GATE40 为发布前置 | RH-4 清单编排（不重定义各门禁） |

## §9 总纲

**「没有 provenance 的包不是产品，没有 golden 对的迁移不是兼容，没有 Release Gate 的发布不是发布。」**

18 号是序列收官图：它不发明新机制，只把前 17 份冻结契约收拢成一条可执行的发货流水线。当前最大缺口是「三个零」——零版本真源（P-RH1）、零导出配置（P-RH2）、零发布脚本（P-RH5），三者叠加意味着今天项目**不具备发货能力**；而迁移骨架（原子写/备份/拒读/6 用例）与 GL Compatibility 双端渲染是健康的底座，缺的只是把健康底座包装成「可追溯、可验证、可回滚」的发布物。Phase1 三件小事（补字段/退役死常量/修注释）成本低到几乎没有理由不做；Phase2 起每一步都依赖用户对发布目标的决策。序列 01→18 至此全部产出并整体 FROZEN（2026-09-05 用户批准、2026-09-06 补办状态行）；2026-09-06 用户下达「按宪法与 01~18 逐一落地」开工指令，ACR-0001 转 APPROVED，Phase1 施工启动。

## §10 关联文档

- 宪法：`docs/constitution/PROJECT_CONSTITUTION_V1.2.md` §32 / §130 / §211 / §212 / §214 / §216 / §230 / L5973（序列点名）
- 序列前图：01 总体（§71 旧档红线）/ 02 Kernel / 03 Schema·SemVer / 04 门禁群 / 05 Content Pipeline / 06~12 各域 / **13 Save（SV-1~7、P-S1/P-S3/P-S6，迁移链定义权）** / 14 表现（本地化）/ 15 工具（工作室打包链边界）/ 16 内容（GATE06）/ 17 模拟性能（GATE40+、§216 双 PASS）
- ACR-0001（Phase0-6 待批）/ ADR-0002（ID 格式，间接联动 content_version）
- 多 AI 协同：change-tracking（change_log 兼容等级标注落地位置）
