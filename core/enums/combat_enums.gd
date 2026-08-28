# core/enums/combat_enums.gd
# 战斗相关枚举

extends RefCounted
class_name CombatEnums

enum CombatResult { NONE, VICTORY, DEFEAT, FLEE }
enum CombatType { ENCOUNTER, BOSS, STORY }
enum TurnMode { SEQUENTIAL, ATB }   # 回合模式：固定顺序(缺省回落) / ATB 行动值(对标逸剑集气条)
enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE, HELL }
# 难度团灭死亡行为（基础动作，与具体惩罚参数分离，全部配置驱动）
enum DefeatBehaviour { RETRY_COMBAT, LOAD_LATEST_SAVE, TRIGGER_QUEST_FAIL, RESPAWN_CHECKPOINT, DELETE_SAVE }
enum DamageType { PHYSICAL, POISON, FIRE, ICE, DARK, INTERNAL }
enum EffectType { BUFF, DEBUFF, DOT, HOT, CONTROL, SHIELD, REFLECT, REVIVE }
enum TargetType { SELF, SINGLE_ENEMY, ALL_ENEMIES, SINGLE_ALLY, ALL_ALLIES }
enum AIState { IDLE, CHASE, ATTACK, GUARD, FLEE }
