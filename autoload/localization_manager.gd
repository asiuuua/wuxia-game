# autoload/localization_manager.gd
# 本地化管理器：加载 data/configs/localization/strings.csv，
# 为每种语言构建 Translation 并注册到 TranslationServer；按设置切换 locale。
# 之后全局 tr(key) 即返回当前语言的文案。设计稿 §11.2
# 批D 子批4（ADR-0007 装配收敛）：原 autoload 降级为纯静态工具类——零实例状态
# （全部语言数据在 TranslationServer 全局单例），setup() 由 Bootstrap 生命周期壳调用。

class_name LocalizationManager
extends RefCounted

const CSV_PATH := "res://data/configs/localization/strings.csv"
const LOCALES := ["zh_CN", "zh_TW", "en"]

## 启动初始化（Bootstrap 生命周期壳调用）：加载 CSV + 按设置恢复语言
static func setup() -> void:
	_load_csv()
	# 批D 子批6：SettingsManager 已静态化——类静态调用恒可用，防御式 null 检查随之收编
	set_locale(SettingsManager.get_language())

static func _load_csv() -> void:
	if not FileAccess.file_exists(CSV_PATH):
		GameLogger.warn("Localization", "本地化文件缺失: %s" % CSV_PATH)
		return
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	# 去除 UTF-8 BOM，否则首列键名会被注入 \ufeff 前缀导致 tr() 失效
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	var lines := text.split("\n")
	if lines.size() < 2:
		return
	var header := lines[0].split(",")
	var translations := {}
	for i in range(1, header.size()):
		var loc: String = header[i].strip_edges()
		if not LOCALES.has(loc):
			continue
		var tr_obj = Translation.new()
		tr_obj.set_locale(loc)
		translations[loc] = tr_obj
	for r in range(1, lines.size()):
		var cells := lines[r].split(",")
		if cells.size() < 2:
			continue
		var key: String = cells[0].strip_edges()
		if key == "":
			continue
		for i in range(1, header.size()):
			var loc: String = header[i].strip_edges()
			if not translations.has(loc):
				continue
			if i >= cells.size():
				break
			var val: String = cells[i].strip_edges()
			(translations[loc] as Translation).add_message(key, val)
	for loc in translations.keys():
		TranslationServer.add_translation(translations[loc])
	GameLogger.info("Localization", "已加载 %d 种语言，%d 条文案" % [translations.size(), lines.size() - 1])

static func set_locale(locale: String) -> void:
	if not LOCALES.has(locale):
		locale = "zh_CN"
	TranslationServer.set_locale(locale)
