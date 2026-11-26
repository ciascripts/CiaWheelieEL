@echo off
REM Lists the WebDriverAgent app on the iPad so you can copy its bundle ID.
ios apps --list | findstr /i "WebDriverAgent xctrunner"
echo.
echo Copy the ID that ends in .xctrunner (SideStore may have added letters to it),
echo then run:  start-ipad.bat ^<that ID^>
pause
