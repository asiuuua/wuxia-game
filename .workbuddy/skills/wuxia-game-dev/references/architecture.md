# 架构与目录职责地图

## 一、分层与依赖方向

```
autoload → core → data → services(RefCounted) → scenes → resources/tests/tools
```

- **单向依赖**：下层不反向依赖上层；跨模块通信只走 `EventBus`（全局事件总线），禁止直接持有对方 Node/脚本。
- **四底线**：单向依赖 / 跨模块只走 EventBus / 数值全进 JSON / 命名见名知意。
- **业务层不持有 Node**：`services/` 下均为 `RefCounted`，逻辑与场景树解耦；需要节点时通过 GameManager 装配或 EventBus 通知 scenes 层。
- **GameManager** = 装配中枢：`PlayerState` + 9 个 Service + `pending_battle_id`。**GameState** = 存档唯一来源。

## 二、autoload（全局单例，按职责）

| 文件 | 职责 |
|---|---|
| `EventBus.gd` | 跨模块事件总线（唯一通道）；新增信号须 `@warning_ignore("unused_signal")` 且写《变更通告》 |
| `ConfigManager.gd` | 配置加载（冻结，只增不改） |
| `GameManager.gd` | 装配中枢，驱动战斗/存档/天数推进（`advance_days` 等） |
| `GameState.gd` | 存档唯一来源（运行时状态真源） |
| `ui_manager.gd` | UI 6 层 CanvasLayer + 屏幕栈 + `popup_close_requested` 收口 |
| `SaveManager.gd` / `save_validator.gd` | 存档读写与校验 |
| `AudioManager.gd` | 音频 |
| `transition_manager.gd` | 场景转场（layer 100） |
| `settings_manager.gd` / `localization_manager.gd` | 设置 / 本地化 |
| `difficulty_manager.gd` | 难度 |
| `weather_time_service.gd` | 天气时间 |
| `patch_manager.gd` | 热更/补丁 |
| `defeat_handler.gd` / `error_handler.gd` | 失败/错误处理 |

## 三、core（引擎级能力，RefCounted/工具）

- `combat_entity_pool.gd`：战斗实体对象池（池化 Label 飘字，`reset` 须同步 `free()` 清节点）。
- `combat_event_renderer.gd`：战斗事件渲染（static 方法内调用同类 static 须加 `CombatEventRenderer.` 前缀）。
- `item_flags.gd` / `resource_manager.gd` / `streaming_media_loader.gd` / `portrait_cache_manager.gd`：物品/资源/流式媒体/立绘缓存。
- `constants/`（含 `ui_theme.gd`，主题色常量，冻结边界外但 UI 主权内）、`enums/*_enums.gd`（冻结）、`extensions/`、`interfaces/`、`utils/`。

## 四、services（业务服务，RefCounted）

已知：`inventory_service`（背包：增删改查/堆叠/负重/锁定/事务 `InventoryTransaction`/`iid` 全局发号/存档 roundtrip）、`equipment_service`（装备换装保留 `iid` 与耐久）、`ability_service`（武学装备/冷却，`notify_skill_bar_changed`+`notify_skill_cd_update`）、`quest_service`（任务，`notify_quest_track_changed`）、`romance_service`（结缘/欢庆每日配额）、`combat_service`（战斗门面 + 战术网格部署）。各 service 有主权，跨窗只派单不直改。

## 五、scenes

- `scenes/ui/`：`components/`（ConfirmDialog/SaveCard/MenuItem/UIBackground/Tooltip）、`overlays/`（attributes/inventory/bond_romance/celebration/dialog/map）、`screens/`（abilities/alchemy/battle/equipment/esc_menu/forge/game_menu/sect/settings/shop + `base_screen.gd`/`popup_base.gd`）、`ui_center_utils.gd`（居中+玻璃样式）、`icon_registry.gd`（图标注册 `get_icon/has_icon`）。
- `scenes/gameplay/battle/`：`battle_entity.gd`（实体+飘字+血条）、`tactical_battle_scene.gd`（战术战棋视图层）。
- `scenes/world/`：`town/`（`TownScene` 根 Node2D）——注意 `TownScene:52` 掉血崩为 open 派单。

## 六、data（数值与配置，全 JSON）

- `data/configs/ui/screens.json`（屏幕注册，**冻结**）、`data/configs/ui/menu_config.json`（菜单配置驱动）、`data/configs/bond/celebrations.json`（欢庆内容表=开放接口）、`data/configs/npcs/town_npcs.json`（`tactical_demo_master` 触发战术战斗 demo）。
- 其余系统数值（物品/技能/敌人/任务）均 JSON 化，禁硬编码到 `.gd`。

## 七、tools（开发基础设施）

- `commit_queue.py`：git 提交队列（精确 `git add` 队列化，每小时自动化出队）。
- `handoff.py`：隐患传递板（open→claimed→done→followup→closed）。
- `gen_contract.gd`：接口契约生成 → `docs/契约总表.md`（动接口后必跑）。
- `validate_project.gd` / `gate_check.sh` / `wip_check.sh` / `signal_audit.py`：批量校验/门禁/WIP 检查/信号审计。
- `verify_*.gd`：P0 主题/本地化等专项校验。
- `config_editor/` `item_editor/` `story_import/` `debug_overlay/`：编辑器辅助。

## 八、tests/unit

- 34 个 `test_*.gd`（继承 `TestBase`），由 `run_all.tscn` 同步驱动（不 `await`）；`expect()` 断言；**测试内不能用 lambda 捕获外层局部变量**（GDScript 4.7.2 失效）。
- 新增测试须落入 `tests/unit/` 且文件名 `test_*.gd` 才会被 `run_all` 扫描。
