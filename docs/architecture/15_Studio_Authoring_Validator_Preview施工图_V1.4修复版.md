# 15 Studio / Authoring / Validator / Preview 施工图 V1.4 修复版

> 状态：FROZEN（2026-09-06 用户批准；可依此实施）
> 真源：宪法 §67 Studio（L3694-3711）/ §68 Story Graph / §69 Dependency Graph（L3736-3747）/ §164 第五阶段（L5159-5166）/ §88 GATE16 Studio Smoke（L4037）；01 图 §79 Studio（L1239-1247）/ §80 Story Editor / §92 Architecture Validators（L1397-1406）/ §93 Forbidden API
> 前序：03 Contract（ID 白名单/ref_index GATE6）· 04 测试（verify_all V2、arch_lint 七校验器、LN/物理双命名空间）· 05 Content Pipeline（Phase0 REPORT/manifest）· 13 SV-6（patch_history 域）· 14 PV（配置面/screens.json 校验/i18n 契约）
> 铁律：本文档只冻结契约与迁移映射，**批准前不写任何实现代码**（01§104）。

---

## 0. 编号命名空间声明

本图启用三个前缀，已对 01~14 图全量核对，**无撞号**：

| 前缀 | 含义 | 归属 |
|---|---|---|
| `ST-1 ~ ST-8` | 冻结契约（Studio/工具域） | 本图 |
| `P-ST1 ~ P-ST10` | 实锤缺陷（机器实扫证据，含文件行号） | 本图 |
| `ST-R01 ~ ST-R12` | Enforcement 矩阵条目 | 本图 |

- 04 图开放问题 T-1~4、05 图开放问题 C-1~4 与本图 ST 前缀不同域，无冲突。
- 宪法 §88 GATE16（Studio Smoke）与 verify_all 物理 GATE7 的映射按 04 图 LN/物理双命名空间政策登记（本图 §2.2），不新增物理槽。

---

## 1. 定位

> **V1.4 修复版总注**：本图随宪法 V1.4（ADR-0005）与 01 图 V1.4 修复版同步升版——①宪法条款号零漂移，正文「宪法 §N / 0-C.x / 0-F.x」引用全部有效；②RULE 001 放软：Domain 经白名单 Adapter/Boundary 触达 Godot 属合法协作（判据=0-E.3/GATE15，白名单升表随 ACR）；③本图冻结契约与冻结物版本零变化，V1.2 原稿保留（§171 收编不丢弃）。域内衔接：Studio 工具链自由度以 RULE 001 白名单边界为准（宪法 0-E.3/GATE15 判据）；ST-6 校验器注册表为新扫描器统一挂载点。

宪法 §67 一句话定性：**Studio 不是 JSON 编辑器，是 Content Authoring System**——12 件套（Schema/NPC/Quest/Dialogue Editor、Story Graph、Condition/Effect Editor、Reference Inspector、Dependency Graph、Preview、Validation、Build）。01 图 §79 加一条红线：**编辑器依赖 Schema / Definition / Validation / Registry，不直接修改 Runtime State**（写的必须是 Authoring 数据）。

§69 给 Studio 一道必答题：**「我修改这个 NPC，会影响什么？」**——Dependency Graph 是创作安全的底座。

**本项目的现实**：工具域是全工程**密度最高的资产带**——tools/ 顶层 32 个 Python 工具约 3900 行 + desktop_studio 约 6400 行，一键门禁 verify_all（GATE1~9）、工作室安全五件套、引用反查 ref_index、多 AI 协同三件套、分层投喂 export_ai_context 全部已在服役。宪法 §164 把 Studio 12 件套放在**第五阶段**，所以本图的任务不是补编辑器，而是三件事：**把现有工具的纪律冻结成契约、把 God Module 拆分与同名漂移排进绞杀者队列、给未来的 12 件套预留唯一写入口与注册表地基**。现有工具域等价物收编标注：Reference Inspector ≈ `ref_index.py --who`；Validation ≈ GATE 群；Build ≈ 打包链（发行期）。

---

## 2. 现状盘点（实扫 2026-09-05）

