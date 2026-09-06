# -*- coding: utf-8 -*-
"""任务（QuestGraph）内容域服务：任务流程图的读取 / 引用校验 / 写回。

只处理 regions/<region>/quests.json 中 type == "quest_graph" 的节点；
写回前校验节点引用（防止写坏运行时图），写操作经 QuestRepository 收口。
"""

import os

from services import _common
from services._common import (  # noqa: F401  门面透传用
    _safe_id, _is_valid_id, _ensure_dirs, load_settings, save_settings,
    load_json, _backup, _backup_dir,
    SAFETY_DIR, TRASH_DIR, BACKUP_DIR, SETTINGS_PATH, LOG_PATH,
    DEFAULT_PROJECT_ROOT, DEFAULT_PORT, DEFAULT_RETENTION_DAYS, DEFAULT_SAFE_MODE,
)
from services.project_service import discover_project_root
from services.audit_service import log_event
from services.repositories.quest_repository import quest_repo


def quest_graph_list():
    root = discover_project_root()
    regions_dir = os.path.join(root, "data", "configs", "regions")
    out = []
    if not os.path.isdir(regions_dir):
        return out
    for region in sorted(os.listdir(regions_dir)):
        qs_path = os.path.join(regions_dir, region, "quests.json")
        if not os.path.isfile(qs_path):
            continue
        data = load_json(qs_path, {"quests": []})
        for q in data.get("quests", []):
            if not isinstance(q, dict) or q.get("type") != "quest_graph":
                continue
            graph = q.get("quest_graph") or {}
            nodes = graph.get("nodes") or {}
            out.append({
                "region": region,
                "id": q.get("id", ""),
                "name": q.get("name", q.get("id", "")),
                "start_node": graph.get("start_node", ""),
                "node_count": len(nodes),
                "node_types": sorted({str(n.get("type", "?")) for n in nodes.values() if isinstance(n, dict)}),
                "endings": [e.get("id") for e in (graph.get("endings") or []) if isinstance(e, dict)],
                "nodes": nodes,
                "objectives": q.get("objectives", []),
            })
    return out


def quest_graph_get(qid):
    for q in quest_graph_list():
        if q.get("id") == qid:
            return q
    return None


def _find_graph_refs(start, nodes):
    """找出指向不存在节点的硬引用；存图前校验，防止写坏运行时图。"""
    refs = []
    for nid, n in nodes.items():
        if not isinstance(n, dict):
            continue
        for k in ("next", "on_win_next", "on_lose_next"):
            v = n.get(k)
            if isinstance(v, str) and v and v not in nodes:
                refs.append("%s.%s→%s" % (nid, k, v))
        opts = n.get("options")
        if isinstance(opts, list):
            for j, o in enumerate(opts):
                if isinstance(o, dict) and o.get("jump_id") and o["jump_id"] not in nodes:
                    refs.append("%s.options[%d].jump_id→%s" % (nid, j, o["jump_id"]))
    if start and start not in nodes:
        refs.append("start_node→%s" % start)
    return refs


def quest_graph_save(region, qid, graph):
    """T2 写回：把可视化编辑后的图存回 regions/<region>/quests.json 的对应 quest。
    先校验节点引用，save_json 自带备份；只有 type==quest_graph 且 id 匹配才写。"""
    root = discover_project_root()
    qs_path = os.path.join(root, "data", "configs", "regions", str(region), "quests.json")
    if not os.path.isfile(qs_path):
        return False, "找不到任务文件 regions/%s/quests.json" % region
    graph = graph or {}
    nodes = graph.get("nodes")
    if not isinstance(nodes, dict):
        return False, "quest_graph 缺 nodes（须为字典）"
    start = graph.get("start_node", "")
    bad = _find_graph_refs(start, nodes)
    if bad:
        return False, "存在指向不存在节点的引用，已拦截保存：%s" % "; ".join(sorted(set(bad))[:8])
    data = load_json(qs_path, {"quests": []})
    if not isinstance(data.get("quests"), list):
        return False, "quests.json 缺少 quests 数组"
    for q in data["quests"]:
        if isinstance(q, dict) and q.get("id") == qid and q.get("type") == "quest_graph":
            q["quest_graph"] = graph
            quest_repo.save_quests(region, data)
            log_event("quest_graph_save", qid, "区域 %s 保存任务流程图" % region)
            return True, "已保存任务图 %s（区域 %s）" % (qid, region)
    return False, "未找到 quest id=%s（type=quest_graph）" % qid
