# 武侠江湖 项目记忆

## 定位与宪法 V1.2
- 等距2.5D武侠RPG单机；Godot 4.7.2；纯GDScript；个人开发；回合制+自动；Win+安卓。
- 真源：**`docs/constitution/PROJECT_CONSTITUTION_V1.4.md`（现行有效,ADR-0005）**；V1.2 保留历史基线；V1.3 经 V1.4 修订说明承载。优先级：宪法>架构>契约>施工图>任务卡>AI推断。V1.4 核心：RULE001 放软白名单 Adapter/0-B.0 分治双轨/0-B.12 三层语义/0-E.3 GATE15 Adapter 放行；0-C 章 20 条逐字兼容；02图K-R+GATE22 基线 Adapter 判据升版待 ACR。
- AI不是架构师：架构级变更一律 STOP→ACR→评审→ADR→分批迁移，禁推倒重写。ACR-0001 APPROVED(2026-09-06)。
- 迁移=绞杀者分批：0测量→1 Kernel→2 事务根治(P0)→3 装配收敛(18 Autoload)→4 逐模块→5 基础设施；每Phase可停；§171收编不丢弃。
- **进度**(2026-09-06)：P1+09/10/11事务根治+D-01~10销项+裁决收口+13/03/16/17图红线批+12图QD-2五类收编；**Phase3 kernel窗批1~3=02图24契约(5a71907)+TransactionRuntime(b9f6489,GATE26/27升PARTIAL)+ShopTrade买卖0-C(ae5cdc1,10图EC-5)**；**05图批1=CONTENT-RUNTIME骨架(ab46676,三TypeAdapter attach回接/GATE17挂槽,十四槽全绿)**；05图DoD3~6留批2~3；**待办清单A组✅(5683d8b)**=Integration链3用例入GATE2(73套件)/P-RH6旧编号清零6处/GATE21核查(test_shape/naming未物理化随ACR)/backlog单一真源20项；**auto_complete复查**:全部任务JSON未写该字段(grep data/零命中;初判null系python get()缺键返None误读),缺省true→交足自动交付=12图契约缺省语义,非缺陷已resolved；**B组七项✅(6723e27)**=RULE007写入口基线(43入口)+R004/007跨模块直写扫描(scenes零直写)+GATE26/27/28 ACTIVE+PROJECT_STATUS.md补建+K-R16漂移抓获修复(entries_for漏排序)+TimeConsumer分相注册制+AB-6确定性锚；**C组三销(085039a)**=GATE22升版(§93完整矩阵kernel零命中+core基线64条+0-E.3 Adapter豁免)+GATE30物理化(GATE42槽 context_pack_validator 0-G.5/0-G.6+对账；施工图变更后必须--generate刷新pack否则STALE红)+Write Lease落地(tools/write_lease.py,0-G.8 FROZEN_SCOPE,施工前必须claim)+ADR-0007 PROPOSED(批A骨架/B三件/C收编/D瘦身,批准即实施)；heredoc长中文三连挂=永久禁用,一律Write脚本文件；下批=ADR-0007批准后批A 或 D组五图。

## 施工图序列 01→18（FROZEN；现行真源=NN_*_V1.4修复版.md——17图升版完成(ADR-0006,commit c2ee981/4602bb3/c10eac7),V1.2稿保留；升表口随ACR：GATE22 Adapter判据/GATE30物理化进verify_all/装配收敛=ADR-0007）
- 18图零星：16 id_validator挂GATE06(基线234只减不增)；GATE28 command_ordering未动。
- SV-2新纪律：新模块入档=先重跑gen_save_body_registry.tscn重产登记表(否则注册期拒)；模块字段变更=升_module_versions+register_module_migration+golden对,不动SAVE_VERSION。
- 门禁双命名空间(T-1追认)：文档LN=GATE01~32；物理槽1~9冻结；新槽GATE40+(40=性能基准,41=架构校验器组)；禁裸引物理号。GATE6=五检；GATE22/32=arch_linter(去注释指纹)。
- 大图余量：06 Actor、08 Relationship、14表现、15 Studio。

## 裁决状态（2026-09-06 用户整批追认「按各图§7推荐」）
02~18开放问题+ADR-0002~0004全追认+ADR-0005宪法升版+ADR-0006十七图升版，登记=docs/architecture/ADR_INDEX.md(新ADR自0007顺延)；nv/mt存量迁移随Phase3~4须存档迁移链。

## 架构铁律
依赖禁引矩阵(04图GATE41机器化)：core地基纯净只引core/data只准core+data/services禁引scenes/生产禁引tests/autoload与scenes装配表现自由；跨模块走EventBus/数值进JSON。
分相队列纪律(12图)：任务事件回调只入队+_flush_events冲刷；外部直调_on_*后须冲刷才见推进；闸门双标志(_flushing/_deferred_pending)禁共用。

## GDScript 4.x 硬规
Color()满4参；typed Array禁`as Array[String]`；mini/maxi仅2参；闭包按值捕获值类型；mouse_filter STOP=0/PASS=1/IGNORE=2；pre-commit三门禁(0a吞点击/0b信号基线拦新增/0c警告)；Variant(Vector2等)JSON往返不等——哈希类先JSON归一化；基准/生成器宿主必须场景模式+看门狗；Dictionary.get()取untyped Array禁直赋typed变量——untyped中转逐元素append；**RefCounted子类方法名禁撞Object原生(get/set等,签名不符即Parse Error,ShardCache.get→fetch踩坑)**；**手动跑Godot必须4.7.2(@abstract等4.4+语法4.3下Parse Error)**。

## Godot 本机验证铁律
console版；双闸门：①--headless --quit 零硬错误 ②run_all.tscn 零✗且失败M==0。验证前必commit；.godot缺失=全崩；新class_name须--import重建。

## 纹理压缩
出厂mode=0；tscn_assets.py写死mode=2+compress_textures.py改0→2；取像素用Image.load_png_from_buffer禁对压缩纹理get_pixel。

## 主权与多AI协同
共享地基冻结；UI/战斗/背包/结缘各有主权。四铁律：留痕(change_log)·调前先查·双闸门commit(窗口署名)·门禁非绿阻断。commit_queue.py+handoff.py。

## 一键验证
`python tools/verify_all.py` 十四槽(GATE1~9+17资产契约+21/22/32/41,GATE1自愈缓存,GATE2防抖)+`--tier performance`(GATE40基准)。真源：区域=_map_index.json v2/NPC=regions/<rid>/npcs.json/好感=BondService；town_npcs退役。schema_guard基线=结构指纹(合法变更升版--update-baseline收编)。TestBase断言只有expect/expect_eq(后者仅int,String比较用expect(a==b))。

## 工作室工具与远端
工作室源码模式=双击studio_launcher.bat即时生效(详见skill desktop-studio-exe-rebuild)；4个runtime大图转LFS；远端唯一=GitHub origin(git@github.com:asiuuua/wuxia-game.git)；严禁`git stash -u`。

## UI/B路线
全量.tscn化收官(23项)；hover_shift经studio调写main_menu_assets.json；5水墨图标在assets/ui/main_menu/。
