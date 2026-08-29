# core/constants/ui_theme.gd
# UI 主题色板（集中管理，禁止在界面脚本里散落 Color(...) 字面量）
# 来源：docs/启动加载与主菜单UI详细设计.md §8.1 色彩规范
# 用法（跨模式安全：--script 下非 autoload class_name 不自动注册，消费方用 const UIPalette = preload(...) 兜底）：
#   const UIPalette = preload("res://core/constants/ui_theme.gd")
#   _label.add_theme_color_override("font_color", UIPalette.GOLD)

extends RefCounted
class_name UIPalette

# --- 背景 ---
const BG_DARK := Color(0.102, 0.086, 0.071)        # 主背景 深墨色 #1A1612
const PANEL_DARK := Color(0.169, 0.141, 0.125)    # 面板背景 深棕 #2B2420
const PAPER := Color(0.910, 0.863, 0.784)         # 宣纸色 #E8DCC8

# --- 文字 ---
const TEXT_MAIN := Color(0.941, 0.902, 0.820)      # 主文字 米白 #F0E6D2
const TEXT_SECONDARY := Color(0.659, 0.608, 0.549) # 次要文字 灰白 #A89B8C
const DISABLED := Color(0.420, 0.365, 0.322)       # 不可交互 灰色 #6B5D52

# --- 强调 / 状态 ---
const GOLD := Color(0.831, 0.686, 0.216)          # 高亮/选中 金色 #D4AF37
const GOLD_DARK := Color(0.788, 0.663, 0.380)      # 金色暗调 #C9A961
const DANGER := Color(0.545, 0.227, 0.227)         # 危险/删除 暗红 #8B3A3A
const SUCCESS := Color(0.290, 0.404, 0.255)        # 成功/确认 墨绿 #4A6741
const BADGE_RED := Color(0.91, 0.20, 0.20)         # 红点徽标 醒目红（姻缘可求婚提示）

# --- 进度条 ---
const PROGRESS_FILL := Color(0.239, 0.204, 0.169)  # 墨色渐变起 #3D342B
const HP_FILL := Color(0.78, 0.27, 0.27)           # 气血条 朱红
const MP_FILL := Color(0.30, 0.58, 0.86)           # 内力条 靛蓝
const XP_FILL := Color(0.831, 0.686, 0.216)        # 经验条 金
const ATTR_FILL := Color(0.45, 0.74, 0.55)        # 六维属性条 竹青
const PREG_FILL := Color(0.86, 0.55, 0.78)         # 孕期进度条 藕荷

# --- 模态遮罩（半透明黑，覆盖在面板之下）---
const DIM := Color(0.0, 0.0, 0.0, 0.5)             # 统一遮罩：原散落 0.45 / 0.55 → 收敛为一档

# --- 磨砂玻璃（弹窗 / 对话面板通用）---
# 半透冷调深蓝黑，让背后内容透出，视觉去棕黄化；细白边 + 柔和阴影"漂浮"感
const GLASS_BG := Color(0.071, 0.078, 0.110, 0.62)  # 主磨砂背景 透冷调 #12141C ~62%
const GLASS_BG_HOVER := Color(0.090, 0.098, 0.137, 0.78)  # 按钮 hover 加深
const GLASS_BORDER := Color(1.0, 1.0, 1.0, 0.20)    # 极细白边 20% 不抢戏
const GLASS_BORDER_FOCUS := Color(1.0, 1.0, 1.0, 0.55)  # 焦点态亮起
const GLASS_SHADOW := Color(0.0, 0.0, 0.0, 0.55)     # 阴影：黑色 55%

# --- 主菜单动态背景美术色（场景占位，非通用 UI 主题，仍集中管理避免裸字面量）---
const ART_MOUNTAIN := Color(0.137, 0.157, 0.180)  # 远山剪影
const ART_WATER := Color(0.078, 0.110, 0.137)      # 水面
const ART_CLOUD := Color(0.941, 0.902, 0.820, 0.05) # 云雾（宣纸色低透明）

# --- 字号（统一阶梯，界面覆盖字体大小时引用，禁止裸数字）---
const FS_TITLE := 22     # 面板标题
const FS_NAME := 20      # 卡片主名
const FS_BODY := 18      # 正文（与全局主题默认一致）
const FS_SUB := 16       # 次级说明
const FS_SMALL := 14     # 小字 / 标签
const FS_TINY := 12      # 辅助信息
const FS_MENU := 23      # 主菜单项
const FS_LOGO := 56      # 加载 / 主菜单 游戏名大标题

# --- 布局栅格（统一安全边距 / 头部 / 内容锚点，界面裸像素边距一律引用此处，禁止散落字面量）---
const MARGIN := 24          # 标准内容安全边距（左右 / 顶部基准）
const MARGIN_WIDE := 40     # 宽布局边距（设置 / 存档主体）
const MARGIN_TIP := 32      # 一指空隙（1080p 屏约一指指宽，底部/控件间的小呼吸）
const MARGIN_LIST := 60     # 列表区左右内缩
const HEADER_TOP := 16      # 顶部栏距顶
const HEADER_H := 72        # 顶部栏高度（返回 + 标题）
const CONTENT_TOP := 0.12   # 主体内容顶部锚点比例
const CONTENT_BOTTOM := 0.96 # 主体内容底部锚点比例
const FS_HEADER := 34       # 头部标题字号
