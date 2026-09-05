# 武侠江湖 项目记忆

## 定位与宪法 V1.2
- 等距2.5D武侠RPG单机；Godot 4.7.2；纯GDScript；个人开发；回合制+自动；Win+安卓；区域枢纽式。
- 真源：`docs/constitution/PROJECT_CONSTITUTION_V1.2.md`。优先级：宪法>架构>契约>施工图>任务卡>AI推断。
- AI不是架构师：架构级变更一律 STOP→ACR→评审→ADR→分批迁移，禁推倒重写。ACR-0001 APPROVED(2026-09-06)。
- 迁移=绞杀者分批：0测量→1 Kernel→2 事务根治(P0)→3 装配收敛(18 Autoload)→4 逐模块→5 基础设施；每Phase可停；§171收编不丢弃。
- **施工已开工**(2026-09-06)：Phase1五项+Phase2收官(版本真源/provenance/出包/id_validator基线263)；09/10/11事务根治60d8ea6；**P1完成**：13图SV-3(P-S3拒读/P-S5五字段checksum归一化/P-S6注册表+golden生产器)+P-S2补课(key撞车拒注册)+17图GATE40+(--tier performance+基线save1.8/combat0.09/boot815ms±50%+build_release强制)。

## 施工图序列 01→18（全部 FROZEN，2026-09-06 用户批准）
- 已整体冻结，可依图实施；各图含 Enforcement X-R 矩阵(E0=0)。**详细契约/实锤/开放问题以 docs/architecture/NN_*.md 为唯一真源**，此处只留索引：
- 01总体/02 Kernel/03 Schema/04 测试门禁/05 内容机器/06 角色/07 时间/08 关系/09 物品/10 经济/11 战斗/12 叙事/13 存档/14 表现/15 工具/16 内容生产/17 模拟平衡/18 发布加固。
- 跨图要点：0-C事务主战场=09/10/11(已完成)；13 SV-3 Phase2已落地(golden生产器tools/golden/)；16 id_validator挂GATE06(基线263只减不增)；17 GATE40+已落地；18 RH管版本真源/export_presets缺失/Provenance八字段/Release Gate六项/兼容等级声明制。
- 门禁双命名空间(04§2冻结待T-1追认)：文档LN=宪法§88 GATE01~20∪01§127 GATE21~32；verify_all物理槽1~9+hook 0a/b/c冻结；新物理槽GATE40+；禁裸引物理号。

## 待用户/ADR裁决(AI不自决·推荐见各图§7)
04-T1双命名空间追认；02 O-1~4；03 ADR-0002 ID格式(推C)·0003目录延Phase5·0004维持.gd，另宪法§23A预占ADR与之撞车待统一登记表；05 C-1~4；06 AC-1~4；07 WT-1~4；08 RF-1~4；09 IE-1~4；10 EC-1~4；11 AB-1~4；12 QD-1~4；13 SV-1~4；14 PV-1~4；15 ST-1~4；16 CP-1~4；17 SBP-1~4；18 RH-4安卓待裁(RH-1版本/RH-2日志轮转/RH-3死常量已执行)。

## 架构铁律
autoload→core→data→services→scenes→tests/tools；单向依赖/跨模块走EventBus/数值进JSON。PerformanceMonitor挂tools/=越位待Phase3收敛。

## GDScript 4.x 硬规
Color()满4参；typed Array禁`as Array[String]`；mini/maxi仅2参；闭包按值捕获值类型；外部配置JSON.new()+parse!=OK；mouse_filter反直觉STOP=0拦截/PASS=1/IGNORE=2穿透(装饰节点必须IGNORE)；pre-commit三门禁(0a吞点击/0b信号基线拦新增/0c警告)；**Variant(Vector2等)JSON序列化往返不等——checksum/哈希类必须先JSON归一化(stringify→parse→stringify)再算**；**基准/生成器宿主必须场景模式(--script无autoload)，场景内加看门狗防脚本错误挂死门禁**。

## Godot 本机验证铁律
console版；双闸门：①--headless --path --quit 零硬错误 ②run_all.tscn 零✗且失败M==0。ROOT用Windows风格；验证前必commit；.godot缺失=全崩；新class_name须--import重建。

## 纹理压缩
出厂mode=0；tscn_assets.py写死mode=2+compress_textures.py改0→2；取像素用Image.load_png_from_buffer禁对压缩纹理get_pixel。

## 主权与多AI协同
共享地基冻结；UI/战斗/背包/结缘各有主权。四铁律：留痕(change_log)·调前先查·双闸门commit(窗口署名)·门禁非绿阻断。commit_queue.py+handoff.py。
## 一键验证
`python tools/verify_all.py` 九门禁(GATE1自愈缓存)+`--tier performance`(GATE40基准)。真源：区域=_map_index.json v2/NPC=regions/<rid>/npcs.json/好感=BondService；town_npcs退役；GATE6=ref_index+id_validator三检。

## 工作室工具（tools/desktop_studio）
源码模式=日常(双击studio_launcher.bat即时生效)。开发完释放：kill测试服务/工作树不留混合改动/收尾前启动验证；版本不对→`git checkout HEAD -- tools/desktop_studio/`。详见skill desktop-studio-exe-rebuild。

## Git LFS 与远端（2026-09-02）
4个runtime大图(~14.6MB)转LFS；git-lfs在PortableGit mingw64/bin。远端唯一=GitHub origin(git@github.com:asiuuua/wuxia-game.git)，Gitee已删(云端旧仓待手删·旧token已吊销)；master含宪法+01~18+P1落地。严禁 `git stash -u`。

## UI/B路线
全量.tscn化收官(23项)；hover_shift经studio调写main_menu_assets.json；5水墨图标在assets/ui/main_menu/。
