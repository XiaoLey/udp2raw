#!/bin/bash
# 验收测试总入口
# 用法: tests/run_all.sh [基线_git_ref]
#   给基线 ref(如修复前的提交)时构建基线二进制,运行全部「基线 vs 当前」对照测试
#   不给时只跑当前版本自身的功能测试
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
REF=${1:-}

echo "== 构建当前版本(常规 + ASan) =="
make -C "$REPO" >/dev/null 2>&1 || { echo "当前版本构建失败"; exit 1; }
export CUR_BIN=$REPO/udp2raw
make -C "$REPO" debug2 >/dev/null 2>&1
cp "$REPO/udp2raw" /tmp/u2r_cur_asan
export CUR_ASAN=/tmp/u2r_cur_asan
make -C "$REPO" >/dev/null 2>&1 # 恢复常规构建产物

if [ -n "$REF" ]; then
    echo "== 构建基线版本: $REF =="
    OUT=$(bash "$HERE/build_base.sh" "$REF") || { echo "基线构建失败"; exit 1; }
    eval "$OUT"
    export BASE_BIN BASE_ASAN
    export BASE_SRC=/tmp/u2r_base_$(echo "$REF" | tr '/:' '__')
    echo "BASE_BIN=$BASE_BIN"
fi

FAILED=0
for t in test_tunnel test_args_asan test_fifo test_stale_fd64 test_epoll_limit test_uninit test_uplink_timeout; do
    echo ""
    echo "########## $t ##########"
    bash "$HERE/$t.sh" || FAILED=1
done

echo ""
echo "########## 生产环境健康状况确认 ##########"
sudo wg show 2>/dev/null | grep -A2 transfer || echo "(本机无 WireGuard 接口)"

echo ""
if [ $FAILED -eq 0 ]; then
    echo "全部测试通过"
else
    echo "存在失败项(见上方 FAIL 行)"
    exit 1
fi
