#!/bin/bash
# 正常功能回归:当前版本自身隧道 + (有基线时)基线自身隧道 + 跨版本互通 + CLI 等价
source "$(dirname "$0")/harness.sh"

tunnel_pair() { # $1=server_bin $2=client_bin $3=tag
    start_echo_app
    start_server "$1" "$3"
    start_client "$2" "$3"
    local hs=$(grep -qi ready "$LOGS/cli_$3.log" && echo yes || echo no)
    check "$3 握手 ready" $hs
    local r=$(echo_check)
    check "$3 双向数据流 ECHO 3/3" $([ "$r" = "ECHO 3/3" ] && echo yes || echo no)
    check "$3 server 存活" $(alive $SRV_PID && echo yes || echo no)
    check "$3 client 存活" $(alive $CLI_PID && echo yes || echo no)
    end_phase
}

begin_phase tunnel_cur
tunnel_pair "$CUR_BIN" "$CUR_BIN" "新+新"

if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    begin_phase tunnel_base
    tunnel_pair "$BASE_BIN" "$BASE_BIN" "旧+旧"

    begin_phase tunnel_cross1
    tunnel_pair "$CUR_BIN" "$BASE_BIN" "新server+旧client"

    begin_phase tunnel_cross2
    tunnel_pair "$BASE_BIN" "$CUR_BIN" "旧server+新client"
fi

# CLI 等价:conf-file 正常加载(不借助 -a,不碰 iptables)
begin_phase cli_conf
printf -- "-s\n-l 0.0.0.0:%s\n-r 127.0.0.1:%s\n-k %s\n" "$RAW_PORT" "$APP_PORT" "$PASS" >"$LOGS/test.conf"
for B in "$CUR_BIN:新" ${BASE_BIN:+$BASE_BIN:旧}; do
    BIN=${B%%:*}
    TAG=${B##*:}
    sudo timeout 2 "$BIN" --conf-file "$LOGS/test.conf" >"$LOGS/conf_$TAG.log" 2>&1
    rc=$?
    f=$(grep -c FATAL "$LOGS/conf_$TAG.log")
    check "$TAG版 conf-file 正常加载" $([ $rc -eq 124 ] && [ "$f" -eq 0 ] && echo yes || echo no)
done
end_phase

summary
