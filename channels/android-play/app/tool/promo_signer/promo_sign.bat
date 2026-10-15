@echo off
setlocal
chcp 65001 >nul

set "APP_DIR=%~dp0..\.."
if not defined DART_EXE set "DART_EXE=dart"

pushd "%APP_DIR%" >nul
"%DART_EXE%" run tool\promo_signer\promo_signer.dart interactive %*
set "RESULT=%ERRORLEVEL%"
popd >nul

:finish
if not "%RESULT%"=="0" echo [失败] 未完成激活码签发，请检查上方提示。
if not "%PROMO_SIGNER_NO_PAUSE%"=="1" pause
exit /b %RESULT%
