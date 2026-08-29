#!/usr/bin/env bash
# gate_check.sh — 多窗口协作的代码门禁（ERROR 感知版，v2 修正）
# 修正点（2026-08-29）：
#   1. ROOT 归一化为 Windows 风格路径——Godot headless 在 Windows 上对 /d/xxx 的
#      POSIX 路径会“静默不运行场景”（零输出、零报错），旧版门禁因此误报绿。
#   2. gate[2] 改以框架打印的「✗」为真实失败判据；旧版 grep "失败 [1-9]" 会命中
#      负向用例的合法小计（如「失败 2」），造成误报。
#   3. run_all 只跑一次（tee 落盘后多次 grep），避免重复运行放大 user://saves 状态污染。
# 用法：bash tools/gate_check.sh [project_root]
# 退出码：0=全部通过；1=有门禁未过。
#
# 注意：Godot headless 输出接「文件重定向(> file)」或「命令替换 $(...)」会丢内容，
#       必须走管道(pipe)给 grep/cat/tee 等消费者。本脚本全程用管道 / tee。
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$HERE/.." && pwd)}"
# 归一化：Git Bash 的 POSIX 路径 /d/xxx → Windows D:\xxx（cygpath 不可用时保留原值）
if command -v cygpath >/dev/null 2>&1; then
  ROOT="$(cygpath -w "$ROOT" 2>/dev/null || echo "$ROOT")"
fi
GODOT="${GODOT:-$HOME/.workbuddy/binaries/godot/Godot_v4.7.2-stable_win64_console.exe}"
ALLOWLIST="$HERE/gate_allowlist.txt"
TMP="$HERE/_gate_tmp"
mkdir -p "$TMP" || { echo "无法创建临时目录 $TMP"; exit 1; }
if [ ! -x "$GODOT" ]; then
  echo "找不到 Godot: $GODOT"; exit 1
fi
fail=0

echo "=== [1/4] --quit 健康检查（零 SCRIPT/PARSE/COMPILE 错误）==="
if "$GODOT" --headless --path "$ROOT" --quit 2>&1 | grep -qE "SCRIPT ERROR|Parse Error|Compile Error|Could not parse"; then
  echo "  --quit 存在硬错误"; fail=1
else
  echo "  --quit 干净"
fi

echo "=== [2/4] run_all 单元套件（无 ✗ 真实失败 + 无非预期 ERROR）==="
# tee 落盘（tee 是管道消费者，不会丢输出）；再对落盘文件多次 grep
"$GODOT" --headless --path "$ROOT" "res://tests/unit/run_all.tscn" 2>&1 | tee "$TMP/run_all.txt" >/dev/null
if ! grep -q "发现 .* 个测试脚本" "$TMP/run_all.txt"; then
  echo "  run_all 未执行（Godot 静默未运行场景，检查 ROOT 路径格式）"; fail=1
elif grep -q "✗" "$TMP/run_all.txt"; then
  echo "  run_all 有用例失败（见上方 ✗ 行）"; fail=1
else
  echo "  run_all 全部套件通过（含预期负向用例）"
fi
# 非预期 ERROR: 行（从 ERROR 行里反选掉白名单）
grep -i "ERROR:" "$TMP/run_all.txt" | grep -vF -f "$ALLOWLIST" > "$TMP/bad_errors.txt"
if [ -s "$TMP/bad_errors.txt" ]; then
  echo "  非预期 ERROR（白名单未覆盖）:"
  sed 's/^/    /' "$TMP/bad_errors.txt"
  fail=1
else
  echo "  ERROR 行均已命中白名单（均为预期负向用例）"
fi

echo "=== [3/4] 背包冒烟测试（ALL_INV_OK）==="
if "$GODOT" --headless --path "$ROOT" "res://tests/ui/inventory_smoke.tscn" 2>&1 | grep -q "ALL_INV_OK"; then
  echo "  背包冒烟通过"
else
  echo "  背包冒烟失败（缺 ALL_INV_OK 或含 INV_FAIL）"; fail=1
fi

echo "=== [4/4] 进入游戏UI冒烟测试（ALL_M6_OK）==="
"$GODOT" --headless --path "$ROOT" "res://tests/ui/m6_ui_smoke.tscn" 2>&1 | tee "$TMP/m6.txt" >/dev/null
if grep -q "ALL_M6_OK" "$TMP/m6.txt" && ! grep -qE "SCRIPT ERROR|\[M6Test\].*(失败|加载失败|instantiate 失败)" "$TMP/m6.txt"; then
  echo "  进入游戏UI冒烟通过（HUD/GameMenu/BondRomance/AbilitiesScreen）"
else
  echo "  进入游戏UI冒烟失败（缺 ALL_M6_OK 或含运行期报错）"; fail=1
fi

rm -rf "$TMP" || true
if [ "$fail" -ne 0 ]; then
  echo "======== 门禁未通过 ❌ ========"
  exit 1
fi
echo "======== 全部门禁通过 ✅ ========"
exit 0
