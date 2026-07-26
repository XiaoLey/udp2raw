#!/bin/bash
# 上行超时状态机测试:用 iptables 单向切断 client->server(server->client 心跳仍可达),
# 模拟非对称链路中断。12 秒上行超时触发后:
# 基线版缺 return 0,会紧跟发出一个畸形心跳;当前版直接返回,不发
source "$(dirname "$0")/harness.sh"

up_run() { # $1=bin $2=tag
    start_server "$1" "up_$2"
    start_client "$1" "up_$2" "$CLI_PORT" --log-level 5
    # 等心跳周期建立(出现首次 heartbeat sent,记为 t0),再等 1.8s 后断网:
    # 上行超时阈值 12s 恰为心跳周期 2s 的整数倍,断网落在 t0+1.8s 时,
    # 超时 tick 会精确落在那个"本来该发心跳"的 tick 上,旧版必发畸形心跳(相位确定,不靠运气)
    local i
    for i in $(seq 1 40); do
        grep -q "heartbeat sent" "$LOGS/cli_up_$2.log" && break
        sleep 0.25
    done
    sleep 1.8
    sudo iptables -I OUTPUT -p tcp --dport "$RAW_PORT" -j DROP # 新增规则,阶段结束按快照差异清理
    sleep 14
    local n=$(grep -c "client-->server direction timeout" "$LOGS/cli_up_$2.log")
    local hb=$(awk '/client-->server direction timeout/{t=NR} t && NR>t && NR<=t+3 && /heartbeat sent/{c++} END{print c+0}' "$LOGS/cli_up_$2.log")
    end_phase
    echo "$n $hb"
}

if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    begin_phase uplink_base
    read -r N HB <<<"$(up_run "$BASE_BIN" 基线)"
    check "基线版上行超时触发" $([ "$N" -ge 1 ] && echo yes || echo no)
    check "基线版超时后紧跟畸形心跳(复现)" $([ "$HB" -ge 1 ] && echo yes || echo no)
fi

begin_phase uplink_cur
read -r N HB <<<"$(up_run "$CUR_BIN" 当前)"
check "当前版上行超时触发" $([ "$N" -ge 1 ] && echo yes || echo no)
check "当前版超时后无畸形心跳" $([ "$HB" -eq 0 ] && echo yes || echo no)
summary