### 2.1 已有资产（§171 收编，升级不丢弃）

| # | 资产 | 位置 | 规模 | 收编说明 |
|---|---|---|---|---|
| 1 | verify_all 一键门禁 | `tools/verify_all.py` | 309 行 | GATE1~9 物理槽全注册（headless/单测/工程规范/战斗预设/双写防线/ref_index/工作室冒烟/结构兜底/JS 语法）；USERPROFILE/APPDATA 自愈根治 user:// 假红（09-04 排障沉淀） |
| 2 | 工作室冒烟闭环 | `tools/studio_smoke.py` | 64 行 | 临时目录 self_test 15+ 断言 + npc_upsert→npc_list→区域表落盘**编辑→游戏同源验证**；宪法 GATE16 的现状实现（物理 GATE7） |
| 3 | 工作室服务端安全五件套 | `tools/desktop_studio/studio_server.py` | 1035 行 | 127.0.0.1 绑定+端口顺延（L1000）；CSRF `_origin_allowed` 三入口全覆盖（L39-48/L396/L679/L968）；`_is_valid_id` ID 白名单；经验库文档读取限工程根+仅 .md/.txt 防穿越（L631-637） |
| 4 | 安全自检 | `security_selftest.py` + `studio_core.self_test` | 100+ 行 | 15 断言回归（安全红线机器兜底） |
| 5 | 引用反查 | `tools/ref_index.py` | 214 行 | 全量 ID 引用索引+悬空检测+`--who` 反查；03 图 GATE6 承接；**Dependency Graph 的现状等价物** |
| 6 | 多 AI 协同三件套 | `change_log.py` / `commit_queue.py` / `handoff.py` | 273+345+283 行 | 留痕/提交队列/隐患传递板（主权协同纪律的机器层） |
| 7 | AI 上下文投喂 | `tools/export_ai_context.py` | 248 行 | summary/module/all 三模式分层投喂+排除白名单+token 估算；平台「ai_context 复用能力」本体 |
| 8 | UI 贴图直写 | `desktop_studio/tscn_assets.py` | 616 行 | UI 贴图直写 .tscn（不写 uid/不预生成 .import）；`write_import()` 写死 compress/mode=2（纹理压缩第一层保险） |
| 9 | 纹理压缩第二层 | `tools/compress_textures.py` | 223 行 | 扫 assets/ 改 mode=0→2 + 删 stale .ctex 强制重导（「仅改 .import 不触发重导」事故沉淀）+ --check/--dry-run |
| 10 | pre-commit 三道门 | `lint_mouse_filter.py` / `audit_signal_contract.py`+基线 / `gate0c_ambiguous_warn.py` | 210+225+114 行 | 拦吞点击/信号契约基线/ambiguous 警告（机器兜底层） |
| 11 | 专项审计三件 | `check_assets_contract.py` / `check_crossref.py` / `audit_onready_paths.py` | 186+188+114 行 | 资产契约/交叉引用/@onready 路径 |
| 12 | JS 语法门禁 | `tools/js_lint.py` | 84 行 | index.html 内联脚本逐块 node --check（物理 GATE9） |
| 13 | 编辑器内预览器 | `scenes/ui/preview/UIPreview.gd` | @tool | screens.json 驱动下拉预览 + `_editor_preview()` 模拟数据注入约定 + owner=null 防污染生产 .tscn |
| 14 | 创作回收站 | `studio_core.py` trash 五件（L555-676） | — | trash_put/list/restore/purge + auto_cleanup——创作误删的「撤销」底座 |
| 15 | LFS 迁移护栏 | `tools/migrate_to_lfs.py` | 147 行 | git-lfs 已装+远端无明文 token 双护栏 |
| 16 | i18n 写入工具 | `studio_core.i18n_upsert`（L495-524） | — | strings.csv 三语写入（14 图 PV-8 本地化契约的作者侧） |

### 2.2 LN/物理门禁映射登记（依 04 图政策）

