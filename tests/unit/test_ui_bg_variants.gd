# tests/unit/test_ui_bg_variants.gd
# 覆盖 UIBackground.pick_bg_path —— 登录背景多分辨率变体的挑选逻辑（任务 #47）
# 要点：变体表用**工程里真实存在的图片**搭建，否则 ResourceLoader.exists() 过滤会把档位全跳过。

extends TestBase

const VARIANTS_PATH := "res://data/configs/ui/_tmp_bg_variants_test.json"
const FALLBACK := "FALLBACK_NOT_EXIST"

# 三档：借工程中真实存在的三张图，避免 exists() 过滤
const P_1080 := "res://assets/ui/splash.png"
const P_2K := "res://assets/ui/main_menu_bg.png"
const P_4K := "res://assets/ui/main_menu_btn/menu_new_game.png"

func _write(txt: String) -> void:
	var f := FileAccess.open(VARIANTS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(txt)
	f.close()

func _write_cfg(cfg: Dictionary) -> void:
	_write(JSON.stringify(cfg))

func _remove() -> void:
	if FileAccess.file_exists(VARIANTS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS_PATH))

func before_each() -> void:
	_remove()

func _three_tier() -> Dictionary:
	return {"variants": [
		{"path": P_1080, "min_width": 0},
		{"path": P_2K, "min_width": 1921},
		{"path": P_4K, "min_width": 3000},
	]}

# 1. 无变体配置文件 → 原样回退主图（老项目行为不变）
func test_01_no_config_returns_fallback() -> void:
	var got := UIBackground.pick_bg_path(3840.0, FALLBACK, VARIANTS_PATH)
	expect(got == FALLBACK, "无配置时应回退主图，实际=%s" % got)

# 2. 视口 1600 → 命中 1080p 档（min_width=0）
func test_02_pick_1080p() -> void:
	_write_cfg(_three_tier())
	var got := UIBackground.pick_bg_path(1600.0, FALLBACK, VARIANTS_PATH)
	expect(got == P_1080, "1600 宽应命中 1080p 档，实际=%s" % got)

# 3. 视口 2560（2K） → 命中 min_width=1921 档
func test_03_pick_2k() -> void:
	_write_cfg(_three_tier())
	var got := UIBackground.pick_bg_path(2560.0, FALLBACK, VARIANTS_PATH)
	expect(got == P_2K, "2560 宽应命中 2K 档，实际=%s" % got)

# 4. 视口 3840（4K） → 命中 min_width=3000 档
func test_04_pick_4k() -> void:
	_write_cfg(_three_tier())
	var got := UIBackground.pick_bg_path(3840.0, FALLBACK, VARIANTS_PATH)
	expect(got == P_4K, "3840 宽应命中 4K 档，实际=%s" % got)

# 5. 视口比所有档位都小 → 兜底取最小的一档，而不是回退主图
func test_05_smaller_than_all_picks_smallest() -> void:
	_write_cfg({"variants": [
		{"path": P_2K, "min_width": 1921},
		{"path": P_4K, "min_width": 3000},
	]})
	var got := UIBackground.pick_bg_path(800.0, FALLBACK, VARIANTS_PATH)
	expect(got == P_2K, "视口小于所有档位时应取最小档，实际=%s" % got)

# 6. 图片文件不存在的档位要被跳过，退到次一档
func test_06_missing_file_skipped() -> void:
	_write_cfg({"variants": [
		{"path": P_1080, "min_width": 0},
		{"path": "res://assets/ui/_definitely_not_here.png", "min_width": 1921},
	]})
	var got := UIBackground.pick_bg_path(2560.0, FALLBACK, VARIANTS_PATH)
	expect(got == P_1080, "缺失文件的档位应被跳过，实际=%s" % got)

# 7. 空 variants / 坏 JSON / 结构不对 → 一律回退主图，绝不抛错
func test_07_invalid_config_falls_back() -> void:
	_write_cfg({"variants": []})
	expect(UIBackground.pick_bg_path(3840.0, FALLBACK, VARIANTS_PATH) == FALLBACK, "空 variants 应回退主图")
	_write("{ 这不是 json ")
	expect(UIBackground.pick_bg_path(3840.0, FALLBACK, VARIANTS_PATH) == FALLBACK, "坏 JSON 应回退主图")
	_write("[1,2,3]")
	expect(UIBackground.pick_bg_path(3840.0, FALLBACK, VARIANTS_PATH) == FALLBACK, "顶层非对象应回退主图")
	_write_cfg({"variants": ["不是对象", 123]})
	expect(UIBackground.pick_bg_path(3840.0, FALLBACK, VARIANTS_PATH) == FALLBACK, "元素非对象应回退主图")

# 8. 收尾：删掉测试临时文件（名字以 z 结尾，排序最后执行）
func test_zz_cleanup() -> void:
	_remove()
	expect(not FileAccess.file_exists(VARIANTS_PATH), "测试临时变体表应已删除")
