cmake_minimum_required(VERSION 3.18.1)

project(openht_sbc C CXX)

# Generic portable build of BlueZ libsbc (no SIMD macros defined -> generic C
# primitives only; plenty fast for 32 kHz mono). The SIMD .c files are NOT
# compiled; their headers are include-guarded declarations only.
add_library(openht_sbc SHARED
        sbc/sbc.c
        sbc/sbc_primitives.c
        sbc_jni.cpp)

target_include_directories(openht_sbc PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/sbc)

# HAVE_CONFIG_H intentionally NOT defined -> <config.h> include is skipped.
target_compile_options(openht_sbc PRIVATE
        -O2
        -fvisibility=hidden
        -Wall
        -Wno-unused-function)

find_library(log-lib log)
target_link_libraries(openht_sbc ${log-lib})
