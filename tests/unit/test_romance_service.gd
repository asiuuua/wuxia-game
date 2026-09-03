# tests/unit/test_romance_service.gd
# 姻缘服务单元测试（模块18 · M2）：无限配偶 / 满好感结缘 / 异性校验 / 关系网 / 存档 / 子嗣预留
extends TestBase

func before_each() -> void:
	GameManager.bond_service.reset()
	GameManager.romance_service.reset()
	GameManager.inventory_service.reset()
	GameManager.player_state.gender = 0   # 男
	_register_test_relations()

func after_each() -> void:
	var ids := ["npc_test_sister", "npc_test_married", "npc_test_teacher", "npc_test_sworn"]
	for id in ids:
		ConfigManager.unregister_test_relation(id)

# 测试期注入婚配资格专用替身（不污染正式 relations.json；after_each 统一清除）
func _register_test_relations() -> void:
	ConfigManager.register_test_relation("npc_test_sister", {
		"id": "npc_test_sister", "name": "测试·幼妹", "gender": 1,
		"is_romanceable": true, "kin_type": "SIBLING", "marital_status": "single",
		"required_gender": 0, "romance": {"propose_affection": 100},
	})
	ConfigManager.register_test_relation("npc_test_married", {
		"id": "npc_test_married", "name": "测试·已嫁", "gender": 1,
		"is_romanceable": true, "kin_type": "NONE", "marital_status": "married",
		"required_gender": 0, "romance": {"propose_affection": 100},
	})
	ConfigManager.register_test_relation("npc_test_teacher", {
		"id": "npc_test_teacher", "name": "测试·师尊", "gender": 1,
		"is_romanceable": true, "kin_type": "MASTER", "marital_status": "single",
		"required_gender": 0, "romance": {"propose_affection": 100},
	})
	ConfigManager.register_test_relation("npc_test_sworn", {
		"id": "npc_test_sworn", "name": "测试·义妹", "gender": 1,
		"is_romanceable": true, "kin_type": "SWORN", "marital_status": "widowed",
		"required_gender": 0, "romance": {"propose_affection": 100},
	})

func test_service_wired() -> void:
	expect(GameManager.romance_service != null, "romance_service 应已装配")
	expect(GameManager.bond_service != null, "bond_service 应已装配")

# 满好感(100)才能求婚；99 不行
func test_propose_requires_full_affection() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 99)
	expect(not rs.can_propose("npc_su_waner"), "99 好感不可求婚")
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	expect(rs.can_propose("npc_su_waner"), "100 好感可求婚")

# 求婚成功 -> 记为配偶 + 已婚阶段
func test_propose_success() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	var res: Dictionary = rs.propose("npc_su_waner")
	expect(res.get("ok", false), "求婚应成功")
	expect(rs.is_spouse("npc_su_waner"), "应记为配偶")
	expect_eq(rs.get_romance_stage("npc_su_waner"), BondEnums.RomanceStage.MARRIED, "阶段应为已婚")
	expect_eq(rs.get_spouse_count(), 1, "配偶数应为1")

# 无限配偶：两个异性 NPC 都能结缘
func test_unlimited_spouses() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	GameManager.bond_service.set_affection("npc_xiao_ying", 100)
	rs.propose("npc_su_waner")
	rs.propose("npc_xiao_ying")
	expect_eq(rs.get_spouse_count(), 2, "可同时拥有2个配偶（无限）")
	expect(rs.is_spouse("npc_xiao_ying"), "小樱应为配偶")

# 异性校验：玩家性别不符不可求婚
func test_gender_mismatch_rejected() -> void:
	var rs = GameManager.romance_service
	GameManager.player_state.gender = 1   # 女
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	expect(not rs.can_propose("npc_su_waner"), "异性不符不可求婚")
	GameManager.player_state.gender = 0
	expect(rs.can_propose("npc_su_waner"), "改回男后可求婚")

# 关系网数据
func test_relationship_graph() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	rs.propose("npc_su_waner")
	var g: Dictionary = rs.get_relationship_graph()
	expect(g.has("spouses"), "关系图含配偶")
	expect_eq(int(g["spouses"].size()), 1, "关系图配偶数1")

# 存档往返
func test_save_roundtrip() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	rs.propose("npc_su_waner")
	var snap: Dictionary = rs.save()
	rs.reset()
	rs.load(snap)
	expect(rs.is_spouse("npc_su_waner"), "读档后应仍配偶")
	expect_eq(rs.get_spouse_count(), 1, "读档配偶数1")

# 子嗣预留：寝欢 + 怀胎十月 -> 出生1子
func test_intimacy_birth() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	rs.propose("npc_su_waner")
	var r1: Dictionary = rs.begin_intimacy("npc_su_waner")
	expect(r1.get("ok", false), "寝欢应启动孕期")
	rs.advance_days(300)
	expect_eq(rs.get_children_of("npc_su_waner").size(), 1, "怀胎十月后应出生1子")