| LN（文档引用） | 物理槽（verify_all 现状） | 说明 |
|---|---|---|
| GATE16 Studio Smoke | 物理 GATE7（studio_smoke.py） | 同物异号，文档一律写 LN，物理槽冻结不动 |
| GATE06 引用校验 | 物理 GATE6（ref_index） | 03 图已 LN 化 |
| GATE09（JS/前端资产） | 物理 GATE9（js_lint） | 本图登记 |
| 其余 GATE1~5/8 | 物理同号或 04 图映射表 | 以 04 图 T-1 追认表为准 |

### 2.3 实锤缺陷（P-ST1 ~ P-ST10）

- **P-ST1【同名工具双份漂移】** `tools/compress_textures.py`（223 行全功能版：.ctex 清理 + --check/--dry-run/--resize-sources + 事故注释）与 `tools/desktop_studio/compress_textures.py`（111 行精简版）**同名异义、已 diff 确认分叉**。文档/MEMORY 口径指顶层版，两份实际并行演进——改哪份、哪份生效，全凭记忆。
- **P-ST2【studio_core.py God Module】** 3091 行单文件装 ≥10 个域：项目发现/设置、安全 ID 校验、NPC 立绘导入与资产上传、任务图三件（L381-469）、i18n 四件（L469-524）、操作日志（L524-551）、回收站五件（L555-676）、对话分片（L676-685）、区域 NPC 文件（L685-734+）、startup 卡/经验库/布局调参——与 GameManager 17 Service God Object 同族问题在工具域复现（违宪法 §73 精神）。
- **P-ST3【modules/ 空壳】** `desktop_studio/modules/` 仅 `__init__.py` + `__pycache__`——模块化拆分开了头没落地，空壳目录误导后来者。
- **P-ST4【一次性脚本残留】** tools/ 顶层 7 个 `_` 前缀脚本（`_dewhite_matte` / `_enhance_matte` / `_extract_clean` / `_gen_clean_tres` / `_gen_matte175_tres` / `_gen_matte_175` / `_gen_matte_frames`）——一次性生成物混在正式工具区，无退役标记（03 图退役名单机制未覆盖工具域）。
- **P-ST5【运行产物混入源码目录】** `desktop_studio/` 下 `_exe_run.log` / `_src_launch.log` / `_src_run2.log` / `__pycache__` / `build/` / `project_root.txt` 与源码混放——git 状态噪音 + 打包易误带。
- **P-ST6【预览组件双登记】** `UIPreview.gd` L18-24 `COMPONENT_PATHS` 硬编码 5 个 HUD 组件路径，与 screens.json 注册表平行——新增 HUD 组件须双登记，漏登记则预览器静默不可见。
- **P-ST7【编辑器写路径零契约】** studio_core 直接写 `data/configs/**` JSON（npc_upsert / quest_graph_save / i18n_upsert 等）：`_is_valid_id`（L188）只管 NPC id 形态，任务图/对话分片/i18n 键无统一 ID 白名单校验；写前 `_backup`（L358）有，**写后无 ref_index 增量反查**——编辑器当场可产生悬空引用，要等下次 GATE6 才兜底暴露。
- **P-ST8【校验器清单分散】** 门禁/审计类工具 9 个各自独立被 verify_all 手工注册，无统一注册表与归属声明（04 图 arch_lint.py 七校验器 + contract_registry 的现状基线=分散态；01 图 §92 七校验器尚未有 py 侧统一宿主）。
- **P-ST9【生成器五散】** `gen_backlog` / `gen_blue_placeholder` / `gen_icons` / `gen_placeholder_portraits` / `gen_ui_sfx` 五个生成器无统一入口、无输出路径契约（对照：tscn_assets 已是工作室导入链一环）。
- **P-ST10【AI 上下文双出口】** 「给 AI 喂上下文」有两个出口：`export_ai_context.py` 文件导出（读 projects/wuxia_game.yaml ai_context 段）与 studio_server `/api/experience` HTTP 经验库——内容同源（manifest）但路径/格式两套，第三套出口无禁令。

---

## 3. 冻结契约（ST-1 ~ ST-8）

