# core/constants/path_constants.gd
# 资源/场景路径集中管理：禁止在代码中硬编码路径字符串

extends RefCounted
class_name PathConstants

const SCENE_BOOTSTRAP := "res://scenes/bootstrap/Bootstrap.tscn"
const SCENE_TOWN := "res://scenes/gameplay/town/TownScene.tscn"
const SCENE_BATTLE := "res://scenes/gameplay/battle/BattleScene.tscn"
const SCENE_TACTICAL_BATTLE := "res://scenes/gameplay/battle/TacticalBattleScene.tscn"
const SCENE_HUD := "res://scenes/ui/overlays/hud/Hud.tscn"
const SCENE_DIALOG := "res://scenes/ui/overlays/dialog/DialogOverlay.tscn"
const ICON_DIR := "res://resources/textures/icons/"
const LOCALIZATION_DIR := "res://resources/localization/"
