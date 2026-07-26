# tests —— 新旧对照验收测试套件

验证「修复/改动确实解决了问题」且「正常功能不受影响」的回归测试。方法论见 `.claude/skills/verify-fix`。

## 快速开始

```bash
# 完整对照测试(基线 = 修复前的提交):
tests/run_all.sh d40199b

# 只测当前版本自身功能(不需要基线):
tests/run_all.sh
```

前置条件：`sudo`（raw socket、iptables、valgrind 需要）、`python3`；`test_uninit.sh` 需要 `valgrind`（没装则跳过）。

## 安全设计（重要）

本机可能同时跑着生产 udp2raw + WireGuard，套件绝不碰它们：

- 清理只杀本套件记录的 PID，iptables 只删「阶段开始前快照」之后新增的规则/链（`harness.sh` 的 `begin_phase`/`end_phase`）——没有任何 `pkill -f`、没有按名字批量删链
- 测试端口默认 31855/31966/31967/31968（可用环境变量覆盖），避开生产端口
- `test_epoll_limit.sh` 临时调低 `fs.epoll.max_user_watches`，脚本内保存原值、结束必恢复
- `run_all.sh` 结尾打印 `wg show` 握手信息，确认生产隧道未受波及

## 各测试对应的验证手段

| 脚本 | 验证内容 | 手段 |
|---|---|---|
| `test_tunnel.sh` | 正常隧道双向数据流、跨版本互通、conf-file 加载 | E2E + 新旧/交叉组合 |
| `test_args_asan.sh` | 参数解析越界（-l/-r/-k/--fifo/--dev/--lower-level/--conf-file） | ASan（`make debug2`）同输入新旧对照 |
| `test_fifo.sh` | fifo 控制通道满读越界 | E2E 写超量数据，ASan 对照 |
| `test_stale_fd64.sh` | epoll 陈旧 fd64 事件竞态 | 故障注入：两份 scratch 构建注入同一前提，对照分支行为 |
| `test_epoll_limit.sh` | epoll_ctl 失败路径的 fd 映射清理 | sysctl 收紧 watch 上限使错误分支自然触发 |
| `test_uninit.sh` | 连接管理的未初始化内存读取 | valgrind memcheck 报告对照 |
| `test_uplink_timeout.sh` | 上行超时状态机分支 | iptables 单向断网 + 日志断言 |

单独运行某个：`BASE_BIN=<基线二进制> bash tests/test_xxx.sh`（ASan 类还需 `BASE_ASAN`/`CUR_ASAN`，`test_stale_fd64.sh` 需 `BASE_SRC` 指向基线源码目录）。`run_all.sh` 会自动构建并设置这些变量。

日志在 `/tmp/u2r_test_logs/`；基线构建的 worktree 在 `/tmp/u2r_base_<ref>/`（`build_base.sh` 重跑时自动重建）。
