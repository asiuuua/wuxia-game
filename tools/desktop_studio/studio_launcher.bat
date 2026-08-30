@echo off
chcp 65001 >nul
cd /d "%~dp0"
REM 用本机托管的 Python 启动「内容工作室」桌面版；若路径不存在则退回系统 python
set PY=C:\Users\Administrator\.workbuddy\binaries\python\versions\3.13.12\python.exe
if not exist "%PY%" set PY=python
echo 正在启动内容工作室（浏览器会自动打开 http://127.0.0.1:8765/ ）...
start "" "%PY%" "%~dp0studio_server.py"
echo.
echo 关闭方法：直接关掉弹出的 Python 黑窗口，或在任务栏结束 python 进程。
pause
