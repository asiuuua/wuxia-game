# Godot 4.x 专项注意事项（参考规范第七部分，按本项目实测修正）

> 规范原文以 Godot 4.7 为目标，本项目当前用 **Godot 4.3 stable** 做 headless 校验。以下"坑"均经实测。

## 1. 已踩并解决的坑（本项目血泪）

| 坑 | 现象 | 解决 |
|---|---|---|
| autoload 与 `class_name` 同名 | `Class "X" hides an autoload singleton` | autoload 脚本**不写** `class_name X` |
| `DirAccess.dir_exists/make_dir_recursive` | Godot 4.x 改为非静态 | 改用 `DirAccess.dir_exists_absolute / make_dir_recursive_absolute` |
| `load().instantiate()` 用 `:=` 推断 | `Cannot infer type of "x"` | 显式类型：`var hud: Hud = load(...).instantiate()` |
| 变量名 `exp` / `log` | `same name as a built-in function` | 改名 `experience` / `entries` |
| `Performance.MONITOR_*` 旧名 | Godot 4 已移除 `MONITOR_` 前缀且常量名变更 | 改用稳定 API（`Engine.get_frames_per_second` / `OS.get_static_memory_usage`），脆弱常量不硬编码 |
| `.godot` 全局类缓存陈旧 | 新增 `class_name` 报 "not declared" | 删除 `.godot` 让 Godot 重新 import，或用 `--editor --quit` 重建索引 |
| 切场景时序 | `Parent node is busy adding/removing children` | `change_scene` 用 `call_deferred` |

## 2. 编码铁律（GDScript 4.x）

- 命名：snake_case 函数、PascalCase 类、ALL_CAPS 常量；tab 缩进（禁空格）。
- 无 `implements` 关键字：用抽象基类继承表达接口（如 `ISaveable`）。
- 信号新语法：`signal_name.emit(args)`，不用 `emit_signal("name", args)`。
- 禁止裸 `print()`：统一 `GameLogger`。
- 跨模块只走 `EventBus`；业务层不持有 Node；全局数据放 Autoload/GameManager。

## 3. 专项特性利用

| 特性 | 本项目用法 |
|---|---|
| Resource 系统 | 静态数据用 JSON（`data/configs`），运行时模型用 `RefCounted`（CombatCharacter/PlayerState 等） |
| 多线程 | 配置/存档后续可上 `WorkerThreadPool`（当前同步加载，量小够用） |
| InputMap | 移动/确认走 InputMap（`ui_right` 等），Phase 2 接入自定义映射 |
| TranslationServer | Phase 2 本地化（`_manifest` 已留 `LOCALIZATION_DIR`） |
| 信号重复连接 | 连接前 `is_connected` 检查，或用 `CONNECT_ONE_SHOT` |

## 4. project.godot 关键配置（当前）

```ini
[application]
config/name="武侠江湖"
config/version="0.5.0"
run/main_scene="res://scenes/bootstrap/Bootstrap.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")

[rendering]
renderer/rendering_method="gl_compatibility"   # 兼顾 PC/安卓/iOS/Web

[gdscript/warnings]
unused_signal=false   # EventBus 全局单例本类不 emit，关误报
```

> 注：规范建议 `forward_plus` + MSAA，但本项目首发目标含 Web/安卓，故用 `gl_compatibility` 保兼容。高端渲染留 Phase 4 平台适配再分档。
