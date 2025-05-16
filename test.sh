#!/bin/bash

# 函数：运行tcpping并提取延迟信息
run_tcpping() {
    local host=$1
    local count=$2
    sudo tcpping -x $count $host 443 | grep "tcp response from" | awk '{print $(NF-3), $(NF-1)}'
}

# 函数：测试单个域名
test_domain() {
    local domain=$1
    local test_count=$2
    echo "测试域名: $domain"
    echo "正在收集数据..."

    # 收集数据
    results=$(run_tcpping $domain $test_count)

    # 找出延迟最小的IP和计算统计信息
    best_ip=$(echo "$results" | sed 's/[()]//g' | sort -k2n | head -1)
    best_ip_addr=$(echo $best_ip | cut -d' ' -f1)

    # 第一阶段的统计信息
    first_min_latency=$(echo "$results" | awk '{print $NF}' | sort -n | head -1)
    first_avg_latency=$(echo "$results" | awk '{sum+=$NF} END {printf "%.3f", sum/NR}')
    first_count=$(echo "$results" | wc -l)
    
    
    echo -e "\n第一阶段结果:"
    echo "最佳IP: $best_ip_addr"
    echo "最小延迟: $first_min_latency ms"
    echo "平均延迟: $first_avg_latency ms"
    echo "测试次数: $first_count"
    

    # 第二阶段：测试最佳IP
    echo -e "\n第二阶段：测试最佳IP"
    echo "正在收集数据..."

    ip_results=$(run_tcpping $best_ip_addr $test_count)

    # 计算统计信息
    min_latency=$(echo "$ip_results" | awk '{print $NF}' | sort -n | head -1)
    avg_latency=$(echo "$ip_results" | awk '{sum+=$NF} END {printf "%.3f", sum/NR}')
    count=$(echo "$ip_results" | wc -l)


    # 获取元数据
    TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
    INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
    
    INSTANCE_TYPE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-type)
    
    EC2_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)
    REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
    IOT_PAYLOAD=$(echo -n "{\"instance_id\": \"$INSTANCE_ID\", \"instance_type\": \"$INSTANCE_TYPE\", \"ip\": \"$EC2_IP\", \"test_domain\": \"$domain\", \"avg_latency\": $avg_latency, \"min_latency\": $min_latency}" | base64)
    echo -e "\n第二阶段结果:"
    echo "IP: $best_ip_addr"
    echo "最小延迟: $min_latency ms"
    echo "平均延迟: $avg_latency ms"
    echo "测试次数: $count"
    echo "本机IP: $EC2_IP"
    echo "本机ID: $INSTANCE_ID"
    echo "本机类型: $INSTANCE_TYPE"
    echo -e "\n----------------------------------------\n"
    echo -n "{\"instance_id\": \"$INSTANCE_ID\", \"instance_type\": \"$INSTANCE_TYPE\", \"ip\": \"$EC2_IP\", \"test_domain\": \"$domain\", \"avg_latency\": $avg_latency, \"min_latency\": $min_latency}"
    
    # instance_id, ip, test_domain, instance_type, avg_latency, min_latency
    aws iot-data publish \
        --region $REGION \
        --topic "/test/cryptohft/$INSTANCE_ID" \
        --payload "$IOT_PAYLOAD"
    
}

# 主程序
echo "开始测试..."
echo -e "\n----------------------------------------\n"

# 测试第一个域名
# test_domain "fapi-mm.binance.com" 20

# 测试binance wss域名
test_domain "fstream-mm.binance.com" 100

echo "所有测试完成！"
