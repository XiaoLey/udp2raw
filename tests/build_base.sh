#!/bin/bash
# 从指定 git ref 构建基线版本二进制(常规版 + ASan 版),输出到 /tmp
# 用法: tests/build_base.sh <git_ref>
# 成功后向 stdout 打印两行 BASE_BIN=/BASE_ASAN= 供 eval 使用
set -e
REF=${1:?用法: build_base.sh <git_ref>}
REPO=$(cd "$(dirname "$0")/.." && pwd)
NAME=$(echo "$REF" | tr '/:' '__')
WT=/tmp/u2r_base_$NAME

git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true
git -C "$REPO" worktree add "$WT" "$REF" >/dev/null

cd "$WT"
make >/dev/null 2>&1
cp udp2raw /tmp/u2r_base_${NAME}_normal
make debug2 >/dev/null 2>&1
cp udp2raw /tmp/u2r_base_${NAME}_asan
make >/dev/null 2>&1

echo "BASE_BIN=/tmp/u2r_base_${NAME}_normal"
echo "BASE_ASAN=/tmp/u2r_base_${NAME}_asan"
