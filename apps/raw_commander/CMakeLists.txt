project(CFS_RAW_COMMANDER C)

add_cfe_app(raw_commander fsw/src/raw_commander_app.c)
target_include_directories(raw_commander PUBLIC fsw/inc)
