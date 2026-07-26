#!/bin/bash
# fifo 控制通道 E2E:向 fifo 一次写入超过缓冲区的字节数
# 基线版客户端应崩溃(ASan 栈越界),当前版应存活并分段读完
source "$(dirname "$0")/harness.sh"

FIFO=/tmp/u2r_test_fifo

fifo_run() { # $1=client_bin $2=tag
    rm -f "$FIFO"
    mkfifo "$FIFO"
    start_echo_app
    start_server "$CUR_BIN" "fifo_$2"
    start_client "$1" "fifo_$2" "$CLI_PORT" --fifo "$FIFO"
    # 一次写入 2300 字节(缓冲区 2200);非阻塞打开,5 秒内打不开就放弃
    python3 -c "import os,sys,time
deadline=time.time()+5
while time.time()<deadline:
    try:
        fd=os.open(sys.argv[1],os.O_WRONLY|os.O_NONBLOCK);break
    except OSError:
        time.sleep(0.1)
else:
    sys.exit(0)
os.write(fd,b'x'*2300);os.close(fd)" "$FIFO" &
    TEST_PIDS+=($!)
    sleep 1.5
    local alive_now=$(alive $CLI_PID && echo yes || echo no)
    local asan=$(grep -c "AddressSanitizer" "$LOGS/cli_fifo_$2.log")
    local got=$(strip_ansi <"$LOGS/cli_fifo_$2.log" | grep -c "got data from fifo")
    echo "$alive_now $asan $got"
    end_phase
    rm -f "$FIFO"
}

if [ -n "$BASE_ASAN" ] && [ -x "$BASE_ASAN" ] && [ -n "$CUR_ASAN" ]; then
    begin_phase fifo_base
    read -r A S G <<<"$(fifo_run "$BASE_ASAN" 基线)"
    check "基线版写入2300字节后客户端死亡" $([ "$A" = no ] && [ "$S" -ge 1 ] && echo yes || echo no)

    begin_phase fifo_cur
    read -r A S G <<<"$(fifo_run "$CUR_ASAN" 当前)"
    check "当前版客户端存活" $A
    check "当前版无 ASan 报告" $([ "$S" -eq 0 ] && echo yes || echo no)
    check "当前版分段读完(>=2 次读取)" $([ "$G" -ge 2 ] && echo yes || echo no)
else
    begin_phase fifo_cur
    read -r A S G <<<"$(fifo_run "$CUR_BIN" 当前)"
    check "当前版客户端存活" $A
    check "当前版分段读完(>=2 次读取)" $([ "$G" -ge 2 ] && echo yes || echo no)
fi
summary
