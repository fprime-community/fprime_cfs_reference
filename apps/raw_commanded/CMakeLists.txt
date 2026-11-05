project(CFS_RAW_COMMANDED C)

add_cfe_app(raw_commanded fsw/src/raw_commanded_app.c)
target_include_directories(raw_commanded PUBLIC fsw/inc)
