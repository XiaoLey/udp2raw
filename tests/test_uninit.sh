#!/bin/bash
# valgrind 未初始化内存读取对照:
# 基线版在 clear_inactive(connection.h) 有对未初始化 last_clear_time 的读取报告,当前版应消失
# (其余报告为 AES/glibc 既有背景噪音,两版一致,不作断言)
source "$(dirname "$0")/harness.sh"
command -v valgrind >/dev/null || { echo "SKIP: 未安装 valgrind"; exit 0; }

vg_run() { # $1=bin $2=tag
    setsid sudo valgrind --tool=memcheck --track-origins=yes "$1" -s -l 0.0.0.0:$RAW_PORT -r 127.0.0.1:$APP_PORT -k "$PASS" -a >"$LOGS/vg_$2.log" 2>&1 &
    TEST_PIDS+=($!)
    sleep 4
    start_client "$CUR_BIN" "vg_$2"
    sleep 3
    echo_check >/dev/null 2>&1
    sleep 1.5
    end_phase
    # 报告位置(at 行)落在 clear_inactive 的数量
    local ci=$(grep -A2 -i "uninitialised" "$LOGS/vg_$2.log" | grep -c "clear_inactive")
    echo "$ci"
}

if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    begin_phase uninit_base
    CI=$(vg_run "$BASE_BIN" 基线)
    check "基线版存在 clear_inactive 未初始化读报告" $([ "$CI" -ge 1 ] && echo yes || echo no)
fi

begin_phase uninit_cur
CI=$(vg_run "$CUR_BIN" 当前)
check "当前版 clear_inactive 未初始化读报告为 0" $([ "$CI" -eq 0 ] && echo yes || echo no)
summary
