# scenes/gameplay/battle/tactical_test_decorator.gd
# 战棋测试场景装饰层（测试专用，不进入生产战斗逻辑）：
#   - 水面：背景层半透明 shader（程序化波纹 + 反光），位于战场后方
#   - 竹子（左下）：前景遮挡物，注入 Battlefield 共享 y_sort，压在角色之上营造纵深
#   - 房屋（右下）：前景遮挡物，注入 Battlefield，制造真实房屋遮挡感
#   - 雾气：CPUParticles2D 慢速飘移低透明度，覆盖全场（在 HUD 之下）
# 设计原则：复用现有战术战斗逻辑（TacticalBattleScene），本节点只做"套一层装饰"，
#           战斗结算/网格/单位逻辑一律不碰。与项目既有落叶粒子共用同一套 Image/CPUParticles API。

extends Node2D

# 按网格像素范围布置四件套；field=战场根（已开 y_sort），scene_root=战术场景根（放雾气叠加层）
func attach(field: Node2D, scene_root: Node2D) -> void:
	var grid_node: Node = field.get_node_or_null("GridNode")
	if grid_node == null:
		grid_node = _find_by_name(field, "GridNode")
	if grid_node == null or not grid_node.has_method("pixel_center"):
		# 兜底：无网格时随便摆，避免空引用崩
		_build_water(Rect2(-200, -120, 400, 240), field)
		_build_bamboo(Vector2(-180, 160), field)
		_build_house(Vector2(180, 160), field)
		_build_fog(Rect2(-200, -120, 400, 360), scene_root)
		return
	var rect: Rect2 = _grid_pixel_rect(grid_node)
	# 水面：战场"后方"（顶边，y 较小）一条横向水带，作为背景层
	var water_rect := Rect2(rect.position.x - 20, rect.position.y - 60, rect.size.x + 40, 110.0)
	_build_water(water_rect, field)
	# 竹子：左下角（x 小、y 大）—— 前景遮挡
	var bamboo_pos := Vector2(rect.position.x + 70, rect.position.y + rect.size.y - 30)
	_build_bamboo(bamboo_pos, field)
	# 房屋：右下角（x 大、y 大）—— 前景遮挡
	var house_pos := Vector2(rect.position.x + rect.size.x - 70, rect.position.y + rect.size.y - 30)
	_build_house(house_pos, field)
	# 雾气：覆盖整张战场，叠加在战场之上、HUD 之下
	_build_fog(rect, scene_root)

## 网格像素包围盒（grid_node 局部坐标 = 世界坐标，因为 Battlefield 在原点）
func _grid_pixel_rect(grid_node: Node) -> Rect2:
	var g = grid_node.get("grid")
	var tl: Vector2 = grid_node.cell_center(Vector2i(0, 0))
	var br: Vector2 = grid_node.cell_center(Vector2i(int(g.width) - 1, int(g.height) - 1))
	var hw: float = grid_node.tile_width * 0.5
	var hh: float = grid_node.tile_height * 0.5
	return Rect2(tl.x - hw, tl.y - hh, (br.x - tl.x) + hw * 2.0, (br.y - tl.y) + hh * 2.0)

func _find_by_name(root: Node, name_: String) -> Node:
	for c in root.get_children():
		if c.name == name_:
			return c
		var deep := _find_by_name(c, name_)
		if deep != null:
			return deep
	return null

# ───────────────────────── 水面 ─────────────────────────
func _build_water(rect: Rect2, parent: Node2D) -> void:
	var water := ColorRect.new()
	water.name = "Water"
	water.position = rect.position
	water.size = rect.size
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 程序化水面 shader：TIME 驱动波纹 + 反光，无需贴图，headless 也能编译
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float w1 = sin(uv.x * 16.0 + t * 1.2) * 0.5 + 0.5;
	float w2 = sin(uv.y * 11.0 - t * 0.9) * 0.5 + 0.5;
	float m = mix(w1, w2, 0.5);
	vec3 deep = vec3(0.07, 0.20, 0.34);
	vec3 shallow = vec3(0.16, 0.42, 0.58);
	vec3 col = mix(deep, shallow, m);
	float glint = smoothstep(0.93, 1.0, sin((uv.x + uv.y) * 24.0 + t * 1.6));
	col += glint * 0.22;
	COLOR = vec4(col, 0.6);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	water.material = mat
	parent.add_child(water)

