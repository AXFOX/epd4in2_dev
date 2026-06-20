#!/usr/bin/env python3
"""
EPD Display 上位机测试工具
=============================

用法:
  python3 test_epd.py <IP> [命令]
  python3 test_epd.py 192.168.31.212 status      查看设备状态
  python3 test_epd.py 192.168.31.212 clear        清屏
  python3 test_epd.py 192.168.31.212 checker      棋盘格测试图案
  python3 test_epd.py 192.168.31.212 gradient     渐变测试图案
  python3 test_epd.py 192.168.31.212 text         文字显示测试

=== 通信协议 ===

  上位机 → ESP8266

  TCP :81 (图像数据传输)
    连接 → 1字节命令 → [7500字节原始1bpp位图] → 断开

    命令:
      0x00  黑色层上半 (rows 0-149)
      0x01  黑色层下半 (rows 150-299)
      0x02  红色层上半 (rows 0-149)
      0x03  红色层下半 (rows 150-299)
      0xFF  刷新显示 (触发 EPD_4IN2B_V2_TurnOnDisplay)

    位图格式:
      - 7500 bytes = 50 bytes/行 × 150 行
      - 1bpp, 行优先 (row-major), MSB first
      - pixel(x,y) = byte[x/8 + y*50] 的 bit[7 - x%8]
      - bit=1 → 白色, bit=0 → 该层颜色 (黑/红)

  HTTP :80 (控制与状态)
    GET  /api/wifi           →  {"ssid":"...","ip":"...","rssi":...,...}
    POST /display/refresh    →  刷新墨水屏
    POST /display/clear      →  清屏 (全白)
    POST /display/sleep      →  屏幕深度睡眠
    POST /display/text       →  绘制文字 (JSON body)
    POST /update             →  OTA 固件更新

  文字 JSON:
    {
      "layer": "black|red",
      "half": 0|1,
      "text": "要显示的文字",
      "x": 0, "y": 0,
      "font": "Font8|Font12|Font16|Font20|Font24|Font12CN|Font24CN",
      "fg": "black|white",
      "bg": "black|white",
      "clear": true|false
    }

=== 典型工作流 ===

  上位机发送完整图像:
    1. TCP 0x00 + black_top_7500b
    2. TCP 0x01 + black_bottom_7500b
    3. TCP 0x02 + red_top_7500b
    4. TCP 0x03 + red_bottom_7500b
    5. TCP 0xFF  (or HTTP POST /display/refresh)

  清屏:
    HTTP POST /display/clear

  显示文字:
    HTTP POST /display/text  (with JSON body)

=== 依赖 ===

  Python 3.6+ (标准库 only, 无第三方依赖)
"""
import socket, sys, time, json, urllib.request

HALF_SIZE = 7500
WIDTH_BYTES = 50

def tcp_send(ip, cmd, data=b''):
    """通过 TCP port 81 发送命令"""
    s = socket.socket()
    s.settimeout(5)
    s.connect((ip, 81))
    s.sendall(bytes([cmd]) + data)
    s.close()

def http_post(ip, path, body=''):
    """通过 HTTP POST 发送请求"""
    req = urllib.request.Request(f'http://{ip}{path}',
        data=body.encode() if body else b'',
        headers={'Content-Type': 'application/json'} if body else {})
    return urllib.request.urlopen(req).read().decode()

def http_get(ip, path):
    return urllib.request.urlopen(f'http://{ip}{path}').read().decode()

# ---- 图案生成 ----
def make_checker(invert=False):
    """棋盘格"""
    img = bytearray(HALF_SIZE)
    for y in range(150):
        for x in range(400):
            idx = x // 8 + y * WIDTH_BYTES
            bit = 7 - (x % 8)
            black = ((x // 16) + (y // 16)) % 2 == 0
            if invert: black = not black
            if black: img[idx] &= ~(1 << bit)
            else:     img[idx] |= (1 << bit)
    return bytes(img)

def make_gradient(invert=False):
    """水平渐变: 左=黑, 右=白"""
    img = bytearray(HALF_SIZE)
    for y in range(150):
        for x in range(400):
            idx = x // 8 + y * WIDTH_BYTES
            bit = 7 - (x % 8)
            # 每列 8 像素一组, 50 列
            col_group = x // 8
            # 0→黑色, 49→白色
            threshold = col_group * 255 // 49
            black = x < threshold if not invert else x >= threshold
            if black: img[idx] &= ~(1 << bit)
            else:     img[idx] |= (1 << bit)
    return bytes(img)

def make_white():
    return b'\xff' * HALF_SIZE

def make_black():
    return b'\x00' * HALF_SIZE

# ---- 命令 ----
def cmd_status(ip):
    data = http_get(ip, '/api/wifi')
    info = json.loads(data)
    print(f"设备: {info['mac']}")
    print(f"WiFi: {info['ssid']}  IP:{info['ip']}  RSSI:{info['rssi']}dBm")
    print(f"堆  : {info['freeHeap']} bytes  运行:{info['uptime']}s")

def cmd_clear(ip):
    print(http_post(ip, '/display/clear'))

def cmd_checker(ip):
    print("发送棋盘格图案...")
    tcp_send(ip, 0x00, make_checker(False))
    tcp_send(ip, 0x01, make_checker(True))
    tcp_send(ip, 0x02, make_white())
    tcp_send(ip, 0x03, make_white())
    print(http_post(ip, '/display/refresh'))   # HTTP refresh (更可靠)
    print("完成!")

def cmd_gradient(ip):
    print("发送渐变图案...")
    tcp_send(ip, 0x00, make_gradient(False))
    tcp_send(ip, 0x01, make_gradient(True))
    tcp_send(ip, 0x02, make_white())
    tcp_send(ip, 0x03, make_white())
    print(http_post(ip, '/display/refresh'))

def cmd_text(ip):
    print("发送文字...")
    # 先全白刷新
    for c in [0x00,0x01,0x02,0x03]:
        tcp_send(ip, c, make_white())
    tcp_send(ip, 0xFF)
    time.sleep(15)  # 等待刷新完成

    # 画文字
    http_post(ip, '/display/text',
        '{"layer":"black","half":0,"text":"Hello EPD!","x":10,"y":10,"font":"Font24","fg":"black","bg":"white"}')
    http_post(ip, '/display/text',
        '{"layer":"black","half":0,"text":"TCP Works!","x":10,"y":50,"font":"Font16","fg":"black","bg":"white"}')
    http_post(ip, '/display/refresh')
    print("完成!")

def cmd_all(ip):
    cmd_status(ip)
    time.sleep(1)
    cmd_clear(ip)
    time.sleep(2)
    cmd_checker(ip)
    time.sleep(20)
    cmd_gradient(ip)
    time.sleep(20)
    cmd_clear(ip)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    ip = sys.argv[1]
    cmd = sys.argv[2] if len(sys.argv) > 2 else 'all'
    
    cmds = {'status':cmd_status, 'clear':cmd_clear, 'checker':cmd_checker,
            'gradient':cmd_gradient, 'text':cmd_text, 'all':cmd_all}
    if cmd in cmds:
        cmds[cmd](ip)
    else:
        print(f"未知命令: {cmd}")
        print(__doc__)
