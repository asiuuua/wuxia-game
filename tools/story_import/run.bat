@echo off
chcp 65001 >nul
setlocal
set PY=
where python >nul 2>nul && set PY=python
if "%PY%"=="" set PY="C:\Users\Administrator\.workbuddy\binaries\python\versions\3.13.12\python.exe"
if not exist %PY% (
  echo 找不到 Python！请安装 Python 3，或确认 managed 路径。
  pause
  exit /b 1
)
%PY% "%~dp0convert.py"
pause
