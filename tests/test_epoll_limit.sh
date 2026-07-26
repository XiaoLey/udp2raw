#!/bin/bash
# epoll_ctl 失败路径测试:把 fs.epoll.max_user_watches 动态收紧到当前值,
# 让 conv 的 epoll 注册恰好失败;发包重试建 conv 时触发 fd 号复用
# 基线版:陈旧映射 + fd 复用 -> fd_manager.create 断言崩溃,且 abort 跳过 iptables 清理
# 当前版:无陈旧映射,连续失败也不崩
source "$(dirname "$0")/harness.sh"

count_watches() {
    sudo python3 -c "
import glob
t = 0
for fi in glob.glob('/proc/[0-9]*/fdinfo/*'):
    try:
        pid = fi.split('/')[2]
        if 'Uid:\t0' not in open('/proc/%s/status' % pid).read():
            continue
        c = open(fi, errors='ignore').read()
        if 'tfd:' in c:
            t += c.count('\ntfd:') + (1 if c.startswith('tfd:') else 0)
    except Exception:
        pass
print(t)"
}

ORIG=$(cat /proc/sys/fs/epoll/max_user_watches)

a6_run() { # $1=bin $2=tag
    sudo sysctl -w fs.epoll.max_user_watches="$ORIG" >/dev/null # 恢复上限,保证 server 正常启动
    start_server "$1" "a6_$2"
    start_client "$CUR_BIN" "a6_$2"
    local dead=no
    for round in 1 2 3; do
        sleep 1.3 # 让上一轮可能建成的 conv 过期
        sudo sysctl -w fs.epoll.max_user_watches="$(count_watches)" >/dev/null # 收紧到当前值:下次 epoll_ctl ADD 必失败
        for i in 1 2 3 4 5; do
            send_once "$CLI_PORT"
            sleep 0.3
        done
        if ! alive $SRV_PID; then dead=yes; break; fi
    done
    local ab=$(grep -c "Assertion" "$LOGS/srv_a6_$2.log")
    local warn=$(grep -c "add udp_fd error" "$LOGS/srv_a6_$2.log")
    end_phase
    echo "$dead $ab $warn"
}

if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    begin_phase epoll_base
    read -r D AB W <<<"$(a6_run "$BASE_BIN" 基线)"
    check "基线版 server 崩溃" $([ "$D" = yes ] && echo yes || echo no)
    check "基线版断言失败≥1" $([ "$AB" -ge 1 ] && echo yes || echo no)
fi

begin_phase epoll_cur
read -r D AB W <<<"$(a6_run "$CUR_BIN" 当前)"
check "当前版 server 存活" $([ "$D" = no ] && echo yes || echo no)
check "当前版无断言失败" $([ "$AB" -eq 0 ] && echo yes || echo no)
check "当前版确实触发过失败路径" $([ "$W" -ge 1 ] && echo yes || echo no)

sudo sysctl -w fs.epoll.max_user_watches="$ORIG" >/dev/null
summary