# 欢庆对接子嗣：首次欢庆受孕；孕期不阻断后续欢庆；不重复受孕；满孕期生子
func test_celebration_triggers_pregnancy() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	rs.propose("npc_su_waner")
	# 首欢庆：应受孕
	var c1: Dictionary = rs.begin_celebration("npc_su_waner")
	expect(c1.get("ok", false), "首次欢庆应成功")
	expect(bool(c1.get("conceived", false)), "首次欢庆应受孕(conceived=true)")
	expect(rs.is_pregnant("npc_su_waner"), "欢庆后应处于孕期")
	# 同日内再次欢庆：仍在配额内(2~3次)，应可点；但不重复受孕
	var c2: Dictionary = rs.begin_celebration("npc_su_waner")
	expect(c2.get("ok", false), "孕期仍可每天欢庆")
	expect(not bool(c2.get("conceived", false)), "已孕不应重复受孕(conceived=false)")
	expect_eq(rs.get_children_of("npc_su_waner").size(), 0, "孕期未到不应有子")
	# 推进怀胎十月 -> 出生1子
	rs.advance_days(300)
	expect_eq(rs.get_children_of("npc_su_waner").size(), 1, "欢庆受孕后满孕期应出生1子")

# 欢庆对所有「可结缘 + 好感满」的 NPC 开放（用户需求）：未结婚也能欢庆，且不污染配偶列表、不受孕
func test_celebration_open_to_full_affection_romanceable() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	# 未求婚、未结婚
	expect(not rs.is_spouse("npc_su_waner"), "此时还不是配偶")
	expect(rs.can_celebrate("npc_su_waner"), "好感满的可结缘 NPC 应能欢庆")
	var c: Dictionary = rs.begin_celebration("npc_su_waner")
	expect(c.get("ok", false), "好感满非配偶也能欢庆成功")
	expect(String(c.get("cg_id", "")) == "npc_su_waner", "cg_id 应为 npc_id（per-NPC 内容）")
	expect(not bool(c.get("conceived", false)), "非配偶欢庆不应受孕")
	expect(not rs.is_spouse("npc_su_waner"), "欢庆不应把非配偶写进配偶列表（配额解耦）")
	expect(rs.get_celebration_left("npc_su_waner") >= 1, "欢庆后当日仍有剩余次数")

# 好感未满不可欢庆
func test_celebration_blocked_when_affection_low() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 50)
	expect(not rs.can_celebrate("npc_su_waner"), "好感未满不可欢庆")
	var c: Dictionary = rs.begin_celebration("npc_su_waner")
	expect(not c.get("ok", false), "好感未满欢庆应被拒")
	expect(String(c.get("reason", "")) == "AFFECTION_NOT_FULL", "拒绝原因应为 AFFECTION_NOT_FULL")

# 不可结缘的 NPC 不能欢庆（即便好感满）
func test_celebration_blocked_for_non_romanceable() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_zhang_brother", 100)  # 张大彪 is_swornable 但非 romanceable
	expect(not rs.can_celebrate("npc_zhang_brother"), "不可结缘 NPC 不能欢庆")
	expect(not rs.begin_celebration("npc_zhang_brother").get("ok", false), "不可结缘 NPC 欢庆应失败")

# 测试辅助：一键满好感后可直接求婚
func test_debug_max_affection() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 0)
	expect(not rs.can_propose("npc_su_waner"), "0 好感不可求婚")
	rs.debug_max_affection("npc_su_waner")
	expect_eq(GameManager.bond_service.get_affection("npc_su_waner"), 100, "好感应为100")
	expect(rs.can_propose("npc_su_waner"), "满好感后可求婚")

# 测试辅助：一键满所有可结缘对象好感
func test_debug_max_all_affection() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_su_waner", 0)
	GameManager.bond_service.set_affection("npc_xiao_ying", 0)
	rs.debug_max_all_affection()
	expect_eq(GameManager.bond_service.get_affection("npc_su_waner"), 100, "苏婉儿好感应满")
	expect_eq(GameManager.bond_service.get_affection("npc_xiao_ying"), 100, "小樱好感应满")
	expect(rs.can_propose("npc_su_waner"), "苏婉儿可求婚")
	expect(rs.can_propose("npc_xiao_ying"), "小樱可求婚")

