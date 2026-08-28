extends SceneTree
class_name Diag

func _init():
	print("=== DIAG: root children ===")
	var root = get_root()
	for c in root.get_children():
		print("  child: ", c.name)
	print("=== DIAG: autoload presence (via /root/<name>) ===")
	for au_name in ["EventBus","ConfigManager","SaveManager","WeatherTimeService","GameManager","AudioManager"]:
		var n = root.get_node_or_null("/root/" + au_name)
		print("  %s -> %s" % [au_name, n != null])
	quit()