# ───────────────────────── 竹子（前景遮挡）─────────────────────────
func _build_bamboo(base: Vector2, parent: Node2D) -> void:
	var bamboo := Node2D.new()
	bamboo.name = "BambooOccluder"
	bamboo.position = base
	# 数根竹竿（细高矩形，绿），向上生长（负 y）
	var stalks := [
		{"x": -22.0, "h": 150.0, "w": 7.0},
		{"x": -8.0,  "h": 182.0, "w": 8.0},
		{"x": 6.0,   "h": 168.0, "w": 7.0},
		{"x": 20.0,  "h": 200.0, "w": 9.0},
	]
	for s in stalks:
		var culm := ColorRect.new()
		culm.color = Color(0.20, 0.45, 0.22)
		culm.size = Vector2(s["w"], s["h"])
		culm.position = Vector2(s["x"] - s["w"] * 0.5, -s["h"])
		bamboo.add_child(culm)
		# 竹节
		for k in range(3):
			var node := ColorRect.new()
			node.color = Color(0.12, 0.32, 0.14)
			node.size = Vector2(s["w"] + 2.0, 3.0)
			node.position = Vector2(s["x"] - (s["w"] + 2.0) * 0.5, -s["h"] * (0.25 + 0.25 * float(k)))
			bamboo.add_child(node)
	# 叶簇（向上斜出的椭圆色块）
	for e in [
		Vector2(-30.0, -150.0), Vector2(18.0, -170.0), Vector2(-6.0, -190.0),
		Vector2(34.0, -140.0), Vector2(-18.0, -120.0)
	]:
		var leaf := ColorRect.new()
		leaf.color = Color(0.26, 0.55, 0.27)
		leaf.size = Vector2(22.0, 9.0)
		leaf.position = Vector2(e.x - 11.0, e.y - 4.0)
		leaf.rotation = 0.5
		bamboo.add_child(leaf)
	parent.add_child(bamboo)

# ───────────────────────── 房屋（前景遮挡）─────────────────────────
func _build_house(base: Vector2, parent: Node2D) -> void:
	var house := Node2D.new()
	house.name = "HouseOccluder"
	house.position = base
	# 墙体（实心，遮住身后单位）
	var wall := ColorRect.new()
	wall.color = Color(0.45, 0.34, 0.26)
	wall.size = Vector2(120.0, 86.0)
	wall.position = Vector2(-60.0, -86.0)
	house.add_child(wall)
	# 门（暗色）
	var door := ColorRect.new()
	door.color = Color(0.20, 0.14, 0.10)
	door.size = Vector2(28.0, 46.0)
	door.position = Vector2(-14.0, -46.0)
	house.add_child(door)
	# 窗（暖色）
	for wx in [-42.0, 18.0]:
		var win := ColorRect.new()
		win.color = Color(0.85, 0.72, 0.35)
		win.size = Vector2(20.0, 18.0)
		win.position = Vector2(wx, -66.0)
		house.add_child(win)
	# 屋顶（梯形，Polygon2D）
	var roof := Polygon2D.new()
	roof.color = Color(0.30, 0.22, 0.20)
	roof.polygon = PackedVector2Array([
		Vector2(-72.0, -86.0), Vector2(72.0, -86.0),
		Vector2(40.0, -126.0), Vector2(-40.0, -126.0)
	])
	house.add_child(roof)
	parent.add_child(house)

# ───────────────────────── 雾气 ─────────────────────────
func _build_fog(rect: Rect2, parent: Node2D) -> void:
	var fog := CPUParticles2D.new()
	fog.name = "Fog"
	fog.emitting = true
	fog.amount = 30
	fog.lifetime = 12.0
	fog.gravity = Vector2(0, -4)
	fog.initial_velocity_min = 6.0
	fog.initial_velocity_max = 16.0
	fog.direction = Vector2(1.0, -0.15)
	fog.spread = 30.0
	fog.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fog.emission_rect_extents = Vector2(rect.size.x / 2.0, rect.size.y / 2.0)
	fog.position = rect.position + rect.size * 0.5
	fog.scale = Vector2(2.4, 2.4)
	fog.texture = _make_soft_circle()
	parent.add_child(fog)

## 径向羽化软圆（雾团贴图）：中心不透明、边缘透明，冷白雾色直接烘焙进贴图
## （Godot 4 的 CPUParticles2D 节点本身无 color 属性，颜色必须走贴图）
func _make_soft_circle() -> Texture2D:
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c := float(sz) / 2.0
	var tint := Color(0.82, 0.86, 0.92)
	for y in range(sz):
		for x in range(sz):
			var d := Vector2(x, y).distance_to(Vector2(c, c)) / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.18   # 整体压低透明度，雾感轻盈
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a))
	var tex := ImageTexture.create_from_image(img)
	return tex
