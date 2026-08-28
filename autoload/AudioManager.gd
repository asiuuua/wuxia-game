# autoload/AudioManager.gd
# 音频管理器：统一播放 BGM / SFX，音量分级符合资源规范
# 规范：BGM 0.6 / SFX 0.8 / Voice 1.0

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

const VOLUME_BGM := 0.6
const VOLUME_SFX := 0.8
const VOLUME_VOICE := 1.0

var _bgm_player: AudioStreamPlayer = null  # 当前 BGM 播放器（持久，循环播放）
var _bgm_path: String = ""                 # 当前 BGM 资源路径（用于去重）

## 启动初始化（由 Bootstrap 调用；当前为占位，Phase 2 接入总线与资源管理）
func setup() -> void:
	GameLogger.info("Audio", "AudioManager 就绪")
	pass

## 确保指定名称的总线存在（不存在则在 Master 下新建）。返回总线索引
func ensure_bus(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		return idx
	AudioServer.add_bus(AudioServer.get_bus_count())
	idx = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx

## 设置某条总线的音量（线性 0..1）。供 SettingsManager 实时调节并持久化
func set_bus_volume(bus_name: String, linear: float) -> void:
	if linear < 0.0:
		linear = 0.0
	if linear > 1.0:
		linear = 1.0
	var idx: int = ensure_bus(bus_name)
	AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

func play_sfx(path: String) -> void:
	if path == "":
		return
	var sfx: AudioStream = load(path)
	if sfx == null:
		push_warning("[Audio] 音效缺失: %s" % path)
		return
	var player := AudioStreamPlayer.new()
	player.stream = sfx
	player.volume_db = linear_to_db(VOLUME_SFX)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

## UI 音效（2026-08-29 配置表驱动）
## 事件名 -> 路径/音量，配置见 data/configs/ui/ui_sfx.json；换音色只改表不动代码。
## 设计要点：
##   - 音频文件缺失时**静默跳过**不刷 warning（占位期文件还没到位，避免日志噪声）
##   - 走独立 SFX 总线，音量由配置表逐事件指定
##   - 用播放器池轮询，避免鼠标快速划过多个按钮时频繁创建/销毁节点
var _ui_sfx_pool: Array[AudioStreamPlayer] = []
var _ui_sfx_cursor: int = 0

func play_ui_sfx(event: String) -> void:
	if event == "" or ConfigManager == null:
		return
	var cfg: Dictionary = ConfigManager.get_ui_sfx(event)
	if cfg.is_empty():
		return
	var path: String = String(cfg.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return  # 占位期：文件未到位就静默跳过
	var bus_name: String = ConfigManager.get_ui_sfx_bus()
	_ensure_ui_sfx_pool(bus_name)
	var player: AudioStreamPlayer = _next_ui_sfx_player()
	if player == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	player.stream = stream
	player.volume_db = float(cfg.get("volume_db", -8.0))
	player.play()

## 确保池内播放器数量达到配置值，并挂到指定总线
func _ensure_ui_sfx_pool(bus_name: String) -> void:
	ensure_bus(bus_name)
	var want: int = ConfigManager.get_ui_sfx_pool_size()
	while _ui_sfx_pool.size() < want:
		var p := AudioStreamPlayer.new()
		p.name = "UISfx%d" % _ui_sfx_pool.size()
		p.bus = bus_name
		add_child(p)
		_ui_sfx_pool.append(p)

## 优先返回空闲播放器；全忙则轮询复用（覆盖最旧的一个，避免声音被完全吞掉）
func _next_ui_sfx_player() -> AudioStreamPlayer:
	if _ui_sfx_pool.is_empty():
		return null
	for p in _ui_sfx_pool:
		if not p.playing:
			return p
	var chosen: AudioStreamPlayer = _ui_sfx_pool[_ui_sfx_cursor % _ui_sfx_pool.size()]
	_ui_sfx_cursor += 1
	return chosen

func play_bgm(path: String) -> void:
	if path == "":
		return
	# 已在播同一首则忽略（避免重复叠加）；只要路径相同即视为同一首
	if _bgm_player != null and _bgm_path == path:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("[Audio] BGM 缺失: %s" % path)
		return
	stop_bgm()
	# 独立 BGM 总线，音量按规范 VOLUME_BGM=0.6
	var bus_idx: int = ensure_bus("Music")
	# 背景音乐音量统一交由 SettingsManager（audio.music）管理，避免与设置界面双总线不一致
	var music_vol: float = VOLUME_BGM
	if SettingsManager != null and SettingsManager.has_method("get_audio_volume"):
		music_vol = SettingsManager.get_audio_volume("music")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(music_vol))
	# 让音频资源循环播放
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop = true
	var player := AudioStreamPlayer.new()
	player.name = "BGMPlayer"
	player.bus = "Music"
	player.stream = stream
	add_child(player)
	player.play()
	_bgm_player = player
	_bgm_path = path

## 停止当前 BGM 并释放播放器
func stop_bgm() -> void:
	if _bgm_player != null:
		_bgm_player.stop()
		_bgm_player.queue_free()
		_bgm_player = null
		_bgm_path = ""
