# 武侠江湖 · Godot 工程骨架（企业级分层架构）

等距 2.5D 武侠 RPG（单机）。Godot 4.7 工程，遵循 `docs/开发规范.md` 的
**架构分层 · 事件驱动 · 数据驱动 · 命名规范** 四底线。

## 如何打开 / 运行
1. 安装 Godot 4.7：https://godotengine.org
2. 打开 Godot → **Import**（导入）→ 选择本目录的 `project.godot`
3. 按 F5 运行：Bootstrap → 主菜单 → 新游戏进入城镇 → 与 NPC 交互进入战斗演示

> 工程用 `config_version=5`，兼容 Godot 4.x。

## 架构分层（详见 docs/开发规范.md）
```
表现层 Scene/Node  →  业务层 Service(RefCounted)  →  数据层 Config/Repository
        ↓ 只调服务                ↓ 只走 EventBus                  ↑ 读配置
   事件总线 EventBus（Autoload）统一解耦跨模块通信
```

## 目录结构（核心）
```
武侠游戏/
├── project.godot            # 工程配置 + 5 个 Autoload 单例
├── autoload/                # EventBus / ConfigManager / SaveManager / AudioManager / GameManager
├── core/                    # 基础层：constants / enums / utils / extensions / interfaces
├── data/
│   ├── configs/             # 配置表 JSON（abilities / items / quests / npcs / scenes）
│   ├── schemas/             # 静态数据 Resource（ItemData / WeaponData / AbilityData…）
│   └── runtime/             # 运行时数据（ItemInstance / PlayerState / QuestState）
├── services/                # 业务层：combat / inventory / ability / quest（RefCounted）
├── scenes/                  # 表现层：bootstrap / ui / gameplay / actors
├── resources/               # 资源层：textures / audio / localization…
├── tests/                   # 单元测试 / 集成测试
├── tools/                   # 编辑器工具 / 调试面板
└── docs/                    # GDD / 开发规范 / 代码规范 / 模块设计
```

## 本次交付（重构对齐企业级标准）
- **5 个 Autoload**：EventBus（事件总线）、ConfigManager（配置表）、
  SaveManager（存档）、AudioManager（音频）、GameManager（状态+服务持有）
- **core 基础层**：常量 / 枚举 / 工具 / 扩展 / 接口（ISaveable 等）
- **data 层**：schemas（Resource）+ runtime（存档载体）+ configs（JSON）
- **services 业务层**：combat（回合+自动战斗）/ inventory（背包）/
  ability（武学）/ quest（任务），全部数据驱动、信号解耦
- **scenes 表现层**：Bootstrap 启动 → 主菜单 → 城镇 → 战斗演示，可独立运行
- 旧 `scripts/` 旧结构已整体废弃并删除

## 关键纪律（强制）
- 业务层不持有 Node 引用；跨模块只走 EventBus；逻辑与数据分离
- 所有数值写在 `data/configs/*.json`，禁止硬编码
- 提交前过 `docs/代码规范.md` 自检清单

## 路线图
Phase 0 脚手架（已交付）→ Phase 1（城镇+战斗垂直切片）→ Phase 2（系统填充）
→ Phase 3（内容扩张）→ Phase 4（安卓/iOS/Web 适配）。

> iOS 导出需 Mac + 苹果开发者账号；Web 导出有包体/线程限制，放后期。
