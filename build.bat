@echo off
IF NOT EXIST build mkdir build

odin build src -out:build/dynamicTerrain.exe -show-timings -warnings-as-errors -o:speed

::-debug
::-o:speed