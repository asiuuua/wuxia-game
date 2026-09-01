@echo off
chcp 65001 >nul
REM ============================================================
REM  工作室工具 · 指定工程目录一键启动
REM  用法：双击本文件即可；或在同目录放一个 project_root.txt 写死工程路径。
REM  也可命令行带参：启动指定工程.bat "E:/我的游戏"
REM ============================================================
setlocal
cd /d "%~dp0"

REM 1) 命令行参数优先
set ROOT=%~1

REM 2) 否则读同目录的 project_root.txt（一行一个路径，取第一行非空）
if not defined ROOT (
  if exist "%~dp0project_root.txt" (
    for /f "usebackq delims=" %%L in ("%~dp0project_root.txt") do (
      if not defined ROOT set "ROOT=%%L"
    )
  )
)

REM 3) 都没有就提示手输
if not defined ROOT (
  set /p ROOT=请输入工程根目录（含 project.godot 的文件夹，例如 D:/武侠游戏）：
)

if not defined ROOT (
  echo 未提供工程目录，退出。
  pause
  exit /b 1
)

echo 目标工程：%ROOT%
echo 正在启动内容工作室（浏览器自动打开 http://127.0.0.1:8765/ ）...
start "" "工作室专业调教.exe" --root=%ROOT%
echo.
echo 关闭方法：直接关掉弹出的工具窗口，或在任务栏结束进程。
pause
endlocal
