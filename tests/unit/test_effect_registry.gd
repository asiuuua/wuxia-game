# tests/unit/test_effect_registry.gd
# Effect 注册表单测（12 图 QD-2 / DoD5）：五类 kind 各自可达 + 第六种拒注册（QD-R03）
# + 死命令 FATAL（QD-R09）+ DSL/dict 双协议路由 + 通报面。

extends TestBase
class_name TestEffectRegistry

func _noop_handler(_payload: Variant, _ctx: Dictionary) -> void:
	pass

# === 五类 kind 注册与可达（DoD5）===

func test_five_kinds_register_and_apply() -> void:
	var reg := EffectRegistry.new()
	var hit := {"n": 0}
	var counter := func(_p: Variant, _c: Dictionary) -> void:
		hit["n"] = int(hit["n"]) + 1
	expect(reg.register("r_op", EffectRegistry.KIND_REWARD, counter), "reward kind 应可注册")
	expect(reg.register("f_op", EffectRegistry.KIND_STORY_FLAG, counter), "story_flag kind 应可注册")
	expect(reg.register("l_op", EffectRegistry.KIND_RELATIONSHIP, counter), "relationship kind 应可注册")
	expect(reg.register("p_op", EffectRegistry.KIND_PROGRESS, counter), "progress kind 应可注册")
	expect(reg.register("s_op", EffectRegistry.KIND_PRESENTATION, counter), "presentation kind 应可注册")
	for op in ["r_op", "f_op", "l_op", "p_op", "s_op"]:
		expect(reg.apply(op, "", {}), "五类 op %s 应端到端可达（QD-R09）" % op)
	expect_eq(int(hit["n"]), 5, "五次 apply 应各命中 handler 一次")

func test_kind_of_and_effect_names() -> void:
	var reg := EffectRegistry.new()
	reg.register("exp", EffectRegistry.KIND_REWARD, _noop_handler)
	reg.register("silver", EffectRegistry.KIND_REWARD, _noop_handler)
	reg.register("sfx", EffectRegistry.KIND_PRESENTATION, _noop_handler)
	expect(reg.kind_of("exp") == EffectRegistry.KIND_REWARD, "kind_of 应返回注册 kind")
	expect(reg.kind_of("__none__") == "", "未注册 op kind_of 应返回空串")
	var rewards: Array = reg.effect_names(EffectRegistry.KIND_REWARD)
	expect(rewards.has("exp") and rewards.has("silver") and not rewards.has("sfx"),
		"effect_names(kind) 应按 kind 过滤")
	var all: Array = reg.effect_names()
	expect_eq(all.size(), 3, "effect_names() 无过滤应返回全部")

# === QD-R03：第六种副作用形态禁令（注册期机器化拒绝）===

func test_sixth_kind_rejected() -> void:
	var reg := EffectRegistry.new()
	expect(not reg.register("evil_op", "custom_sixth", _noop_handler),
		"第六种 kind 注册应被拒绝（QD-R03）")
	expect(not reg.has_effect("evil_op"), "被拒注册不应入表")
	expect(not reg.register("empty_kind_op", "", _noop_handler), "空 kind 注册应被拒绝")

func test_duplicate_op_rejected() -> void:
	var reg := EffectRegistry.new()
	expect(reg.register("dup_op", EffectRegistry.KIND_REWARD, _noop_handler), "首次注册应成功")
	expect(not reg.register("dup_op", EffectRegistry.KIND_REWARD, _noop_handler),
		"重复 op 注册应被拒绝（防双 handler 语义漂移）")

# === QD-R09：死命令禁令（未注册 op = FATAL）===

func test_dead_command_rejected() -> void:
	var reg := EffectRegistry.new()
	expect(not reg.apply("__never_registered__", "", {}), "未注册 op apply 应返回 false（死命令）")
	expect(not reg.apply_line("__dead__:x", {}), "DSL 死命令应返回 false")
	expect(not reg.apply_dict({"type": "__dead__"}, {}), "dict 死命令应返回 false")

# === 双协议路由：apply_line（DSL 首冒号）/ apply_dict（type|op 键）===

func test_apply_line_dsl_parsing() -> void:
	var reg := EffectRegistry.new()
	var got := {}
	var h := func(payload: Variant, _ctx: Dictionary) -> void:
		got["payload"] = payload
	reg.register("set_flag", EffectRegistry.KIND_STORY_FLAG, h)
	expect(reg.apply_line("set_flag:story_x=1", {}), "kv DSL 应可达")
	expect(String(got.get("payload", "")) == "story_x=1", "首冒号后整段应作 payload（kv 解析归 handler）")
	expect(reg.apply_line("set_flag:story_y", {}), "裸 key DSL 应可达")
	expect(String(got.get("payload", "")) == "story_y", "裸 key payload 应为键名")
	expect(not reg.apply_line("", {}), "空命令应返回 false")
	expect(not reg.apply_line("   ", {}), "纯空白命令应返回 false")

func test_apply_dict_shapes() -> void:
	var reg := EffectRegistry.new()
	var got := {}
	var h := func(payload: Variant, _ctx: Dictionary) -> void:
		got["payload"] = payload
	reg.register("shake", EffectRegistry.KIND_PRESENTATION, h)
	expect(reg.apply_dict({"type": "shake", "intensity": 8.0}, {}), "type 键 dict 应可达")
	var p: Dictionary = got.get("payload", {})
	expect(float(p.get("intensity", 0)) == 8.0, "整字典应透传为 payload")
	expect(reg.apply_dict({"op": "shake"}, {}), "op 键 dict 应兼容可达")
	expect(reg.apply_dict("shake", {}), "字符串效果应透传 apply_line")
	expect(not reg.apply_dict({"no_type_key": 1}, {}), "缺 type/op 键应返回 false")
	expect(not reg.apply_dict(42, {}), "非法形态应返回 false")

# === 游戏装配全景：共享域表六 op 齐备（与 QuestService/Executor 咬合）===

func test_game_assembly_registry_ops() -> void:
	if GameManager == null or GameManager.effect_registry == null:
		expect(false, "GameManager.effect_registry 不可用（装配缺位）")
		return
	var reg := GameManager.effect_registry
	for op in ["exp", "silver", "items", "abilities"]:
		expect(reg.kind_of(op) == EffectRegistry.KIND_REWARD, "装配表 %s 应为 reward 类" % op)
	expect(reg.kind_of("quest_accept") == EffectRegistry.KIND_PROGRESS, "装配表 quest_accept 应为 progress 类")
	expect(reg.kind_of("quest_complete") == EffectRegistry.KIND_PROGRESS, "装配表 quest_complete 应为 progress 类（P-Q1 修复）")
	expect(reg.kind_of("set_flag") == EffectRegistry.KIND_STORY_FLAG, "装配表 set_flag 应为 story_flag 类")
	expect(reg.kind_of("sfx") == EffectRegistry.KIND_PRESENTATION, "装配表 sfx 应为 presentation 类")
	expect(reg.kind_of("shake") == EffectRegistry.KIND_PRESENTATION, "装配表 shake 应为 presentation 类")
