#!/bin/bash
# 陈旧 fd64 事件(竞态)故障注入测试:
# 给当前版和基线版的 scratch 副本注入同一段代码——处理某事件前先关掉它对应的 fd64,
# 精确构造"fd 已关闭但事件还在队列里"的前提;被测分支原样不动,对照行为
source "$(dirname "$0")/harness.sh"

build_injected() { # $1=源码目录 $2=输出目录
    rm -rf "$2"
    mkdir -p "$2"
    (cd "$1" && tar cf - --exclude=.git --exclude=udp2raw --exclude=git_version.h .) | (cd "$2" && tar xf -)
    python3 - "$2/server.cpp" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "        for (idx = 0; idx < nfds; ++idx) {"
inject = anchor + """
            if (getenv("U2R_INJECT_STALE") != 0 && events[idx].data.u64 > u32_t(-1) && fd_manager.exist(events[idx].data.u64)) {
                // 测试注入:处理本事件前关掉它对应的fd64,制造陈旧事件
                mylog(log_warn, "INJECT: closing fd64 %llu right before its event is handled\\n", events[idx].data.u64);
                fd_manager.fd64_close(events[idx].data.u64);
            }"""
assert s.count(anchor) == 1, "注入锚点不唯一或不存在: " + p
open(p, "w").write(s.replace(anchor, inject))
EOF
    make -C "$2" >/dev/null 2>&1 || { echo "注入版构建失败: $2" >&2; return 1; }
}

injected_run() { # $1=bin $2=tag
    setsid sudo env U2R_INJECT_STALE=1 "$1" -s -l 0.0.0.0:$RAW_PORT -r 127.0.0.1:$APP_PORT -k "$PASS" -a >"$LOGS/srvi_$2.log" 2>&1 &
    TEST_PIDS+=($!)
    SRV_PID=$!
    sleep 0.6
    start_client "$CUR_BIN" "inji_$2"
    sleep 3
    local inj=$(grep -c INJECT "$LOGS/srvi_$2.log")
    local alive_now=$(alive $SRV_PID && echo yes || echo no)
    end_phase
    echo "$inj $alive_now"
}

build_injected "$REPO" /tmp/u2r_inj_cur || exit 1
BASE_SRC=${BASE_SRC:-}
if [ -n "$BASE_SRC" ] && [ -d "$BASE_SRC" ]; then
    build_injected "$BASE_SRC" /tmp/u2r_inj_base || exit 1
    begin_phase stale_base
    read -r I A <<<"$(injected_run /tmp/u2r_inj_base/udp2raw 基线)"
    check "基线版注入≥1次" $([ "$I" -ge 1 ] && echo yes || echo no)
    check "基线版首次注入即退出(复现)" $([ "$A" = no ] && echo yes || echo no)
fi

begin_phase stale_cur
read -r I A <<<"$(injected_run /tmp/u2r_inj_cur/udp2raw 当前)"
check "当前版注入≥1次" $([ "$I" -ge 1 ] && echo yes || echo no)
check "当前版注入后存活" $A
summary
