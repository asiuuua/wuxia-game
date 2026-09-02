# 10 · 平台连接器三段（ai_context / reskin / knowledge）

> 检索关键词：平台、连接器、容器、换皮、ai_context、reskin、knowledge、manifest、版本切换、经验复用
> 等级：E4

## 平台本质再定位：连接器而非容器
- 平台**只对接工程、不持有工程数据**；方便不同职能人员（美工/前端/架构/PM/代码审核/任务追踪/剧情）工作。
- 三大复用能力 = **ai_context**（新 AI 秒懂架构）+ **reskin**（换皮不换药）+ **knowledge**（经验复用）。
- 远程访问（Phase 4）**已决策延后**（紧迫度极低，需要时一步扩展）。

## 二维解耦
- 横向 **Domain Module**：UI视觉 / 剧情创作 / 战斗关卡 / 资产资源 / 系统治理。
- 纵向 **Project Adapter**：每个工程一份 `manifest.yaml`，一键版本切换对接各自工程。

## 三段模板（manifest.yaml）
```yaml
project_id: wuxia_game
display_name: 武侠江湖
data_root: D:/武侠游戏          # 仅指向工程，不复制数据
git_repo: ...
modules: [...]                  # 该工程可见的 Domain Module
adapters: [...]                 # 版本切换适配
ai_context:                    # ① 新 AI 秒懂架构意图
  architecture_intent: "等距2.5D 武侠 RPG；分层 autoload→core→data→services→scenes"
  key_decisions: [...]
  conventions: [...]
  common_pitfalls: [...]        # 前人踩坑（对齐 06/08）
  role_responsibilities: [...]  # 主权边界
reskin:                        # ② 换皮不换药
  swappable: [立绘, 登录背景, 按钮, 音频, 剧情]   # 小白只换这些
  locked: [底层逻辑, 数据结构, 服务契约]
knowledge:                     # ③ 经验复用
  refs: [docs/项目经验白皮书.md, docs/经验库/*.md, docs/契约总表.md, ...]
  reusable_patterns: [...]
  predecessor_mistakes: [...]
```

## 连接器端点（studio_server）
- `GET /api/projects` → 列出可对接工程（版本切换下拉源）。
- `GET /api/project/manifest/<id>` → 返回 modules / ai_context / reskin / knowledge（**不搬工程数据**）。
- 经验库面板读 `knowledge.refs` 渲染可检索条目（见工作室「经验库」标签页）。

## 远程决策
- Phase 4 远程访问**延后**：本地化优先，端口自动顺延（8765 被占试 8766..+20），用户免调端口。
- 跨项目知识复用 + 换皮模板 = 连接器核心，已落地 `manifest_template.yaml` + `wuxia_game.yaml` 实配。

## 关联
- 见 `09_可复用模式清单.md`（连接器三段作为可复用模式）
- `tools/desktop_studio/projects/manifest_template.yaml`（模板真源）
- `tools/desktop_studio/project_loader.py`（连接器读取逻辑）
