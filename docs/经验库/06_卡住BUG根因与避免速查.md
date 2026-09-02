# 06 · 卡住很久的 BUG 根因与避免速查

> 检索关键词：BUG、根因、修复、避免、键盘失效、经济漏洞、脏档、freeze、纹理压缩、town.json

| BUG | 等级 | 根因 | 解决 | 以后怎么避免 |
|---|---|---|---|---|
| **BUG-01** UIManager 缓存屏重开未回写屏幕栈 | Critical | 关缓存屏后屏幕栈未回写，重开时键盘输入全失效（无报错） | UIManager 重开恢复屏幕栈 + 焦点 | GATE2 信号接缝测试 + 启动卡口令 |
| **主菜单 freeze** | High | `queue_free` 与 `change_scene_to_file` 同帧竞争，节点半销毁即切场景 | 延迟一帧 `_deferred_change_scene`（先 `call_deferred` 再切） | 切场景前 `call_deferred`，禁止同帧 free+change |
| **BUG-04** 商店售卖锁定物/任务物换钱 | High | `sell` 用含锁定 `get_item_count` 预检，只扣未锁定却按全量付钱 | 改用 `get_unlocked_count` 预检 | 任何「被动移除」预检都用非锁定可用量 |
| **BUG-03** 关系双写脏档 | High | 好感与关系字典两处持有，双写不同步 | 状态下沉唯一真源（`BondService` 管好感、`RomanceService` 管配偶、`Sworn`/`Master` 管结义师徒） | 任何「关系/状态」只一处持有，查询走聚合门面 |
| **BUG-06** WeddingScene 绕过回城钩子 | Mid | 婚礼场景直接切走未走回城编排 | 婚礼结束经 `bond_wedding_started` + GameManager 回城钩子 | 场景切换统一走 GameManager 编排 |
| **BUG-14** town.json 误删 | 教训 | 当死数据删，实为战术底图几何依赖 | 从 git 恢复 + 记入变更通告 | 删文件先查引用/变更通告，勿臆测 |
| **纹理压缩 latent bug** | High | 改纹理压缩 mode=2 后 UI 取像素逻辑暴露 latent bug | 诊断先看日志刷屏量，不臆测硬件；`Image.load_png_from_buffer` 解码源 PNG | 压缩改动后跑 GATE1，刷屏先查日志量 |
| **静默接缝类 BUG** | 高频 | 装饰子节点 `mouse_filter=STOP(0)` 吞点击，无报错 | `lint_mouse_filter.py`(GATE0) + `test_ui_mouse_filter.gd`(GATE2) + pre-commit + 启动卡口令 | 装饰子节点必须写 IGNORE(2)，绝不可写 0 |

## 通用避免铁律
1. **切场景**：`call_deferred` 延迟一帧，禁止同帧 `queue_free` + `change_scene`。
2. **资产操作**：先预检（can_add / get_unlocked_count）再 apply，失败回滚；被动移除用非锁定量。
3. **状态**：单一真源，拒绝双写；查询走聚合门面。
4. **删文件**：先查引用与变更通告，勿当死数据删。
5. **装饰节点**：`mouse_filter` 必须 IGNORE(2)，STOP(0) 会静默吞输入。

## 关联
- 见 `03_经济系统_事务化资产API.md`（BUG-04 修复细节）
- 见 `04_结缘系统_单一真源与回城编排.md`（BUG-03 修复细节）
- 见 `07_双闸门门禁.md` / `08_静默接缝BUG四层防线.md`（防线）
