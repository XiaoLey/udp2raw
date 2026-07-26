#!/bin/bash
# 命令行解析 ASan 对照矩阵:同一畸形输入,基线版应 ASan 报告/崩溃,当前版应干净处理
source "$(dirname "$0")/harness.sh"
need_asan
begin_phase args_asan

L150=$(printf 'a%.0s' {1..150})
L1500=$(printf 'a%.0s' {1..1500})
L998=$(printf 'a%.0s' {1..998})

# $1=bin $2=版本 $3=用例 $4=期望标记(grep -E 模式,空=期望无任何 AddressSanitizer)  $5..=参数
run_case() {
    local bin=$1 ver=$2 name=$3 expect=$4
    shift 4
    local out rc marker
    out=$(timeout 10 "$bin" "$@" 2>&1)
    rc=$?
    marker=$(echo "$out" | strip_ansi | grep -m1 -oE "AddressSanitizer: [a-zA-Z-]+|Segmentation fault|failed to parse|\[FATAL\]|root check failed" | head -1)
    local verdict=no
    if [ -n "$expect" ]; then
        echo "$out" | strip_ansi | grep -qE "$expect" && verdict=yes
    else
        echo "$out" | grep -q "AddressSanitizer" || verdict=yes
    fi
    check "$ver $name [rc=$rc $marker]" $verdict
}

for B in "$BASE_ASAN:基线" "$CUR_ASAN:当前"; do
    BIN=${B%%:*}
    VER=${B##*:}
    if [ "$VER" = "基线" ]; then
        # 基线版:每个用例都应触发 ASan/SEGV
        run_case "$BIN" "$VER" "-r 150字符主机名" "AddressSanitizer|Segmentation" -s -l 1.2.3.4:8855 -r "$L150:80"
        run_case "$BIN" "$VER" "-k 1500字符" "AddressSanitizer" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 -k "$L1500"
        run_case "$BIN" "$VER" "-k 998字符" "AddressSanitizer" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 -k "$L998"
        run_case "$BIN" "$VER" "--fifo 1500字符" "AddressSanitizer" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 --fifo "/tmp/$L1500"
        run_case "$BIN" "$VER" "--dev 150字符" "AddressSanitizer" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 --dev "$L150"
        run_case "$BIN" "$VER" "--lower-level 150字符" "AddressSanitizer" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 --lower-level "$L150#00:11:22:33:44:55"
        run_case "$BIN" "$VER" "--conf-file 缺参数" "AddressSanitizer|Segmentation" --conf-file
    else
        # 当前版:所有用例不得出现 ASan 报告
        run_case "$BIN" "$VER" "-r 150字符主机名" "" -s -l 1.2.3.4:8855 -r "$L150:80"
        run_case "$BIN" "$VER" "-k 1500字符" "" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 -k "$L1500"
        run_case "$BIN" "$VER" "-k 998字符" "" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 -k "$L998"
        run_case "$BIN" "$VER" "--fifo 1500字符" "" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 --fifo "/tmp/$L1500"
        run_case "$BIN" "$VER" "--dev 150字符" "" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 --dev "$L150"
        run_case "$BIN" "$VER" "--lower-level 150字符" "" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 --lower-level "$L150#00:11:22:33:44:55"
        run_case "$BIN" "$VER" "--conf-file 缺参数" "\[FATAL\]" --conf-file
        run_case "$BIN" "$VER" "--max-rst-allowed -1 可接受" "root check failed|raw" -s -l 1.2.3.4:8855 -r 1.2.3.4:8856 --max-rst-allowed -1
    fi
done
end_phase
summary
