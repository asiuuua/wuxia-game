# core/enums/quest_enums.gd
# 任务相关枚举

extends RefCounted
class_name QuestEnums

enum QuestType { MAIN, SIDE, DAILY, FACTION, HIDDEN }
enum QuestStatus { INACTIVE, ACTIVE, COMPLETED, TURNED_IN, FAILED, ABANDONED, FAIL_DEAD_NPC, FAIL_ESCAPED }
enum ObjectiveType { KILL, COLLECT, LOCATION, TALK, CHOICE }
enum QuestAcceptType { NPC, AUTO, ITEM, SCENE }
