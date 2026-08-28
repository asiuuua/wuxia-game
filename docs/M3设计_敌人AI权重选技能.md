# M3 设计 · 敌人 AI 权重选技能（战斗窗口主权）

> 本文是 M3 第一项的设计稿（仅铺方案，实现待用户拍板）。
> 读者：战斗窗口实现 + 其他窗口（UI/背包）了解情况。
> 配套 SOP：开工前读最新《变更通告》+《契约总表》；收尾跑双闸门 + 写本窗口通告；共享地基只增不改。

## 0. 范围与定位
- 属于 **M3 第一项**：把当前「敌人纯普攻」升级为「按权重 + 条件 + 资源/cooldown 选招」的 CRPG 式 AI。
- 全部落在**战斗窗口主权**（`enemies.json` / `combat_character.gd` / `combat_core.gd` / `combat_service.gd` / `test_combat_smoke.gd`），**不动冻结共享地基**（`EventBus` / `*_enums` / `ConfigManager` / `screens.json` / `strings.csv`）。

## 1. 现状（已查代码确认）
- `combat_core.enemy_phase()`（combat_core.gd:119-133）**当前是纯普攻**：每个存活敌人只 `_resolve_hit(enemy, player, enemy.effective_attack())`，**完全没消费 `enemies.json.abilities`**，也无冷却/真气/权重判断。
- `enemies.json.abilities` 现是**一维字符串数组**（如 `["sword_001"]`），**没有权重/冷却/触发条件**；且 `sword_001` / `blade_001` 是**悬空引用**——`skills.json` 里根本没有这两个 id（真实技能是 `sword_qingsong_001` / `blade_duanshui_001` 等）。所以即便接上 AI，若不重定向也会因「技能不存在」被过滤回普攻。
- `CombatCharacter`（combat_character.gd）已具备 `cooldowns` / `mp` / `status_effects` / `effective_attack()`，敌人 `max_mp=30`（combat_service.gd:60），**施法资源齐备**。
- 🔴 **冷却从未递减（M1 隐性 bug）**：全工程 grep `cooldowns` 只有「设置」(combat_core.gd:68) 与「判定」(combat_core.gd:60)，**无任何减 1 逻辑**。意味着玩家/敌人一旦放招就永久进冷却、再放不出。M3 必须顺带修，否则敌人招式也是一次性。
- `SeededRNG.randf()` 存在（seeded_rng.gd:23），可取 `[0,1)` 浮点 → 加权随机可**确定性复现**，测试可控。

## 2. 目标
敌人按「权重 + 条件 + 资源/cooldown 可用性」选招；无可用招则普攻兜底；全程确定性可测；修复 M1 冷却 bug（顺带，属预期行为修正）。

## 3. 方案

### 3.1 配置 schema（enemies.json.abilities，向后兼容）
元素既支持旧字符串，也支持新对象：
```json
"abilities": [
  { "id": "sword_qingsong_001", "weight": 3, "condition": "always" },
  { "id": "sword_hanjian_001", "weight": 1, "condition": "player_hp_below:0.4" }
]
```
- `weight`：int，默认 1（权重越高越常选）。
- `condition`（M3 文法）：`always` | `player_hp_below:<0-1>` | `self_hp_below:<0-1>` | `self_mp_above:<0-1>`。后续可扩 `target_count_ge` 等。
- **悬空引用重定向**：`sword_001`→`sword_qingsong_001`，`blade_001`→`blade_duanshui_001`；并按敌人定位配权重/条件（头目低血斩杀、斥候有真气时开攻 buff 等示例见 §5）。

### 3.2 CombatCharacter.ai_kit（data/runtime/combat_character.gd）
战斗窗口主权，新增字段：
```gdscript
var ai_kit: Array = []   # 元素: {"id":String,"weight":int,"condition":String}
```
`combat_service.start_combat` 里把 `edata.get("abilities", [])` **归一化**为上述字典数组写入 `ec.ai_kit`（字符串元素→`{id:原串, weight:1, condition:"always"}`）。

### 3.3 冷却递减修复（combat_core.tick_unit）
`tick_unit(unit)` 末尾给 `unit` 自身 cooldowns 各减 1（floor 0）：
```gdscript
for k in unit.cooldowns.keys():
    unit.cooldowns[k] = max(0, unit.cooldowns[k] - 1)
```
`tick_unit(unit)` 恰在「每个单位自己回合开始」被调用（玩家 `_basic/_skill/_rest` 三动作 + `enemy_phase` 循环均调它），语义正确：冷却按「施法者自己的回合数」递减。
不影响现有测试：`player_skill` 在 tick 之后才 set cooldown（combat_core.gd:68-70），放招当回合断言 `cd==1` 仍成立；递减发生在下个该单位回合开始。

