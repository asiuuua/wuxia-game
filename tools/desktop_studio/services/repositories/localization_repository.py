# -*- coding: utf-8 -*-
"""LocalizationRepository —— 本地化域数据访问（strings.csv 文案表）。

承载原 localization_service 中与文件打交道的读写：
  - data/configs/localization/strings.csv（key,zh_CN,zh_TW,en）
写操作统一经 services.persistence（DataSink 六步收口），业务层不直接落盘。
"""

import csv
import os

from services import persistence
from services.project_service import discover_project_root


class LocalizationRepository:
    """本地化域数据访问对象（无状态；模块级单例 localization_repo）。"""

    def csv_path(self):
        return os.path.join(discover_project_root(), "data", "configs", "localization", "strings.csv")

    def load_csv(self):
        path = self.csv_path()
        if not os.path.isfile(path):
            return []
        with open(path, encoding="utf-8-sig", newline="") as f:
            return list(csv.reader(f))

    def save_csv(self, text, note="", encoding="utf-8"):
        persistence.save_text(self.csv_path(), text, note=note or "文案表", encoding=encoding)


localization_repo = LocalizationRepository()
