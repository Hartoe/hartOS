@echo off

set ASM=nasm
set SRC_DIR=src
set BUILD_DIR=build

%ASM% %SRC_DIR%\main.asm -f bin -o %BUILD_DIR%\main.bin
copy %BUILD_DIR%\main.bin %BUILD_DIR%\main_floppy.img /b
trunc %BUILD_DIR%\main_floppy.img 1440000