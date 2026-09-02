# 08 · 静默接缝 BUG 四层防线

> 检索关键词：静默、接缝、mouse_filter、吞点击、lint、GATE0、GATE2、pre-commit、卡口令、防御
> 等级：E3

## 问题本质
「静默接缝 BUG」= 无报错但功能失效（最典型：装饰子节点 `mouse_filter=STOP(0)` 静默吞掉点击，玩家点不动）。这类 BUG 编译器不报、运行时不崩，靠肉眼/体感才发现，极难定位。

## mouse_filter 枚举反直觉（必记）
- `STOP = 0`：**拦截**（吞输入，装饰节点写了它就被静默吞点击）
- `PASS = 1`：放行
- `IGNORE = 2`：**穿透**（装饰子节点必须写这个，绝不可写 0）

## 四层 Enforcement
1. **GATE0 静态扫描**（`tools/lint_mouse_filter.py`）：提交前扫所有 `.tscn`，凡装饰子节点写 `mouse_filter=0` 即报错拦截。机器兜底，零漏网。
2. **GATE2 运行时断言**（`tests/unit/test_ui_mouse_filter.gd`）：单测里断言关键 UI 节点 `mouse_filter` 不为 STOP，门禁红即阻断。
3. **pre-commit 钩子**：接 GATE0，未改 `.tscn` 时跳过提示，改了则强制扫。
4. **启动卡口令**：新 AI/新窗口动手前先读「静默拦截守卫」说明，人工意识防线。

## 配套记忆机制
- 四层顺序：记忆（本文件）→ skill（wuxia-game-dev 静默接缝段）→ 启动卡口令 → 机器兜底（GATE0/GATE2）。任一层漏了下一层补。

## 其它静默类
- 信号名拼错 → NOTIFY 静默不触发（靠契约总表 + GATE2 接缝测试）。
- 同帧 `queue_free`+`change_scene` → 主菜单 freeze（靠 `_deferred_change_scene` 延迟一帧）。

## 关联
- 见 `06_卡住BUG根因与避免速查.md`（静默接缝类 BUG 行）
- 见 `07_双闸门门禁.md`（GATE0 属双闸门前置扫描）
- `tools/lint_mouse_filter.py` / `tests/unit/test_ui_mouse_filter.gd`（真源）
