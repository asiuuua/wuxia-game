# tests/unit/test_icons_real.gd
# 真实图标落地回归（UI 窗口主权）：验证"缺图标占位（品红棋盘）"已被真实图标替换。
# 覆盖各分类的代表性 id：skills / items / enemies / npc / menu / status。
# 关键断言：get_icon 返回的是真实 Texture2D，且绝不再回退 PlaceholderTexture2D（紫块）。

extends TestBase

const IconRegistry = preload("res://scenes/ui/icon_registry.gd")

# 游戏实际引用、必须可加载真实图标的代表性 id
const REAL_IDS := [
	"skills/sword_qingsong_001",
	"skills/qinggong_tiyun_001",
	"items/armor_cloth_001",
	"items/pill_heal_xiaohuan_001",
	"enemies/bandit_001",
	"npc/player",
	"npc/demo_npc",
	"menu/attributes",
	"menu/save",
	"status/pojia",
]

func test_generated_icons_resolve_real_textures() -> void:
	for id in REAL_IDS:
		expect(IconRegistry.has_icon(id), "图标应真实存在并可加载: " + id)
		var tex := IconRegistry.get_icon(id)
		expect(tex != null and tex is Texture2D, "get_icon 应返回真实 Texture2D: " + id)

func test_no_placeholder_leak_for_shipped_ids() -> void:
	# 这些 id 是游戏实际引用的，绝不能再回退到品红棋盘占位
	for id in REAL_IDS:
		var tex := IconRegistry.get_icon(id)
		expect(tex != null, "不能为 null: " + id)
		expect(not (tex is PlaceholderTexture2D), "不应回退占位图（品红棋盘）: " + id)
