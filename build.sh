#!/usr/bin/env bash
set -e
python3 -m pip install --upgrade pip
python3 -m pip install pyinstaller pyqt6 pyqtgraph pyserial
rm -rf build dist
python3 -m PyInstaller build.spec --noconfirm
echo "Готово: dist/SolenoidTester"