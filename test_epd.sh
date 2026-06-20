#!/usr/bin/env bash
#===============================================================================
# EPD Display - 上位机测试脚本
# 用法: ./test_epd.sh <ESP8266_IP> [命令...]
#   - 不带命令: 运行全套测试
#   - 带命令:   只运行指定命令
#
# 示例:
#   ./test_epd.sh 192.168.1.100          # 全套测试
#   ./test_epd.sh 192.168.1.100 status   # 只看状态
#   ./test_epd.sh 192.168.1.100 text     # 只测试文字
#   ./test_epd.sh 192.168.1.100 clear    # 只清屏
#===============================================================================
set -euo pipefail

# ---- 配置 ----
IP="${1:-}"
CMD="${2:-all}"
HALF_SIZE=7500          # 半屏字节数: 50 bytes/行 × 150 行

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR ]${NC} $*"; }

# ---- 参数检查 ----
if [[ -z "$IP" ]]; then
    echo -e "${RED}用法: $0 <ESP8266_IP> [命令]${NC}"
    echo ""
    echo "命令 (可选):"
    echo "  all     运行全套测试 (默认)"
    echo "  status  查看设备状态"
    echo "  text    测试文字显示"
    echo "  pattern 测试棋盘格图案"
    echo "  clear   清屏"
    echo "  refresh 仅刷新"
    echo "  sleep   进入睡眠"
    echo ""
    exit 1
fi

BASE="http://${IP}"

# ---- 工具函数 ----

# 生成一个"棋盘格"半屏图案 (7500 bytes)
# 每行 50 bytes = 400 像素
# 奇数列 = 0xFF (白色), 偶数列 = 0x00 (黑色)
# 生成黑白交替的竖条纹
gen_checkerboard_half() {
    local invert="${1:-0}"  # 0=正常, 1=反色
    local byte
    for ((row = 0; row < 150; row++)); do
        for ((col = 0; col < 50; col++)); do
            if (( (row / 8 + col) % 2 == 0 )); then
                byte=$(( invert ? 0x00 : 0xFF ))
            else
                byte=$(( invert ? 0xFF : 0x00 ))
            fi
            printf "\\x$(printf '%02x' "$byte")"
        done
    done
}

# 生成水平渐变的半屏图案
gen_gradient_half() {
    local invert="${1:-0}"
    for ((row = 0; row < 150; row++)); do
        for ((col = 0; col < 50; col++)); do
            # 每一行从左到右渐变: 0xFF -> 0x00
            local val=$(( 0xFF - (col * 0xFF / 49) ))
            printf "\\x$(printf '%02x' "$val")"
        done
    done
}

# 生成全白的半屏数据
gen_white_half() {
    dd if=/dev/zero bs="$HALF_SIZE" count=1 2>/dev/null | tr '\0' '\xFF'
}

# 生成全黑的半屏数据
gen_black_half() {
    dd if=/dev/zero bs="$HALF_SIZE" count=1 2>/dev/null
}

# HTTP POST helper
post_bin() {
    local url="$1"
    local file="$2"
    local desc="$3"
    info "POST $url ($desc)"
    if curl -s -X POST --data-binary "@$file" "$url" 2>&1; then
        echo ""
        ok "  ✓ $desc"
    else
        echo ""
        err "  ✗ $desc"
        return 1
    fi
}

post_json() {
    local url="$1"
    local json="$2"
    local desc="$3"
    info "POST $url ($desc)"
    if curl -s -X POST -H "Content-Type: application/json" -d "$json" "$url" 2>&1; then
        echo ""
        ok "  ✓ $desc"
    else
        echo ""
        err "  ✗ $desc"
        return 1
    fi
}

get_url() {
    local url="$1"
    local desc="$2"
    info "GET $url ($desc)"
    curl -s "$url" | head -20
    echo ""
    ok "  ✓ $desc"
}

# ---- 测试用例 ----

test_status() {
    echo ""
    echo "============================================"
    echo "  1/5 📡 设备状态"
    echo "============================================"
    get_url "$BASE/" "获取状态页面"
    echo ""
    get_url "$BASE/api/wifi" "获取 WiFi 信息"
}

