#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 docs/AI协同启动卡.md 生成 tools/desktop_studio/startup_card.json。

用途：让「工作室后台」里的「🤝 协同启动卡」标签页有一份结构化数据可直接渲染，
且日后 docs/AI协同启动卡.md 改了，只需重跑本脚本即可重新同步（保持单一真源）。

解析目标（与 docs/AI协同启动卡.md 的结构强绑定，改文档结构时需同步本脚本）：
  - §1 窗口一览表（markdown 表格）→ windows[].name/signature/sovereignty/duty
  - §2 各窗口启动口令（### <图标> <窗口名>窗口 后的 ``` 代码块）→ windows[].command
  - §3 通用启动口令模板（## 3. 后的 ``` 代码块）→ template
  - §4 各窗口专属「别踩的坑」（- **<窗口名>**：… 列表）→ windows[].pitfalls

纯标准库；用任意 Python 3 运行。
"""

import os
import re
import json

MODULE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(MODULE_DIR))
DOC = os.path.join(REPO_ROOT, "docs", "AI协同启动卡.md")
OUT = os.path.join(MODULE_DIR, "startup_card.json")


def _strip_icon(name: str) -> str:
    """去掉 '🔥 战斗窗口' 里的图标与 '窗口' 后缀，得到 '战斗'。"""
    s = name.strip()
    # 去掉开头的可能 emoji/符号（非中文/字母/数字开头的部分）
    m = re.match(r"^[^\u4e00-\u9fffA-Za-z0-9]*([\u4e00-\u9fffA-Za-z0-9].*)$", s)
    if m:
        s = m.group(1)
    if s.endswith("窗口"):
        s = s[:-2]
    return s.strip()


def parse(doc_text: str):
    lines = doc_text.splitlines()
    windows = {}           # name -> dict
    order = []             # 保持表格顺序
    pitfalls = {}          # name -> text
    template = ""
    fences = {}            # heading -> code block text

    # ---- 第一遍：抓表格(§1) + 代码块(§2/§3) ----
    in_table = False
    heading = None
    capture = False
    buf = []
    for ln in lines:
        s = ln.strip()
        if s.startswith("## 1."):
            in_table = True
            continue
        if in_table and s.startswith("## 2."):
            in_table = False
        if in_table and s.startswith("|"):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if len(cells) < 4:
                continue
            name = cells[0]
            if name in ("窗口名",) or set(name) <= set("-"):
                continue  # 表头 / 分隔行
            if name not in windows:
                windows[name] = {
                    "name": name,
                    "signature": cells[1],
                    "sovereignty": cells[2],
                    "duty": cells[3],
                    "command": "",
                    "pitfalls": "",
                }
                order.append(name)
            continue
        # 代码块捕获（## / ### 标题之后的 ``` 块）
        if s.startswith("## ") or s.startswith("### "):
            heading = s
            capture = False
            buf = []
            continue
        if s.startswith("```") and not capture:
            capture = True
            buf = []
            continue
        if s.startswith("```") and capture:
            capture = False
            fences[heading] = "\n".join(buf).strip("\n")
            continue
        if capture:
            buf.append(ln)

    # ---- 第二遍：映射 §2 口令到窗口 + 提取 §3 模板 ----
    def _norm(s: str) -> str:
        return re.sub(r"\s+", "", s)  # 去掉空格，使 "PM / 集成" 与 "PM/集成" 对齐

    for h, code in fences.items():
        if h and h.startswith("## 3."):
            template = code
            continue
        if h and ("窗口" in h):
            wn = _norm(_strip_icon(h))
            if wn in windows:
                windows[wn]["command"] = code

    # ---- 第三遍：§4 避坑清单 ----
    in_pit = False
    for ln in lines:
        s = ln.strip()
        if s.startswith("## 4."):
            in_pit = True
            continue
        if in_pit and s.startswith("## 5."):
            in_pit = False
        if in_pit and s.startswith("- **"):
            m = re.match(r"-\s*\*\*([^*]+)\*\*[:：]\s*(.*)$", s)
            if m:
                wn = m.group(1).strip()
                txt = m.group(2).strip()
                if wn in pitfalls:
                    pitfalls[wn] += "；" + txt
                else:
                    pitfalls[wn] = txt

    for wn in order:
        if wn in pitfalls:
            windows[wn]["pitfalls"] = pitfalls[wn]

    return {
        "updated": "",
        "source": "docs/AI协同启动卡.md",
        "windows": [windows[w] for w in order],
        "template": template,
    }


def main():
    if not os.path.exists(DOC):
        raise SystemExit("找不到文档: %s" % DOC)
    text = open(DOC, encoding="utf-8").read()
    data = parse(text)
    # 更新时间
    import datetime
    data["updated"] = datetime.date.today().isoformat()
    # 兜底：没有专属口令的窗口用通用模板
    for w in data["windows"]:
        if not w["command"]:
            w["command"] = data["template"]
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print("✓ 已生成 %s" % OUT)
    print("  窗口数: %d" % len(data["windows"]))
    print("  有专属口令: %d / 通用模板长度: %d" % (
        sum(1 for w in data["windows"] if w.get("command") and w["command"] != data["template"]),
        len(data["template"])))


if __name__ == "__main__":
    main()