# === 婘眷值（2026-08-30 新增，5 级制：初始 0 级，每级 200 经验，合计 1000；仅 3/5 级解锁立绘） ===
# before_each 已 reset，直接造配偶即可从干净状态开始。
func test_quanquan_add_and_level() -> void:
	var rs = GameManager.romance_service
	rs.debug_make_spouse("npc_su_waner")
	var qq0 = rs.get_quanquan("npc_su_waner")
	expect_eq(int(qq0.get("level", 0)), 0, "初始应为 0 级")
	expect_eq(int(qq0.get("xp", 0)), 0, "初始经验应为 0")
	# +190 → 190 经验：仍 0 级，未解锁立绘
	rs.add_quanquan("npc_su_waner", 190)
	var qq1 = rs.get_quanquan("npc_su_waner")
	expect_eq(int(qq1.get("xp", 0)), 190, "加 190 后经验应为 190")
	expect_eq(int(qq1.get("level", 0)), 0, "190 经验仍为 0 级")
	expect_eq(int(qq1.get("unlocked_portraits", 0)), 0, "未到 3 级不应解锁立绘")
	# 凑到 600 → 3 级：解锁第 1 张立绘
	rs.add_quanquan("npc_su_waner", 410)
	var qq2 = rs.get_quanquan("npc_su_waner")
	expect_eq(int(qq2.get("xp", 0)), 600, "应累计到 600")
	expect_eq(int(qq2.get("level", 0)), 3, "600 经验应为 3 级")
	expect_eq(int(qq2.get("unlocked_portraits", 0)), 1, "3 级应解锁 1 张立绘")
	# 再 +400 → 1000，5 级：解锁第 2 张立绘
	rs.add_quanquan("npc_su_waner", 400)
	var qq3 = rs.get_quanquan("npc_su_waner")
	expect_eq(int(qq3.get("level", 0)), 5, "满 1000 应为 5 级（封顶）")
	expect_eq(int(qq3.get("unlocked_portraits", 0)), 2, "5 级应解锁 2 张立绘")
	# 超过上限不再升级
	rs.add_quanquan("npc_su_waner", 500)
	var qq4 = rs.get_quanquan("npc_su_waner")
	expect_eq(int(qq4.get("level", 0)), 5, "超过 1000 仍封顶 5 级")

func test_quanquan_travel_and_family() -> void:
	var rs = GameManager.romance_service
	rs.debug_make_spouse("npc_su_waner")
	var t = rs.travel_together("npc_su_waner")
	expect(t.get("ok", false), "同游应成功")
	expect_eq(int(rs.get_quanquan("npc_su_waner").get("xp", 0)), 5, "同游后经验应为 5")
	# 无子嗣家庭出游应失败
	var f0 = rs.family_outing("npc_su_waner")
	expect(not f0.get("ok", false), "无子嗣家庭出游应被拒")
	# 造子嗣后再试：寝欢启动孕期 + 推进天数分娩
	rs.begin_intimacy("npc_su_waner")
	rs.advance_days(400)
	var f1 = rs.family_outing("npc_su_waner")
	expect(f1.get("ok", false), "有子嗣家庭出游应成功")
	expect_eq(int(rs.get_quanquan("npc_su_waner").get("xp", 0)), 20, "5+15=20")

func test_quanquan_non_spouse_rejected() -> void:
	var rs = GameManager.romance_service
	# npc_village_chief 非配偶
	var r = rs.travel_together("npc_village_chief")
	expect(not r.get("ok", false), "非配偶不应获得婘眷值")

func test_portrait_list_includes_base() -> void:
	var rs = GameManager.romance_service
	rs.debug_make_spouse("npc_su_waner")
	var lst = rs.get_portrait_list("npc_su_waner")
	expect(lst.size() >= 1, "立绘列表至少含基准半身立绘")
	expect(String(lst[0]).contains("half_body"), "基准应为半身立绘路径")

# === 婚配资格（2026-09-03 新增：不娶血亲；已婚不娶；师徒/结义单身或鳏寡可娶；不限上限） ===
# 血亲（幼妹 SIBLING）不可求婚/受拒
func test_blood_kin_blocked() -> void:
	var rs = GameManager.romance_service
	# npc_test_sister 顶层 init_affection=100，直接达标
	expect(not rs.can_propose("npc_test_sister"), "血亲不可求婚")
	var p: Dictionary = rs.propose("npc_test_sister")
	expect(not p.get("ok", false), "血亲求婚应被拒")
	expect(String(p.get("reason", "")) == "BLOOD_KIN", "血亲拒绝原因应为 BLOOD_KIN")

# 已嫁 NPC（marital_status=married）不可求娶
func test_married_npc_blocked() -> void:
	var rs = GameManager.romance_service
	expect(not rs.can_propose("npc_test_married"), "已婚者不可求婚")
	var p: Dictionary = rs.propose("npc_test_married")
	expect(not p.get("ok", false), "已婚者求婚应被拒")
	expect(String(p.get("reason", "")) == "ALREADY_MARRIED", "拒绝原因应为 ALREADY_MARRIED")

