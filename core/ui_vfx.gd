# core/ui_vfx.gd
# UI 视觉特效配置装载器（UI 窗口主权，Phase2 放权）。
# 设计原则同 UISkin：小白只改 data/configs/ui/skin/<screen_id>.vfx.json 这份数据；
# 游戏侧只做「装载 + 应用」，缺文件 / 非法 JSON 都回退 DEFAULTS，永不崩溃。
# 写由工作室后端 /api/ui_skin(kind=main_menu_vfx) 负责，游戏侧对平台零依赖。
extends RefCounted
class_name UIVFX

const DIR := "res://data/configs/ui/skin/"

# 主菜单默认特效参数（与现有写死数值一致；缺文件回退，视觉不变）。
# enabled_* 控制该特效是否出现；其余为补间时长 / 粒子数量等可调旋钮。
const DEFAULTS := {
	"enabled_cloud": true, "cloud_speed": 30.0,
	"enabled_water": true, "water_min_alpha": 0.6, "water_max_alpha": 1.0, "water_period": 2.5,
	"enabled_boat": true, "boat_speed": 20.0,
	"enabled_leaves": true, "leaves_amount": 24, "leaves_lifetime": 9.0,
	"leaves_gravity_y": 26.0, "leaves_vel_min": 18.0, "leaves_vel_max": 55.0, "leaves_scale": 1.6,
}

## 读取某屏的 VFX 配置，返回合并默认值后的 dict。缺文件 / 非法 JSON 回退 DEFAULTS。
static func load_vfx(screen_id: String) -> Dictionary:
	var path := DIR + screen_id + ".vfx.json"
	if not FileAccess.file_exists(path):
		return DEFAULTS.duplicate()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return DEFAULTS.duplicate()
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return DEFAULTS.duplicate()
	var raw: Dictionary = j.data
	var out := DEFAULTS.duplicate()
	for k in DEFAULTS.keys():
		if raw.has(k):
			out[k] = raw[k]
	return out
