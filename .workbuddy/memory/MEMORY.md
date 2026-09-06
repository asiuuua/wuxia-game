# 武侠江湖 项目记忆

## 定位与宪法 V1.2
- 等距2.5D武侠RPG单机；Godot 4.7.2；纯GDScript；个人开发；回合制+自动；Win+安卓。
- 真源：`docs/constitution/PROJECT_CONSTITUTION_V1.2.md`。优先级：宪法>架构>契约>施工图>任务卡>AI推断。
- AI不是架构师：架构级变更一律 STOP→ACR→评审→ADR→分批迁移，禁推倒重写。ACR-0001 APPROVED(2026-09-06)。
- 迁移=绞杀者分批：0测量→1 Kernel→2 事务根治(P0)→3 装配收敛(18 Autoload)→4 逐模块→5 基础设施；每Phase可停；§171收编不丢弃。
- **进度**(2026-09-06)：P1+09/10/11事务根治+D-01~10销项+裁决收口+13/03/16/17图红线批+12图QD-2五类收编(EffectRegistry五kind锁/P-Q1修复/GATE32基线85)；**Phase3批次1=02图kernel 24契约(5a71907)+批次2=TransactionRuntime三件套(b9f6489：begin/run/commit/rollback+Journal八字段,13测试,GATE26/27升PARTIAL,GATE2=69套件)**；下批=批次3装配收敛(需单独ADR+Write Lease)。

## 施工图序列 01→18（FROZEN；唯一真源=docs/architecture/NN_*.md）
- 0-C事务主战场=09/10/11(完成)；13图Phase2红线批全落(SV-1/2/3/4/6)；16 id_validator挂GATE06(基线234只减不增)；17 GATE40+落地；18 RH版本真源/Provenance八字段/Release Gate六项。
- SV-2新纪律：新模块入档=先重跑gen_save_body_registry.tscn重产登记表(否则注册期拒)；模块字段变更=升_module_versions+register_module_migration+golden对,不动SAVE_VERSION。
- 门禁双命名空间(T-1追认)：文档LN=GATE01~32；物理槽1~9冻结；新槽GATE40+(40=性能基准,41=04图架构校验器组)；禁裸引物理号。GATE6=五检(ref_index/id_validator/schema_guard/pack_manifest/region三同)；GATE22/32=arch_linter(去注释指纹)。
- 大图余量：05 ContentRegistry、06 Actor、08 Relationship、14表现、15 Studio；02 kernel批次1/2已落；GATE28 command_ordering未动。

## 裁决状态（2026-09-06 用户整批追认「按各图§7推荐」）
02~18 开放问题+ADR-0002/0003/0004 全部追认，登记表=docs/architecture/ADR_INDEX.md(新ADR自0005顺延,§23A预占题不占号)；nv/mt存量迁移随Phase3~4须存档迁移链；forge_iron_sword按10图EC-R07 Phase4迁recipe_域。

## 架构铁律
依赖禁引矩阵(04图GATE41机器化)：core地基纯净只引core/data只准core+data/services禁引scenes/生产禁引tests/autoload与scenes装配表现自由；跨模块走EventBus/数值进JSON。PerformanceMonitor挂tools/=越位待Phase3收敛。
分相队列纪律(12图)：任务事件回调只入队+_flush_events冲刷；外部直调_on_*后须冲刷才见推进；闸门双标志(_flushing/_deferred_pending)禁共用。

## GDScript 4.x 硬规
Color()满4参；typed Array禁`as Array[String]`；mini/maxi仅2参；闭包按值捕获值类型；外部配置JSON.new()+parse!=OK；mouse_filter反直觉STOP=0/PASS=1/IGNORE=2；pre-commit三门禁(0a吞点击/0b信号基线拦新增/0c警告)；**Variant(Vector2等)JSON往返不等——checksum/哈希类必须先JSON归一化再算**；**基准/生成器宿主必须场景模式(--script无autoload)+看门狗**；**Dictionary.get()取untyped Array禁直赋typed变量(运行时崩溃)——untyped中转+逐元素append**。

## Godot 本机验证铁律
console版；双闸门：①--headless --path --quit 零硬错误 ②run_all.tscn 零✗且失败M==0。ROOT用Windows风格；验证前必commit；.godot缺失=全崩；新class_name须--import重建。

## 纹理压缩
出厂mode=0；tscn_assets.py写死mode=2+compress_textures.py改0→2；取像素用Image.load_png_from_buffer禁对压缩纹理get_pixel。

## 主权与多AI协同
共享地基冻结；UI/战斗/背包/结缘各有主权。四铁律：留痕(change_log)·调前先查·双闸门commit(窗口署名)·门禁非绿阻断。commit_queue.py+handoff.py。
## 一键验证
`python tools/verify_all.py` 十三槽(GATE1~9+21/22/32/41,GATE1自愈缓存,GATE2防抖)+`--tier performance`(GATE40基准)。真源：区域=_map_index.json v2/NPC=regions/<rid>/npcs.json/好感=BondService；town_npcs退役。schema_guard基线=结构指纹(合法变更升版后--update-baseline收编)。TestBase断言只有expect/expect_eq(后者仅int,String比较用expect(a==b))。

## 工作室工具（tools/desktop_studio）
源码模式=日常(双击studio_launcher.bat即时生效)；版本不对→`git checkout HEAD -- tools/desktop_studio/`。详见skill desktop-studio-exe-rebuild。

## Git LFS 与远端（2026-09-02）
4个runtime大图转LFS；远端唯一=GitHub origin(git@github.com:asiuuua/wuxia-game.git)；严禁 `git stash -u`。

## UI/B路线
全量.tscn化收官(23项)；hover_shift经studio调写main_menu_assets.json；5水墨图标在assets/ui/main_menu/。