test_text() {
    echo ""
    echo "============================================"
    echo "  2/5 🔤 文字显示测试"
    echo "============================================"
    # 先清空黑色层
    gen_white_half > /tmp/epd_black0.bin
    gen_white_half > /tmp/epd_black1.bin
    gen_white_half > /tmp/epd_red0.bin
    gen_white_half > /tmp/epd_red1.bin
    post_bin "$BASE/display/black/0" /tmp/epd_black0.bin "清空黑色层上半"
    post_bin "$BASE/display/black/1" /tmp/epd_black1.bin "清空黑色层下半"
    post_bin "$BASE/display/red/0"   /tmp/epd_red0.bin   "清空红色层上半"
    post_bin "$BASE/display/red/1"   /tmp/epd_red1.bin   "清空红色层下半"

    # 显示英文
    post_json "$BASE/display/text" \
        '{"layer":"black","half":0,"text":"Hello EPD!","x":10,"y":10,"font":"Font24","fg":"black","bg":"white"}' \
        "绘制英文 (黑色层上半, Font24)"

    # 显示中文
    post_json "$BASE/display/text" \
        '{"layer":"black","half":0,"text":"墨水屏测试","x":10,"y":50,"font":"Font24CN","fg":"black","bg":"white"}' \
        "绘制中文 (黑色层上半, Font24CN)"

    # 在红色层显示
    post_json "$BASE/display/text" \
        '{"layer":"red","half":0,"text":"RED LAYER","x":10,"y":10,"font":"Font16","fg":"black","bg":"white"}' \
        "绘制红色层文字 (红色层上半, Font16)"

    post_json "$BASE/display/refresh" '{}' "刷新显示"
}

test_pattern() {
    echo ""
    echo "============================================"
    echo "  3/5 🎨 棋盘格图案测试"
    echo "============================================"
    info "生成测试图案..."
    gen_checkerboard_half 0 > /tmp/epd_pattern_black0.bin
    gen_checkerboard_half 1 > /tmp/epd_pattern_black1.bin
    gen_white_half         > /tmp/epd_pattern_red0.bin
    gen_white_half         > /tmp/epd_pattern_red1.bin

    post_bin "$BASE/display/black/0" /tmp/epd_pattern_black0.bin "黑色层上半 (棋盘格)"
    post_bin "$BASE/display/black/1" /tmp/epd_pattern_black1.bin "黑色层下半 (反色棋盘格)"
    post_bin "$BASE/display/red/0"   /tmp/epd_pattern_red0.bin   "红色层上半 (全白)"
    post_bin "$BASE/display/red/1"   /tmp/epd_pattern_red1.bin   "红色层下半 (全白)"

    post_json "$BASE/display/refresh" '{}' "刷新显示"

    echo ""
    warn "等待 15 秒让刷新完成..."
    sleep 15

    # 显示渐变图案在红色层
    info "生成渐变图案..."
    gen_gradient_half 0 > /tmp/epd_grad_red0.bin
    gen_gradient_half 0 > /tmp/epd_grad_red1.bin
    gen_white_half     > /tmp/epd_grad_black0.bin
    gen_white_half     > /tmp/epd_grad_black1.bin

    post_bin "$BASE/display/black/0" /tmp/epd_grad_black0.bin "黑色层上半 (全白)"
    post_bin "$BASE/display/black/1" /tmp/epd_grad_black1.bin "黑色层下半 (全白)"
    post_bin "$BASE/display/red/0"   /tmp/epd_grad_red0.bin   "红色层上半 (渐变)"
    post_bin "$BASE/display/red/1"   /tmp/epd_grad_red1.bin   "红色层下半 (渐变)"

    post_json "$BASE/display/refresh" '{}' "刷新显示"
}

test_clear() {
    echo ""
    echo "============================================"
    echo "  4/5 🧹 清屏测试"
    echo "============================================"
    post_json "$BASE/display/clear" '{}' "清屏"
}

test_sleep() {
    echo ""
    echo "============================================"
    echo "  5/5 💤 进入睡眠模式"
    echo "============================================"
    post_json "$BASE/display/sleep" '{}' "睡眠"
}

# ---- 主流程 ----
echo "============================================"
echo "  📟 EPD Display 测试工具"
echo "  目标: ${BASE}"
echo "============================================"

case "$CMD" in
    all)
        test_status
        sleep 1
        test_text
        sleep 3
        test_pattern
        test_clear
        # test_sleep  # 默认不清屏+睡眠，方便观察
        echo ""
        ok "全套测试完成!"
        ;;
    status)   test_status ;;
    text)     test_text ;;
    pattern)  test_pattern ;;
    clear)    test_clear ;;
    refresh)  post_json "$BASE/display/refresh" '{}' "刷新";;
    sleep)    test_sleep ;;
    *)
        err "未知命令: $CMD"
        echo "可用命令: all, status, text, pattern, clear, refresh, sleep"
        exit 1
        ;;
esac

# 清理临时文件
rm -f /tmp/epd_*.bin
