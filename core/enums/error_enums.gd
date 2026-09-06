# core/enums/error_enums.gd
# 错误级别（18 图 RH 域错误分级；旧「规范 §4.2.1」编号已废）。匿名枚举常量直接挂在类名上，
# 外部用 GameErrorLevel.FATAL 这类形式引用，无需再写 .Level。

class_name GameErrorLevel
extends RefCounted

enum { INFO, WARN, ERROR, FATAL }