### ST-1 Studio 定位与红线（宪法 §67 / 01 图 §79 原文锚定）
- Studio = Content Authoring System，写 **Authoring 数据**（data/configs → 未来 content/definitions，随 05 图 ADR-0003）；**禁直接修改 Runtime State**、禁写 user:// 存档、禁连运行中的游戏进程改内存态。
- 编辑器功能必须构建在 Schema / Definition / Validation / Registry 之上（01 §79），禁绕过定义层直写任意 JSON 结构。

### ST-2 写路径契约（P-ST7 收口，未来 12 件套的唯一地基）
- 所有编辑器写入统一走**单一 DataSink 收口**，固定六步：①ID 校验（03 图白名单正则统一入口，`_is_valid_id` 扩为全域形态校验）→ ②Schema 校验（05 图 Validation 双通道的运行期端）→ ③`_backup` 留底 → ④落盘 → ⑤**ref_index 增量反查**（写后即时悬空检测，违例即回滚并提示，不等 GATE6 兜底）→ ⑥change_log 留痕。
- DataSink 抽象层先行于任何目录迁移（ADR-0003 落位时只改根路径，写路径零改动）。

### ST-3 安全契约（五件套冻结，P-ST 平台红线）
- 冻结五件套：127.0.0.1 绑定 + 端口顺延 / `_origin_allowed` CSRF（全部 do_GET/do_POST 入口先过）/ `_is_valid_id` ID 白名单 / 文档读取限工程根+限扩展名 / security_selftest 断言回归。
- **新端点准入清单**：任何新增 HTTP 端点必须同时过五件套检查 + 进 self_test 断言清单，否则不合入（change_log 留痕时声明）。

### ST-4 模块化拆分契约（P-ST2/P-ST3 收口）
- `studio_core.py` 按 10 域拆入 `modules/`（project / security / npc_asset / quest_graph / i18n / oplog / trash / dialogue / region / knowledge…），studio_core 降为 facade 转发；server 只留 HTTP 路由层，**禁在 server 写业务逻辑**。
- 每模块自带自测函数并注册进 `self_test` 注册表；`modules/` 空壳状态限期兑现（拆分排期见 §4，属 Phase3 随装配收敛）。
- 与 GameManager 绞杀者同款纪律：拆分是**搬移不改行为**，studio_smoke 全程绿。

### ST-5 工具清单与退役制契约（P-ST1/P-ST4/P-ST5 收口）
- `tools/` 建 **TOOLS manifest**（`tools/manifest.json` 或 TOOLS.md）：名称/职责/门禁归属（LN 编号）/入口用法；新工具入仓必须登记+声明 verify_all 归属。
- 退役机制延展到工具域：一次性脚本迁 `tools/_archive/`（`_` 前缀禁入顶层）；运行产物（*.log/__pycache__/build）落 `.gitignore` 并移出源码目录规范位。
- **同名工具唯一化**：compress_textures 双份合并（方向见开放问题 ST-2），全 tools 禁同名双份。

### ST-6 校验器统一注册表契约（P-ST8 收口，承接 01 §92 / 04 图）
- 九个门禁/审计工具统一注册进 04 图 contract_registry / arch_lint 基线范式：每校验器声明 {名称, LN Gate 编号, tier, 输入域, REPORT 可用性}；verify_all 从注册表编排（物理槽 1~9 + 0a/b/c 冻结不动，新校验走注册表 + LN 编号，GATE40+ 物理槽）。
- 01 §92 七校验器（dependency/forbidden_api/module_scope/changed_file_scope/contract_drift/state_owner/naming）以 py 侧 arch_lint.py 为统一宿主（04 图已规划，本图认领工具域宿主地位）；Phase0 REPORT 模式沿用 05 图测量纪律。

### ST-7 预览契约（P-ST6 收口）
- 预览登记**单一真源**：`COMPONENT_PATHS` 退役，组件并入 screens.json（或独立 `preview_registry.json`，随 14 图 PV-6 配置面裁决）——预览器只读注册表，禁硬编码路径清单。
- `_editor_preview()` 模拟数据注入约定冻结为组件**可选实现协议**（生产界面保持非 @tool、预览 owner=null 防污染两条现行为冻结）。

