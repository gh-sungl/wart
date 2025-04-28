#!/bin/bash

url="http://qubic1.hk.apool.io:8001/api/qubic/epoch_challenge"
CHECK_INTERVAL=5  # 检查间隔时间（秒）
WORKER_NAME=$(hostname)
MINER_CMD="/hive/miners/apoolxmr/apoolminer_hiveos/apoolminer ./xmrminer -A xmr --account CP_ejrl8u0va4 --worker my_worker --pool xmr.apool.top:3334"
LOG_PATH="/var/log/miner/custom/custom_cpu.log"

# 创建日志文件的父目录（如果不存在）
mkdir -p "$(dirname "$LOG_PATH")"

# 定义退出时清理的函数
cleanup() {
    echo "Stopping apoolminer and cleaning up..."
    pkill -f apoolminer  # 结束矿工进程
    exit 0
}

# 捕获退出信号 (SIGINT 和 SIGTERM)
trap cleanup SIGINT SIGTERM

# 主循环
while true; do
    res_url=$(curl -s -w "\nhttp_code:%{http_code}\n" "$url")
    res_code=$(echo "$res_url" | grep -o 'http_code:[0-9]*' | sed 's/http_code://')
    [ "$res_code" != "200" ] && echo "Failed to get idle status" && sleep $CHECK_INTERVAL && continue

    mining_time=$(echo "$res_url" | grep -o '"timestamp":[0-9]*' | sed 's/"timestamp"://')
    mining_seed=$(echo "$res_url" | grep -o '"mining_seed":"[^"]*"' | sed 's/"mining_seed":"\([^"]*\)"/\1/')
    mining_status=$([ "$mining_seed" == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" ] && echo "IDLE" || echo "BUSY")
    echo "$mining_status now, from $(date -d @$mining_time "+%Y-%m-%d %H:%M:%S")"

    if [ "$mining_status" == "IDLE" ]; then
        if ! pgrep -f apoolminer > /dev/null; then
            echo "Starting apoolminer..."
            nohup $MINER_CMD >> "$LOG_PATH" 2>&1 &
        else
            echo "apoolminer is already running."
        fi
    elif [ "$mining_status" == "BUSY" ]; then
        echo "Stopping apoolminer..."
        pkill -f apoolminer
    fi

    sleep $CHECK_INTERVAL
done
