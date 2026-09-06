# tests/unit/test_actor_skeleton.gd
# 06 图批1 ②③④：State Owner 落位 + Materialization/VS-005 骨架 + NPC 四态契约。
# 覆盖：NP-2 白名单六项（A-R02 面）、NP-3 禁存（构造面）、Owner 默认 ALIVE 防误判、
#       战斗快照回写语义镜像、SV-1 DTO 切片往返、SV-3 State 先于皮、
#       A-R05 Materialize→Dematerialize→Rematerialize 逐字段一致。

extends TestBase


func _make_def(npc_id: String) -> NPCDefinition:
	var d := {
		"id": npc_id,
		"name": "测试NPC",
		"scene": "town",
		"pos_x": 100.0,
		"pos_y": 200.0,
		"dialog_id": "dlg_test",
		"quest_id": "",
		"battle_id": "",
	}
	return NPCDefinition.from_dict(d)


# ---------------- ② NpcStateOwner ----------------

func test_owner_default_alive_and_state_whitelist() -> void:
	var owner := NpcStateOwner.new()
	expect_eq(owner.status_of("npc_ghost_a"), NpcStateOwner.STATUS_ALIVE, "缺省状态=ALIVE 防误判（§1.1 语义）")
	expect(owner.state_of("npc_ghost_a") == null, "读路径不隐式创建（防读侧误写）")
	owner.set_unit_status("npc_ghost_a", NpcStateOwner.STATUS_DEAD)
	expect_eq(owner.status_of("npc_ghost_a"), NpcStateOwner.STATUS_DEAD, "写入口生效")
	var st := owner.ensure_state("npc_ghost_a")
	var keys: Array = st.to_dict().keys()
	expect(keys.size() == 6, "NP-2 白名单六项（实际 %d 键）" % keys.size())
	for k in NPCState.WHITELIST_KEYS:
		expect(keys.has(k), "白名单键在位：%s" % k)


func test_owner_combat_snapshot_mirror() -> void:
	var owner := NpcStateOwner.new()
	owner.apply_combat_snapshot([
		{"unit_id": "npc_ghost_a", "status": 2},
		{"unit_id": "npc_ghost_b", "status": 1},
		{},   # 坏快照：无 unit_id，静默跳过
	])
	expect_eq(owner.status_of("npc_ghost_a"), 2, "快照回写 a")
	expect_eq(owner.status_of("npc_ghost_b"), 1, "快照回写 b")
	expect_eq(owner.state_count(), 2, "坏快照不入册")


func test_owner_save_slice_roundtrip() -> void:
	var owner := NpcStateOwner.new()
	var st := owner.ensure_state("npc_ghost_a")
	st.position = Vector2(12.5, 34.0)
	st.status = 1
	st.schedule_ref = "sched_market_day"
	st.runtime_flags = {"met_player": true}
	var dto := NPCSaveDTO.from_state(st)
	var blob := dto.to_dict()
	# SV-1 切片面：生命/任务状态不落本 Owner 切片（事实各归其主）
	expect(not blob.has("health"), "DTO 不含 health（归 Progression 域）")
	expect(not blob.has("quest_state"), "DTO 不含 quest_state（归 Quest 域）")
	# JSON 往返（Vector2 → [x,y] 归一化红线）
	var restored_owner := NpcStateOwner.new()
	restored_owner.import_save({"npc_ghost_a": blob})
	var st2 := restored_owner.state_of("npc_ghost_a")
	expect(st2 != null, "恢复出状态")
	expect(st2.equals_state(st), "SV-1 切片往返逐字段一致")


# ---------------- ③ ActorMaterializer / VS-005 ----------------

func test_materializer_four_phase_loop() -> void:
	var owner := NpcStateOwner.new()
	var mz := ActorMaterializer.new(owner)
	var def := _make_def("npc_ghost_a")
	# SV-3：State 先于皮——materialize 从 Owner 事实灌皮
	var rt := mz.materialize(def)
	expect(rt != null and rt.is_active, "materialize 出皮且激活")
	expect(mz.materialized_count() == 1, "皮在册")
	# AM-2：弃皮回写事实
	owner.ensure_state("npc_ghost_a").position = Vector2(7.0, 8.0)   # 皮外事实变更（Owner 为真源）
	expect(mz.dematerialize("npc_ghost_a"), "dematerialize 成功")
	expect(not mz.is_materialized("npc_ghost_a"), "皮已弃")
	expect(mz.dematerialize("npc_ghost_a") == false, "重复弃皮返回 false")
	expect_eq(mz.materialized_count(), 0, "皮册清空")
	var st := owner.state_of("npc_ghost_a")
	expect_eq(st.status, 0, "事实仍在 Owner（皮撕了事实没丢）")


func test_ar05_rematerialize_field_identical() -> void:
	var owner := NpcStateOwner.new()
	var def := _make_def("npc_ghost_a")
	var st := owner.ensure_state(def.id)
	st.position = Vector2(3.0, 4.0)
	st.status = 1
	st.runtime_flags = {"flag_a": 1}
	var mz := ActorMaterializer.new(owner)
	var rt1 := mz.materialize(def)
	var before := owner.state_of(def.id).duplicate_state()
	var rt2 := mz.rematerialize(def)
	expect(rt2 != null and rt2.is_active, "re-materialize 出新皮")
	var after := owner.state_of(def.id)
	expect(before.equals_state(after), "A-R05：Rematerialize 后 Owner 状态逐字段一致")
	expect(rt1.position == rt2.position, "皮位置一致")
	expect(rt1.status == rt2.status, "皮状态镜像一致")


func test_materializer_reads_state_not_stale_skin() -> void:
	var owner := NpcStateOwner.new()
	var def := _make_def("npc_ghost_b")
	owner.ensure_state(def.id).position = Vector2(9.0, 9.0)
	var mz := ActorMaterializer.new(owner)
	var rt := mz.materialize(def)
	expect(rt.position == Vector2(9.0, 9.0), "SV-3：皮的位置来自 Owner 事实，非凭空")


# ---------------- ④ 四态契约 / AC-3 ----------------

func test_definition_from_region_shard_shape() -> void:
	var def := _make_def("npc_ghost_c")
	expect(def.id == "npc_ghost_c", "id 透传")
	expect(def.display_text_id == "", "旧键 name 不冒充键化 display（键化补齐归 Phase2）")
	expect(def.spawn_position() == Vector2(100.0, 200.0), "spawn 点在 Definition（NP-4）")
	expect(def.dialog_id == "dlg_test", "Binding 归 Definition（01 §47）")


func test_actor_identity_carrier_minimal() -> void:
	var eid := EntityId.of(&"NPC", "000001")
	var a := ActorIdentity.of(eid, ActorIdentity.ActorType.NPC)
	expect(a.is_alive(), "默认存活")
	expect(a.describe().contains("NPC_000001"), "描述含身份锚、不含显示名")
	a.alive_state = ActorIdentity.AliveState.DEAD
	expect(not a.is_alive(), "存活态可迁移")
	# AC-2 禁吞：Carrier 面只应有 entity_id/actor_type/alive_state 三个脚本字段
	# （get_property_list 会夹带原生类标记项——只认 SCRIPT_VARIABLE 用途位）
	var own := []
	for p in a.get_property_list():
		if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			own.append(str(p.get("name", "")))
	own.sort()
	expect(own.size() == 3, "AC-3 载体最小面（实际 %s）" % str(own))
	for expected in ["actor_type", "alive_state", "entity_id"]:
		expect(own.has(expected), "载体字段在位：%s" % expected)
