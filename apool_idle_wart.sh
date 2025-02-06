#!/bin/bash

url="http://qubic1.hk.apool.io:8001/api/qubic/epoch_challenge"
CHECK_INTERVAL=5  # 检查间隔时间（秒）
WORKER_NAME=$(hostname)
MINER_CMD="/hive/miners/bzminer/22.0.0/bzminer -a warthog -r test -w 4086091606c9011325f0b8ecc3b4f61c6693ec981bbb32c2.$WORKER_NAME -p stratum+tcp://8.138.4.244:39998 --nc 0 --nvidia 1 --amd 0 --cpu_threads 0 --cpu_threads_start_offset 0"

# 确保日志目录存在
mkdir -p /var/log/miner/custom

while true; do
    res_url=$(curl -s -w "\nhttp_code:%{http_code}\n" "$url")
    res_code=$(echo "$res_url" | grep -o 'http_code:[0-9]*' | cut -d ':' -f 2)
    [ "$res_code" != "200" ] && echo "$(date): failed to get idle status (HTTP $res_code)" && sleep $CHECK_INTERVAL && continue

    mining_time=$(echo "$res_url" | grep -oP '"timestamp":\K[0-9]+')
    mining_seed=$(echo "$res_url" | grep -oP '"mining_seed":"\K[^"]+')
    mining_status=$([ "$mining_seed" == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" ] && echo "IDLE" || echo "BUSY")
    
    echo "$(date): Mining status is $mining_status, last updated at $(date -d @$mining_time "+%Y-%m-%d %H:%M:%S")"

    if [ "$mining_status" == "IDLE" ]; then
        if ! pgrep -f bzminer > /dev/null; then
            echo "$(date): Starting bzminer..."
            nohup $MINER_CMD >> /var/log/miner/custom/custom_cpu.log 2>&1 &
        else
            echo "$(date): bzminer is already running."
        fi
    elif [ "$mining_status" == "BUSY" ]; then
        echo "$(date): Stopping bzminer..."
        pkill -f bzminer
    fi

    sleep $CHECK_INTERVAL
done