### ST-8 生成器与投喂契约（P-ST9/P-ST10 收口）
- gen_* 五器统一入口 `gen.py <kind>`（或登记制逐一挂 manifest），输出路径写死规范位（assets/ 或 data/configs/ 对应域），禁散落根目录。
- AI 上下文**双出口冻结**：文件导出（export_ai_context）与 HTTP 经验库（/api/experience）为仅有的两个出口，同源 projects/*.yaml manifest；禁建第三出口，manifest 变更两出口自动同步（单源双投）。

---

## 4. 迁移映射表（绞杀者分批，每步可停）

| # | 现状 | 目标 | Phase | 依据 |
|---|---|---|---|---|
| 1 | 同名工具双份（P-ST1） | compress_textures 合并唯一化 | Phase2 | ST-5 |
| 2 | 一次性脚本/运行产物混放（P-ST4/5） | `_archive/` + gitignore 规范位 | Phase2 | ST-5 |
| 3 | 编辑器写路径零契约（P-ST7） | DataSink 六步收口 | Phase2（随 03/05 契约） | ST-2 |
| 4 | 预览双登记（P-ST6） | 单源注册表 | Phase2 | ST-7 |
| 5 | 校验器分散（P-ST8） | 注册表 + arch_lint 宿主 | Phase3（随 04 V2） | ST-6 |
| 6 | studio_core God Module + modules 空壳（P-ST2/3） | 十域拆入 modules/，facade 化 | Phase3（随装配收敛） | ST-4 |
| 7 | 生成器五散（P-ST9） | 统一入口/登记制 | Phase3 | ST-8 |
| 8 | AI 上下文双出口（P-ST10） | 单源双投冻结 | Phase3 | ST-8 |
| 9 | Studio 12 件套缺口（Story Graph / Dependency Graph / Schema Editor 等） | 按宪法 §164 第五阶段排期；Dependency Graph 先以 ref_index --who 收编标注 | Phase5 | ST-1 |
| 10 | exe 发行打包链 | 源码模式为日常，exe 仅发行场景（desktop-studio-exe-rebuild 流程已固化） | 发行期 | ST-3 补 |

---

## 5. Freeze 清单（批准后不可再改，改动走 ADR）

1. 「Studio 写 Authoring 数据、禁碰 Runtime State」红线与 DataSink 六步顺序。
2. 安全五件套清单与新端点准入规则。
3. verify_all 物理 GATE1~9 + hook 0a/b/c 冻结；LN/物理映射表（§2.2）。
4. tools manifest 登记制与 `_` 前缀退役规则。
5. `modules/` 拆分目标边界（server 禁业务逻辑 / core facade 化 / 每模块自测注册）。
6. `_editor_preview()` 协议与 owner=null 约定。
7. AI 上下文双出口清单（禁第三出口）。
8. P-ST1~P-ST10 编号（缺陷登记永不回收，修复后在 Enforcement 基线表销账）。

---

## 6. DoD（本图完成的定义）

1. ST-1~ST-8 全部契约有宪法/01 图条款锚点，无 AI 自创标准。
2. P-ST1~P-ST10 每条含文件+行号级实锤（diff/def 分布可独立复核）。
3. 迁移映射 10 行每行有 Phase 归属，Studio 12 件套明确落宪法 §164 第五阶段，不抢跑。
4. 开放问题 ST-1~4 每条带推荐项，标注「AI 不自决，待用户/ADR」。
5. Enforcement 矩阵 ST-R01~R12 每条有 LN Gate 编号与验收方式，E0=0 如实登记。
6. §171 资产 16 项全部给出收编方式（冻结/升级/收编标注），零丢弃。
7. 本文档不包含任何实现代码，未改动任何生产源码与工具。

---

## 7. 开放问题（AI 不自决，待用户/ADR 裁决）

> **【已追认 2026-09-06】** 用户整批复核：以下 ST-1~ST-4 全部按推荐执行（本节保留原文供审计）。

- **ST-1【Authoring 数据落位时机】** 推荐：维持 05 图 ADR-0003 裁决（data/configs → content/definitions 延 Phase5）；ST-2 DataSink 抽象先行，落位切换只是换根路径，工作室写路径零改动。不在 15 图内提前搬目录。
- **ST-2【compress_textures 双份合并方向】** 推荐：`tools/compress_textures.py`（223 行全功能版）为唯一真源；desktop_studio/111 行版退役——其职责已被 tscn_assets.py「第一层保险」+ 顶层版「第二层保险」覆盖，工作室如有独立调用点改为 `sys.path` 引顶层版。合并前先 diff 确认 111 行版无独有逻辑（本图已 diff 头部，合并时全量确认）。
- **ST-3【Studio 12 件套缺口排期】** 推荐：Phase5 前不新增编辑器（宪法 §164 定第五阶段）；当前优先把地基打牢（ST-2 DataSink + ST-6 注册表）；Story Graph 八节点（01 §80）与 Dependency Graph 届时基于 03/05 图 Definition/Registry 建。现状等价物标注：Reference Inspector ≈ `ref_index.py --who`、Validation ≈ GATE 群、Build ≈ 发行打包链。
- **ST-4【桌面工具发行形态】** 推荐：源码模式（studio_launcher.bat 自愈版）为日常形态；exe 仅发行/分发场景 PyInstaller 重打包（打包 SOP 已在 desktop-studio-exe-rebuild skill 固化，含同步 6 副本+md5 校验）；施工图不冻结打包细节，只冻结「改完源码必须跑启动验证释放端口」纪律（已有）。

---

## 8. Enforcement 矩阵（ST-R01 ~ ST-R12，E0=0 如实登记）

| # | 条目 | Gate | E 级 |
|---|---|---|---|
| ST-R01 | Studio 写路径唯一 DataSink（绕过直写 data/configs 的 py 代码扫描） | LN GATE05 / GATE07 | E0 |
| ST-R02 | 编辑器写后 ref_index 增量反查（悬空即拒绝写入） | LN GATE07 | E0 |
| ST-R03 | 安全五件套回归（selftest 断言随新端点扩容） | LN GATE07 | E0 |
| ST-R04 | server 禁业务逻辑 / core facade 化（拆分边界基线检查） | LN GATE05（py 侧） | E0 |
| ST-R05 | tools manifest 登记制（新工具未登记即违例） | LN GATE05 | E0 |
| ST-R06 | `_` 前缀一次性脚本禁入 tools 顶层 | LN GATE05 | E0 |
| ST-R07 | 全 tools 禁同名双份脚本 | LN GATE05 | E0 |
| ST-R08 | modules/ 空壳限期兑现（拆分完成前禁增新逻辑入 core） | 人工评审 | E0 |
| ST-R09 | 预览登记单源（COMPONENT_PATHS 退役） | LN GATE07 | E0 |
| ST-R10 | index.html 内联脚本逐块 node --check（物理 GATE9 冻结引用） | 物理 GATE9 | E0 |
| ST-R11 | 新编辑域必须接入 studio_smoke 写→读回闭环模板 | LN GATE07 | E0 |
| ST-R12 | LN/物理门禁映射表随 04 T-1 追认更新（文档一致性） | 文档评审 | E0 |

---

## 9. 一句话总纲

**工具域资产密度全工程最高——本图把「能跑」升「有契约」：DataSink 唯一写入口、安全五件套准入、注册表化校验器、God Module 排拆、12 件套不抢跑（§164 第五阶段）。**

---

## 10. 关联文档

- 宪法 §67/§68/§69（Studio 三节）、§88 GATE16、§164 第五阶段
- 01 图 §79 Studio、§80 Story Editor、§92 Architecture Validators、§93 Forbidden API
- 03 图（ID 白名单/ref_index/GATE6）、04 图（verify_all V2/arch_lint/LN 双命名空间）、05 图（Validation 双通道/ADR-0003/Phase0 REPORT）
- 13 图 SV-6（patch_history/user:// 域）、14 图 PV-6/PV-8（配置面校验/本地化作者侧）
- 运行 SOP：desktop-studio-exe-rebuild skill（源码模式优先/释放三件事）
