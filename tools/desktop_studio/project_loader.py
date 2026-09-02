#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Phase 2 工程适配器加载器（连接器骨架）。

读取 projects/*.yaml，暴露：
  - list_projects()          列出所有已配置工程（id / 名称 / 启用模块）
  - get_manifest(pid)        读取某工程完整 manifest
  - get_connector_info(pid)  前端"对接当前工程"时展示的精简信息
                             （模块 / AI上下文 / 换皮清单 / 经验库，不含巨量数据）

依赖：pyyaml（开发态 venv 已装）。exe 打包需在 spec 补 hiddenimports=pyyaml，
否则运行时会抛清晰错误提示，不会静默崩。
"""
import os
import glob

try:
    import yaml
except ImportError:
    yaml = None

PROJECTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "projects")

# 模板文件不是可对接工程，版本下拉需排除
_TEMPLATE_IDS = {"manifest_template"}


def _load_raw(project_id):
    p = os.path.join(PROJECTS_DIR, "%s.yaml" % project_id)
    if not os.path.exists(p):
        return None
    if yaml is None:
        raise RuntimeError(
            "缺少 pyyaml：开发态请 `pip install pyyaml`；"
            "exe 打包需在 工作室专业调教.spec 的 hiddenimports 补 pyyaml"
        )
    with open(p, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def list_projects():
    """列出所有工程的概览，供前端版本下拉/总控台使用。"""
    out = []
    for p in sorted(glob.glob(os.path.join(PROJECTS_DIR, "*.yaml"))):
        pid = os.path.splitext(os.path.basename(p))[0]
        if pid in _TEMPLATE_IDS:
            continue
        try:
            d = _load_raw(pid)
        except Exception:
            d = None
        out.append({
            "project_id": pid,
            "display_name": (d or {}).get("display_name", pid),
            "modules": (d or {}).get("modules", []),
        })
    return out


def get_manifest(project_id):
    return _load_raw(project_id)


def get_connector_info(project_id):
    """前端对接当前工程时展示的精简信息（连接器视图，不搬数据）。"""
    d = _load_raw(project_id)
    if d is None:
        return None
    return {
        "project_id": project_id,
        "display_name": d.get("display_name"),
        "modules": d.get("modules", []),
        "ai_context": d.get("ai_context", {}),
        "reskin": d.get("reskin", {}),
        "knowledge": d.get("knowledge", {}),
        "data_root": d.get("data_root"),
        "git_repo": d.get("git_repo"),
    }
