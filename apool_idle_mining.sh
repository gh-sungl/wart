#!/bin/bash

# 自定义部分 - 请根据需要修改这些参数
MINER_PATH="/hive/miners/bzminer/22.0.0/bzminer"  # 矿工路径
POOL_PARAMS="-p stratum+tcp://8.138.4.244:39998"  # 矿池参数
WALLET_PARAMS="-w 4086091606c9011325f0b8ecc3b4f61c6693ec981bbb32c2"  # 钱包参数
MINER_PARAMS="-a warthog"  # 其他矿工参数（算法、线程等）
MINER_SESSION="bz"  # 矿工的screen会话名称

# 检查矿工路径是否存在
if [ ! -f "$MINER_PATH" ]; then
    echo "错误: 矿工 $(basename "$MINER_PATH") 不存在于路径 $MINER_PATH"
    echo "请下载 $(basename "$MINER_PATH") 矿工"
    exit 1
fi

# 配置
URL="http://qubic1.hk.apool.io:8001/api/qubic/epoch_challenge"
CHECK_INTERVAL=15  # 检查间隔时间（秒）
WORKER_NAME=$(hostname)

# 自动获取矿工名称（路径的最后一个单词）
MINER_NAME=$(basename "$MINER_PATH")

# 完整的矿工命令
MINER_CMD="$MINER_PATH $MINER_PARAMS $POOL_PARAMS $WALLET_PARAMS.$WORKER_NAME"

# 日志文件路径
LOG_FILE="/var/log/miner/custom/custom_apool.log"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 日志轮转函数
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(du -m "$LOG_FILE" | cut -f1) -gt 10 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
        touch "$LOG_FILE"
        log "日志文件已轮转。"
    fi
}

# 获取挖矿状态
get_mining_status() {
    local res_url=$(curl -s -w "\nhttp_code:%{http_code}\n" "$URL" || echo "http_code:000")
    local res_code=$(echo "$res_url" | grep -o 'http_code:[0-9]*' | cut -d':' -f2)

    if [ "$res_code" = "000" ]; then
        log "网络请求失败,无法连接到服务器"
        return 1
    elif [ "$res_code" != "200" ]; then
        log "获取空闲状态失败。HTTP 代码: $res_code"
        return 1
    fi

    local json_data=$(echo "$res_url" | sed '$d')
    local mining_time=$(echo "$json_data" | grep -oP '"timestamp":\s*\K[0-9]+')
    local mining_seed=$(echo "$json_data" | grep -oP '"mining_seed":\s*"\K[^"]+')

    if [ -z "$mining_time" ] || [ -z "$mining_seed" ]; then
        log "提取挖矿数据失败。响应: $json_data"
        return 1
    fi

    if [ "$mining_seed" == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" ]; then
        echo "IDLE" "$mining_time"
    else
        echo "BUSY" "$mining_time"
    fi
}

# 启动矿工
start_miner() {
    if ! screen -list | grep -q "$MINER_SESSION"; then
        log "启动 $MINER_NAME..."
        screen -dmS $MINER_SESSION bash -c "$MINER_CMD"
        sleep 2
        if screen -list | grep -q "$MINER_SESSION"; then
            log "$MINER_NAME 在 screen 会话 '$MINER_SESSION' 中启动成功。"
        else
            log "$MINER_NAME 启动失败。"
        fi
    else
        log "$MINER_NAME 已在 screen 会话 '$MINER_SESSION' 中运行。"
    fi
}

# 停止矿工
stop_miner() {
    log "停止 $MINER_NAME..."
    if screen -list | grep -q "$MINER_SESSION"; then
        # 使用 screen 的 -X 选项发送 SIGTERM 信号到矿工进程
        screen -S $MINER_SESSION -X stuff $'\003'  # 发送 Ctrl+C
        sleep 2
        if ! screen -list | grep -q "$MINER_SESSION"; then
            log "$MINER_NAME 停止成功。"
        else
            log "$MINER_NAME 停止失败，尝试强制终止..."
            screen -S $MINER_SESSION -X quit
            sleep 2
            if ! screen -list | grep -q "$MINER_SESSION"; then
                log "$MINER_NAME 已被强制终止。"
            else
                log "警告: 无法完全停止 $MINER_NAME。"
                pkill -f "$(basename "$MINER_PATH")"
            fi
        fi
    else
        log "$MINER_NAME 未在运行。"
    fi
}

# 重启 apoolminer
restart_apoolminer() {
    log "在前台执行 miner restart..."
    miner restart
    log "miner restart 执行完成。"
}

# 健康检查函数
check_miner_health() {
    if ! screen -list | grep -q "$MINER_SESSION"; then
        log "警告: $MINER_NAME 不在运行状态,尝试重新启动..."
        start_miner
    fi
}

# 清理函数
cleanup() {
    log "接收到中断信号,正在清理..."
    stop_miner
    exit 0
}

# 设置信号处理
trap cleanup SIGINT SIGTERM

# 主函数
main() {
    log "开始挖矿监控脚本..."
    log "按 Ctrl+C 停止脚本"
    log "检查间隔: $CHECK_INTERVAL 秒"
    log "日志文件: $LOG_FILE"
    log "矿工路径: $MINER_PATH"
    log "矿工命令: $MINER_CMD"
    log "矿工 screen 会话: $MINER_SESSION"
    
    local previous_status=""
    
    while true; do
        # 日志轮转
        rotate_log
        
        if mining_info=$(get_mining_status); then
            read -r status timestamp <<< "$mining_info"
            log "工作节点名称: $WORKER_NAME"
            log "挖矿状态: $status (时间: $(date -d @"$timestamp" "+%Y-%m-%d %H:%M:%S"))"
            
            if [ "$status" == "IDLE" ] && [ "$previous_status" != "IDLE" ]; then
                start_miner
            elif [ "$status" == "BUSY" ] && [ "$previous_status" != "BUSY" ]; then
                stop_miner
                restart_apoolminer
            fi
            
            if [ "$status" == "IDLE" ]; then
                check_miner_health
            fi
            
            previous_status="$status"
        fi

        sleep $CHECK_INTERVAL
    done
}

# 运行主函数
main

# 功能特点：
#1. 自动化挖矿管理：根据服务器状态自动启动或停止矿工程序。
#2. 实时状态监控：定期检查服务器的挖矿状态（空闲或忙碌）。
#3. 智能进程控制：使用screen会话管理矿工进程，支持优雅启动和停止。
#4. 日志管理：
#   1. 详细记录所有操作和状态变化
#   2. 自动日志轮转，防止日志文件过大
#5. 错误处理和恢复：
#   1. 网络请求失败时的错误处理
#   2. 矿工进程意外退出时自动重启
#6. 健康检查：定期验证矿工进程是否正常运行，必要时重启。
#7. 优雅退出：通过信号处理，确保脚本被中断时能够清理资源并安全退出。
#8. 灵活配置：支持自定义矿工路径、矿池参数、钱包地址等。
#9. 兼容性：用于在HiveOS上运行。
#勾选矿机批量运行：wget http://ftp.***.cn/apool_idle_mining.sh && chmod +x apool_idle_mining.sh && screen -S apidle -dm bash -c "./apool_idle_mining.sh"
