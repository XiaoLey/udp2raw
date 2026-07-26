#!/bin/bash
# 测试公共 harness:配置、安全清理、隧道辅助函数
# 各测试脚本 source 本文件,用 begin_phase/end_phase 包住测试段
#
# 安全清理原则(见 AGENTS.md「测试与环境安全」):
#   - 只杀本阶段记录的 PID,绝不用 pkill -f 按名字模式杀
#   - iptables 只删「相对阶段开始前快照」新增的规则和链,绝不碰测试前就存在的(生产)规则

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")

# 端口配置(故意用不常见端口,避开本机生产 udp2raw)
RAW_PORT=${U2R_TEST_RAW_PORT:-31855}
APP_PORT=${U2R_TEST_APP_PORT:-31966}
CLI_PORT=${U2R_TEST_CLI_PORT:-31967}
CLI2_PORT=${U2R_TEST_CLI2_PORT:-31968}
PASS=${U2R_TEST_PASS:-u2r-test-pass}

LOGS=${U2R_TEST_LOGS:-/tmp/u2r_test_logs}
mkdir -p "$LOGS"

# 被测二进制(可由 run_all.sh 或环境变量指定)
CUR_BIN=${CUR_BIN:-$REPO/udp2raw}
BASE_BIN=${BASE_BIN:-}
CUR_ASAN=${CUR_ASAN:-}
BASE_ASAN=${BASE_ASAN:-}

TEST_PIDS=()
IPT_SNAP=""
PHASE=""
PASS_CNT=0
FAIL_CNT=0

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

begin_phase() { # $1=阶段名
    PHASE=$1
    IPT_SNAP="$LOGS/ipt_$1.snap"
    sudo iptables-save 2>/dev/null | grep -v '^#' | grep -v '^\*' | grep -v '^COMMIT' | LC_ALL=C sort >"$IPT_SNAP"
    trap end_phase EXIT
}

end_phase() {
    trap - EXIT
    # 只杀本阶段记录的进程
    local pid
    for pid in "${TEST_PIDS[@]}"; do
        sudo kill -9 -- -"$pid" 2>/dev/null || sudo kill -9 "$pid" 2>/dev/null
        kill -9 -- -"$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
    done
    TEST_PIDS=()
    sleep 0.3
    # 只删相对快照新增的 iptables 规则与链
    if [ -n "$IPT_SNAP" ] && [ -f "$IPT_SNAP" ]; then
        local cur="$IPT_SNAP.after"
        sudo iptables-save 2>/dev/null | grep -v '^#' | grep -v '^\*' | grep -v '^COMMIT' | LC_ALL=C sort >"$cur"
        comm -13 "$IPT_SNAP" "$cur" | grep '^-A' | tac | while read -r r; do
            sudo iptables -w 5 $(echo "$r" | sed 's/^-A/-D/') 2>/dev/null
        done
        comm -13 <(grep '^:' "$IPT_SNAP" | sort) <(grep '^:' "$cur" | sort) |
            sed 's/^:\([^ ]*\).*/\1/' | while read -r ch; do
            [ -n "$ch" ] || continue
            sudo iptables -w 5 -F "$ch" 2>/dev/null
            sudo iptables -w 5 -X "$ch" 2>/dev/null
        done
    fi
}

alive() { sudo kill -0 "$1" 2>/dev/null || kill -0 "$1" 2>/dev/null; }

start_echo_app() {
    python3 "$HERE/py/echo_srv.py" "$APP_PORT" &
    TEST_PIDS+=($!)
    sleep 0.3
}

start_flood_app() {
    python3 "$HERE/py/flood_srv.py" "$APP_PORT" &
    TEST_PIDS+=($!)
    sleep 0.3
}

start_server() { # $1=bin $2=tag [$3..=额外参数]
    setsid sudo "$1" -s -l 0.0.0.0:$RAW_PORT -r 127.0.0.1:$APP_PORT -k "$PASS" -a "${@:3}" >"$LOGS/srv_$2.log" 2>&1 &
    TEST_PIDS+=($!)
    SRV_PID=$!
    sleep 0.6
}

start_client() { # $1=bin $2=tag [$3=本地端口 [$4..=额外参数]]
    local port=${3:-$CLI_PORT}
    setsid sudo "$1" -c -l 127.0.0.1:$port -r 127.0.0.1:$RAW_PORT -k "$PASS" -a "${@:4}" >"$LOGS/cli_$2.log" 2>&1 &
    TEST_PIDS+=($!)
    CLI_PID=$!
    sleep 1.8
}

echo_check() { python3 "$HERE/py/echo_cli.py" "${1:-$CLI_PORT}" "${2:-3}"; }

send_once() {
    python3 -c "import socket,sys
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
s.sendto(b'x'*100,('127.0.0.1',int(sys.argv[1])))" "$1"
}

need_base() {
    [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ] || { echo "SKIP: 需要基线二进制(BASE_BIN)"; exit 0; }
}
need_asan() {
    [ -n "$BASE_ASAN" ] && [ -n "$CUR_ASAN" ] || { echo "SKIP: 需要 ASan 二进制(BASE_ASAN/CUR_ASAN)"; exit 0; }
}

check() { # $1=描述 $2=yes|no
    if [ "$2" = yes ]; then
        PASS_CNT=$((PASS_CNT + 1))
        echo "  PASS  $1"
    else
        FAIL_CNT=$((FAIL_CNT + 1))
        echo "  FAIL  $1"
    fi
}

summary() {
    echo "[$PHASE] 小结: pass=$PASS_CNT fail=$FAIL_CNT"
    [ "$FAIL_CNT" -eq 0 ]
}
