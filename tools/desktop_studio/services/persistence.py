# -*- coding: utf-8 -*-
"""持久化适配层（Persistence Adapter）：业务层唯一 JSON/文本落盘收口。

承接原 _common.save_json / save_text 职责（15 图 ST-2 DataSink 六步收口）：
  ① ID 校验  ② Schema 校验  ③ _backup  ④ tmp+os.replace 原子写
  ⑤ ref_index 增量反查（悬空即回滚）  ⑥ change_log 留痕；
frozen 旧包缺 data_sink 时降级直写并记日志（③备份走 _common._backup）。

分层（§28 Repository Boundary）：
  业务域 service → 域 Repository（services/repositories/）→ 本层 → data_sink
本层与 repositories/ 是仅有的两处落盘入口；业务层禁止直调本层之外的写口。
"""

import json
import os
import sys

from services._common import _backup, _log_event

MODULE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS_DIR = os.path.dirname(MODULE_DIR)          # tools/（data_sink 所在层）
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

try:
    import data_sink as _sink
    from data_sink import SinkRejected  # noqa: F401  （studio_server 可经此捕获提示用户）
    _SINK_OK = True
except Exception:  # pragma: no cover
    _SINK_OK = False


def _project_root():
    # 延迟 import：project_service 顶层依赖 _common，本层被各域 service 间接引用，
    # 运行时才取工程根（与 settings 互调场景解耦，避免顶层成环）。
    from services.project_service import discover_project_root
    return discover_project_root()


def save_text(path, text, note="", encoding="utf-8"):
    """ST-2 唯一写口（文本/CSV 版）：降级策略同 save_json。"""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if _SINK_OK:
        try:
            _sink.write_text(_project_root(), path, text,
                             note=note or "Studio save_text", encoding=encoding)
            return
        except _sink.SinkRejected as e:
            _log_event("sink_rejected", path, "%s | %s" % (e.step, "；".join(e.problems[:5])))
            raise
        except Exception as e:
            _log_event("sink_error", path, str(e))
    _backup(path)
    with open(path, "w", encoding=encoding, newline="") as f:
        f.write(text)
    if not _SINK_OK:
        _log_event("sink_degraded", path, "data_sink 不可用，直写降级（请重打包或用源码模式）")


def save_json(path, data, note=""):
    """ST-2 唯一写口：Studio 生产 JSON 写统一经 DataSink 六步收口（15图批2）。

    降级路径：frozen 旧包缺 data_sink 时按旧逻辑直写（③备份+④落盘仍在），
    并写 studio 日志提示重打包。"""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if _SINK_OK:
        try:
            _sink.write_json(_project_root(), path, data, note=note or "Studio save_json")
            return
        except _sink.SinkRejected as e:
            _log_event("sink_rejected", path, "%s | %s" % (e.step, "；".join(e.problems[:5])))
            raise
        except Exception as e:
            _log_event("sink_error", path, str(e))
            # 六步设施异常不阻断编辑器主流程：退回直写并留痕
    _backup(path)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    if not _SINK_OK:
        _log_event("sink_degraded", path, "data_sink 不可用，直写降级（请重打包或用源码模式）")