### 3.4 _cast_skill 抽取（combat_core，DRY）
把 `player_skill(slot)` 的施法结算抽出为通用方法，玩家与敌人共用，行为完全不变（双闸门保护）：
```gdscript
func _cast_skill(caster: CombatCharacter, ability_id: String, primary_target_id: String) -> Array[CombatEvent]
```
职责：`get_ability` → 校验 mp/cooldown → 扣 mp 发 `QI_COST`(带 actor_mp_after) → 设 cooldown 发 `COOLDOWN_SET` → 发 `ACTION_SKILL` → 按 `cfg.target` 解析目标（`all_enemies`→玩家；`self`/`all_allies`→自身；其余→primary_target）→ 逐个 `_resolve_hit` + `_try_down` + `_apply_status`。
`player_skill(slot)` 改为：校验 slot/ability_id 后 `return _cast_skill(state.player, ability_id, target_id)`。

### 3.5 enemy_use_skill + enemy_phase 权重选技（combat_core）
- `_ability_usable(enemy, ab) -> bool`：技能存在 + 未在 cd + `enemy.mp >= qi_cost` + condition 满足。
- `_pick_enemy_ability(enemy) -> Dictionary`：遍历 `enemy.ai_kit` 用 `_ability_usable` 过滤得候选，按 `weight` 用 `rng.randf()*total` 加权随机选；无候选返回 `{}`。
- `enemy_phase()` 重写：
  ```
  for enemy in get_alive_enemies():
      TURN_START(enemy)
      tick_unit(enemy)              # 含冷却递减
      if not enemy.is_alive(): continue
      ab = _pick_enemy_ability(enemy)
      if ab.is_empty():
          ACTION_BASIC(enemy) + _resolve_hit(enemy, player, enemy.effective_attack())   # 普攻兜底
      else:
          evs = _cast_skill(enemy, ab["id"], "player")
          if evs.is_empty(): ACTION_BASIC + _resolve_hit(...)        # 防御性兜底
      _try_down(player)
      if player.is_dead: break
  ```

### 3.6 演出层
`BattleView` 按 `CombatEvent.Type` 泛型分派，`ACTION_SKILL` / `ACTION_BASIC` 已支持（actor=敌人也能按 `character_id` 查到 panel，unit_hud 已按 id 注册）。**无需改演出层代码**，仅需在变更通告里注明「敌人技能事件 actor=敌方 id」供 UI 窗口知悉。

## 4. 验收（双闸门 + 单测）
- 单招敌人（mp 足）→ `enemy_phase` 含 `ACTION_SKILL` 且 `actor_id`=该敌人、`skill_id`=该招。
- 敌人 `mp=0` → 无 `ACTION_SKILL`，走普攻（`ACTION_BASIC`+`DAMAGE`）。
- 带 cd 招式：放后 `cd>0`，**下个敌人回合仍 cd>0 → 本回合普攻**；再下回合 `cd==0` → 可再放（冷却递减生效）。
- 条件门控：`player_hp_below:0.4` 仅当玩家血 <40% 才进候选。
- `--headless --quit` 零错误；`run_all.tscn` 零失败（战斗套件全绿）；固定 seed 同结果可复现。

## 5. 文件清单（战斗窗口主权，实现后交 UI 模块提交）
- `data/configs/npcs/enemies.json` — schema 扩 + 悬空引用重定向 + 权重/条件
- `data/runtime/combat_character.gd` — 增 `ai_kit`
- `services/combat/combat_core.gd` — `tick_unit` 冷却递减 + `_cast_skill` + `_ability_usable`/`_pick_enemy_ability`/`enemy_use_skill` + `enemy_phase` 重写
- `services/combat/combat_service.gd` — `start_combat` 归一化 `ai_kit`（`enemy_phase_events` 不变）
- `tests/unit/test_combat_smoke.gd` — +3~4 项
- `docs/变更通告_2026-08-29_敌人AI选技能.md` — 实现后写

## 6. 风险 / 注意
- **冷却递减虽修 M1 隐性 bug，但会改变玩家 cd 节奏**（cd=1 实际=隔 1 回合可再放）。属预期修正，双闸门 + 现有「cast 后 cd==1」测试覆盖，不会回归。
- **未动 `CombatEvent` 类型、未动 `combat_service` 公开签名** → 契约总表大概率无需重跑；若 `gen_contract` 顺带扫描 `combat_character.ai_kit` 字段，则由 UI/背包窗口在提交时一并重跑（不自行改背包窗口主权文件）。
- 不碰冻结共享地基；不碰背包/UI 主权文件；演出层零改动（仅通告知会）。
- 配置改动属战斗窗口主权，但 `enemies.json` 被 `ConfigManager` 读取（全局），改动需确保 JSON 合法（gen_contract/--quit 会校验）。
