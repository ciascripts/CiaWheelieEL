@echo off
REM Starts WebDriverAgent on the iPad so Claude can control it.
REM Usage:  start-ipad.bat  [WebDriverAgent bundle ID]
REM Find the bundle ID with:  find-wda.bat
setlocal
set BUNDLE=%~1
if "%BUNDLE%"=="" set BUNDLE=com.facebook.WebDriverAgentRunner.xctrunner
echo Using WebDriverAgent bundle ID: %BUNDLE%
echo Keep the iPad unlocked and plugged in for this step.
echo.

start "1 iPad tunnel - keep open" cmd /k ios tunnel start --userspace
timeout /t 6 /nobreak >nul

echo Mounting the developer disk image...
ios image auto

start "2 WebDriverAgent - keep open" cmd /k ios runwda --bundleid=%BUNDLE% --testrunnerbundleid=%BUNDLE% --xctestconfig=WebDriverAgentRunner.xctest
timeout /t 12 /nobreak >nul

start "3 Port 8100 - keep open" cmd /k ios forward 8100 8100
timeout /t 3 /nobreak >nul

echo.
echo Check it: open http://127.0.0.1:8100/status in a browser.
echo You should see "ready" : true. Then open Claude Desktop.
start "" http://127.0.0.1:8100/status
pause
