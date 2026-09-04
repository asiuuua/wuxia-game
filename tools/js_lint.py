# -*- coding: utf-8 -*-
"""
js_lint.py — index.html 内联脚本语法门禁（第三阶段·代码审查报告整改 2026-09-04）
================================================================
背景：desktop_studio/index.html 为 3950 行单文件 SPA，HTML+CSS+JS 全内联、无构建无 lint。
曾发生「JS 语法错误（未闭合括号）致整页脚本失效」（变更日志 L314，只能运行时暴露）。
本门禁：抽取 index.html 全部内联 <script>（无 src）块，逐块交给 node --check 做语法校验
（零构建、零改动，只检查）。任何语法错误直接阻断提交。
退出码 0=全部通过；供 verify_all.py 调用（也可单独跑）。
"""
import os
import re
import sys
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TARGET = os.path.join(ROOT, "tools", "desktop_studio", "index.html")
NODE = os.environ.get("NODE") or os.path.expanduser(
    "~/.workbuddy/binaries/node/versions/22.22.2-2/node.exe"
)


def extract_scripts(html: str):
    """抽取内联 <script> 块（跳过带 src 与 type=module 的外链/模块标签），返回 [(序号, 起始行, 代码)]。"""
    out = []
    for m in re.finditer(r"<script\b([^>]*)>(.*?)</script>", html, re.S | re.I):
        attrs, code = m.group(1), m.group(2)
        if re.search(r"\bsrc\s*=", attrs, re.I):
            continue
        if re.search(r"\btype\s*=\s*[\"']module[\"']", attrs, re.I):
            continue
        start_line = html[: m.start()].count("\n") + 1
        code = code.strip()
        if code:
            out.append((len(out) + 1, start_line, code))
    return out


def main() -> int:
    if not os.path.exists(NODE):
        print("GATE9 ⚠ 未找到 node（%s），跳过 JS 语法门禁（不拦截）" % NODE)
        return 0
    html = open(TARGET, encoding="utf-8", errors="replace").read()
    blocks = extract_scripts(html)
    if not blocks:
        print("GATE9 ⚠ index.html 未发现内联脚本，跳过")
        return 0
    failures = 0
    for idx, start_line, code in blocks:
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as tf:
            tf.write(code)
            tmp = tf.name
        try:
            p = subprocess.run([NODE, "--check", tmp], capture_output=True, text=True, errors="replace")
            if p.returncode != 0:
                failures += 1
                first_err = (p.stderr or "").strip().splitlines()
                print("   ✗ 内联脚本 #%d（index.html 第 %d 行起）语法错误：" % (idx, start_line))
                for ln in first_err[:3]:
                    print("      " + ln.strip())
        finally:
            os.unlink(tmp)
    if failures:
        print("GATE9 ✗ JS 语法门禁：%d/%d 块内联脚本语法错误（node --check）" % (failures, len(blocks)))
        return 1
    print("GATE9 ✓ JS 语法门禁：%d 块内联脚本全部通过 node --check" % len(blocks))
    return 0


if __name__ == "__main__":
    sys.exit(main())