# 师徒（MASTER/单身）与结义（SWORN/鳏寡）均可求娶
func test_teacher_sworn_marriage_allowed() -> void:
	var rs = GameManager.romance_service
	GameManager.bond_service.set_affection("npc_test_teacher", 100)
	GameManager.bond_service.set_affection("npc_test_sworn", 100)
	expect(rs.can_propose("npc_test_teacher"), "单身师尊应可求婚")
	expect(rs.can_propose("npc_test_sworn"), "鳏寡义妹应可求婚")
	var r1: Dictionary = rs.propose("npc_test_teacher")
	var r2: Dictionary = rs.propose("npc_test_sworn")
	expect(r1.get("ok", false), "师尊求婚应成功")
	expect(r2.get("ok", false), "义妹求婚应成功")
	expect(rs.is_spouse("npc_test_teacher"), "师尊应记为配偶")
	expect(rs.is_spouse("npc_test_sworn"), "义妹应记为配偶")

# === 后宅名分（2026-09-03 新增：大房~七房、小妾一~七、通房丫鬟；自定义重排） ===
func test_spouse_rank_default_and_reassign() -> void:
	var rs = GameManager.romance_service
	# 首位配偶 = 大房
	rs.debug_make_spouse("npc_su_waner")
	expect_eq(rs.get_spouse_rank("npc_su_waner"), BondEnums.SpouseRank.PRIMARY, "首位应为大房")
	expect(rs.get_spouse_rank_name("npc_su_waner") == "大房", "名分中文应为大房")
	# 第二位 = 二房
	rs.debug_make_spouse("npc_xiao_ying")
	expect_eq(rs.get_spouse_rank("npc_xiao_ying"), BondEnums.SpouseRank.SECOND, "次位应为二房")
	# 自定义重排：把小樱抬成大房，苏婉儿降为通房丫鬟
	expect(rs.set_spouse_rank("npc_xiao_ying", BondEnums.SpouseRank.PRIMARY), "应可重排为大房")
	expect_eq(rs.get_spouse_rank("npc_xiao_ying"), BondEnums.SpouseRank.PRIMARY, "重排后小樱为大房")
	expect(rs.set_spouse_rank("npc_su_waner", BondEnums.SpouseRank.CHAMBERMAID), "应可降为通房丫鬟")
	expect(rs.get_spouse_rank_name("npc_su_waner") == "通房丫鬟", "苏婉儿中文名应为通房丫鬟")

# 名分不设上限：可无限娶妻，且不加成（仅登记）；单位数时名分按结婚次序为房位
func test_spouse_rank_unlimited_and_sorted() -> void:
	var rs = GameManager.romance_service
	var ids := ["npc_su_waner", "npc_xiao_ying", "npc_test_teacher", "npc_test_sworn"]
	for id in ids:
		rs.debug_make_spouse(id)
	expect_eq(rs.get_spouse_count(), 4, "可有 4 位配偶（不设上限）")
	# 第3/4位为三房/四房（7 房之内均称"房"，第 8 位起才回落小妾）
	expect_eq(rs.get_spouse_rank("npc_test_teacher"), BondEnums.SpouseRank.THIRD, "第3位应三房")
	expect_eq(rs.get_spouse_rank("npc_test_sworn"), BondEnums.SpouseRank.FOURTH, "第4位应四房")
	var sorted: Array = rs.get_sorted_spouses()
	expect_eq(sorted.size(), 4, "排序表含4人")

# === 子嗣成长阶段（2026-09-03 新增：婴儿→幼童→孩童→少年→成年） ===
func test_child_growth_stage() -> void:
	var rs = GameManager.romance_service
	rs.debug_make_spouse("npc_su_waner")
	rs.begin_intimacy("npc_su_waner")
	rs.advance_days(300)  # 满孕期分娩
	var kids: Array = rs.get_children_of("npc_su_waner")
	expect_eq(kids.size(), 1, "应出生1子")
	var cid: String = String(kids[0])
	expect_eq(rs.get_child_stage(cid), BondEnums.ChildStage.INFANT, "出生应为婴儿")
	expect(rs.get_child_stage_name(cid) == "婴儿", "阶段中文应为婴儿")
	# 幼童：+35 天（累计35）
	rs.advance_days(35)
	expect_eq(rs.get_child_stage(cid), BondEnums.ChildStage.TODDLER, "满30天应为幼童")
	# 孩童：再+200（累计235）
	rs.advance_days(200)
	expect_eq(rs.get_child_stage(cid), BondEnums.ChildStage.CHILD, "满180天应为孩童")
	# 少年：再+600（累计835）
	rs.advance_days(600)
	expect_eq(rs.get_child_stage(cid), BondEnums.ChildStage.TEEN, "满720天应为少年")
	# 成年：再+1200（累计2035）
	rs.advance_days(1200)
	expect_eq(rs.get_child_stage(cid), BondEnums.ChildStage.ADULT, "满1800天应为成年")
