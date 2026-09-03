REM =====================================================================
REM  内容工作室 启动器 —— 开发约束铁律（任何 AI 改本工具前必读）
REM  目标：保证用户双击本 bat 永远能开（窗口 + 浏览器），绝不"闪一下就退"。
REM  1. 零崩溃：根因是工作树被改成半成品/混合状态导致 import 失败。严禁留下
REM     这种状态；启动入口(studio_server.py __main__)已加 try/except 兜底打印错误。
REM  2. 改完必须释放：后台测功能起的 `python studio_server.py` 验证完立刻关掉，
REM     别留进程占 876x 端口。本 bat 已自愈合：双击先 PowerShell kill 任何残留
REM     再启动，用户永远不用手管端口。
REM  3. 不碰端口：端口自动顺延 8765→8785，禁止写死端口或改成需用户配置的常量。
REM  4. 收尾验证：改完跑 `python -u studio_server.py` 看"已启动"日志 + curl 端口
REM     HTTP 200 确认能开；纯验证性改动用 `git checkout HEAD -- tools/desktop_studio/` 还原。
REM  5. 源码模式即时生效：用户日常双击本 bat 读磁盘最新文件，无需重打包 exe。
REM  详规见 .workbuddy/memory/MEMORY.md「工作室工具 / 开发完必须释放」段。
REM =====================================================================
@echo off
chcp 65001 >nul
cd /d "%~dp0"
REM 用本机托管的 Python 启动「内容工作室」桌面版；若路径不存在则退回系统 python
set PY=C:\Users\Administrator\.workbuddy\binaries\python\versions\3.13.12\python.exe
if not exist "%PY%" set PY=python
REM 释放：关掉任何残留的 studio 服务进程，避免端口被占 / 旧实例挡路（8765 常被环境占用，服务端会自动顺延端口）
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='python.exe'\" | Where-Object { $_.CommandLine -like '*studio_server.py*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>&1
echo 正在启动内容工作室（浏览器会自动打开，端口被占会自动顺延）...
echo.
"%PY%" "%~dp0studio_server.py"
echo.
echo 内容工作室已关闭。直接关掉本窗口即可；如需重启请再次双击 studio_launcher.bat。
pause >nul
