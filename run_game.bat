@echo off
setlocal

set "RUNTIME_PY=C:\Users\Daddy\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"

if exist "%RUNTIME_PY%" (
  "%RUNTIME_PY%" server.py
  goto :eof
)

python server.py
