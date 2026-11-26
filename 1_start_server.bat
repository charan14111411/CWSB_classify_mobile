@echo off
rem Starts the model server. Keep this window open while you use the app.
cd /d "%~dp0backend"
start "" http://localhost:8765
python app.py --lan
pause
