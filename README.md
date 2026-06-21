# epd4in2_dev — ESP8266 驱动 4.2 英寸 三色墨水屏（400×300）

项目概述
--------

本项目基于 ESP8266（NodeMCU v2）与 电子价签 4.2" 三色（黑/白/红）墨水屏（分辨率 400×300）开发，使用 PlatformIO + Arduino 框架。目标是在设备端提供 HTTP 与 TCP 服务，允许上位机发送文字或位图并在墨水屏上显示。

主要功能
--------

- HTTP API（端口 80）：设备状态、文字绘制、刷新、清屏、睡眠、OTA 等。
- TCP 原始数据服务（端口 81）：传输二进制位图数据（半屏块）以绕过 HTTP POST body 的内存限制。
- 基于 Waveshare 驱动的显示控制与帧缓冲绘图库（`lib/epd_driver/`）。

工程结构（概要）
----------------

```
epd4in2_dev/
├── AGENTS.md                # 代理与项目设计文档
├── README.md                # 本文件
└── epd_4.2in/
    ├── platformio.ini
    ├── test_epd.py         # 上位机测试脚本
    ├── src/
    │   └── main.cpp        # 应用入口（HTTP + TCP 服务器）
    └── lib/epd_driver/     # 墨水屏驱动与字体
```

硬件连接（引脚映射）  
----------------

| 信号 | GPIO | 说明 |
|------|------|------|
| CS   | 15   | SPI 片选 |
| RST  | 2    | 复位 |
| DC   | 4    | 数据/命令 |
| BUSY | 5    | 忙检测（输入上拉） |

*AI生成的README没什么看头，自己看文档对比个人设备的SPI接口引脚定义*
SPI 使用 `SPI.transfer()` 通信，延时使用封装宏 `DEV_Delay_ms()`。

构建与运行
---------

在项目目录（`epd_4.2in/`）下使用 PlatformIO：

```bash
pio run                # 构建固件
pio run -t upload      # 烧录设备（自动检测 /dev/ttyUSB0）
pio run -t clean       # 清理
pio device monitor     # 串口监视（115200）
```

网络架构与协议
---------------

两端口设计：

- HTTP（:80）：用于控制命令、状态查询与触发刷新（长时阻塞操作在 HTTP handler 中异步处理，先返回响应再执行刷新以避免看门狗复位）。
- TCP（:81）：用于传输二进制位图数据（每次连接为一次事务），避免 `ESP8266WebServer` 在处理大二进制 POST body 时的内存问题。

TCP 位图协议（端口 81）
------------------

每个 TCP 连接发送：1 字节命令头 + 7500 字节半屏数据（单向事务，发送完成后断开）。命令定义：

| 命令 | 数据 | 说明 |
|------|------|------|
| 0x00 | 7500 bytes | 黑色层 上半 |
| 0x01 | 7500 bytes | 黑色层 下半 |
| 0x02 | 7500 bytes | 红色层 上半 |
| 0x03 | 7500 bytes | 红色层 下半 |
| 0xFF | — | 刷新显示（已废弃 — 推荐使用 HTTP `/display/refresh`） |

完整上传流程示例（上位机）：

1. 发送 TCP 0x00 + black_top_7500b
2. 发送 TCP 0x01 + black_bottom_7500b
3. 发送 TCP 0x02 + red_top_7500b
4. 发送 TCP 0x03 + red_bottom_7500b
5. 使用 HTTP POST /display/refresh 触发物理刷新（或 TCP 0xFF，但不推荐）

HTTP API（常用）
----------------

- `GET /` — 状态页面
- `GET /api/wifi` — 设备状态（JSON）
- `POST /display/refresh` — 刷新屏幕（会先返回 HTTP 响应再实际刷新）
- `POST /display/clear` — 清屏（全白）
- `POST /display/sleep` — 屏幕睡眠
- `POST /display/text` — 绘制文字（JSON body）
- `POST /update` — OTA 固件更新

`POST /display/text` 示例：

```json
{
  "layer": "black",
  "half": 0,
  "text": "Hello",
  "x": 10,
  "y": 10,
  "font": "Font24",
  "fg": "black",
  "bg": "white",
  "clear": false
}
```

位图数据格式说明
----------------

- 半屏块 = 7500 bytes = 50 bytes/行 × 150 行
- 1bpp，行优先，MSB first：pixel(x,y) 位于 `byte[x/8 + y*50]` 的 bit[7−x%8]
- bit=1 → 白色；bit=0 → 对应层颜色（黑/红）

关键注意事项
-------------

- 内存紧张：ESP8266 约 80KB RAM，HTTP POST 二进制 body 超过数 KB 会导致 `String` 扩容并触发 OOM，因此图像数据应走 TCP :81。
- 刷新阻塞：`TurnOnDisplay()` 会阻塞大约 15 秒（轮询 BUSY），因此不要在 TCP handler 中直接调用刷新；应通过 HTTP 接口先返回响应再执行刷新。
- 避免逐字节手写 SPI：使用库中提供的 `SendHalfBimage()` / `SendHalfRYimage()` 等函数，这些实现包含必要的 `yield()`/延时以防看门狗复位。
- 延时统一使用 `DEV_Delay_ms()` 宏，不要直接调用裸 `delay()`。

开发与调试
-----------

- 驱动代码位置：`epd_4.2in/lib/epd_driver/`
- 应用入口：`epd_4.2in/src/main.cpp`
- 上位机测试脚本：`epd_4.2in/test_epd.py`

后续/贡献
---------

欢迎提交 issues 或 PR。若需要我：

- 将 README 同步到 `epd_4.2in/` 子目录下；
- 帮你生成示例上位机脚本或演示图片上传脚本。

许可
----

请在仓库中补充 LICENSE 文件以明确许可条款（当前未指定）。

----

更多技术细节请参阅 `AGENTS.md` 与 `epd_4.2in/` 下的源代码。

## 更新日志

### 2025-06-22 — v1.1 关键修复

| # | 问题 | 根因 | 修复 |
|---|------|------|------|
| 1 | 串口乱码（115200 二进制噪声） | ESP8266 SDK 内部 `os_printf` 绕过 Arduino `Serial` 直接写 UART0 | `setup()` 开头调用 `system_set_os_print(0)` |
| 2 | 必须先清屏再发图才能显示 | `TurnOnDisplay()` 后 EPD RAM 地址指针停留在末尾，后续 `0x24`/`0x26` 写入未复位 | `SendHalfBimage(0)` / `SendHalfRYimage(0)` 中加 `SetWindows` + `SetCursor(0,0)` |
| 3 | 红色层不显示 | `SetCursor` 函数缺 `Xstart>>3`（像素→字节转换）；`WiFiClient::readBytes()` 阻塞不 yield 导致 lwIP TCP 窗口死锁 | 修正 `(Xstart>>3)`；实现 `readWithYield()` 替代 `readBytes()` |
| 4 | TCP 数据包丢失 | `rawServer.accept()` 后 `client.connected()` 可能短暂返回 false 导致连接被跳过 | 移除 `raw.connected()` 检查 |
| 5 | 7500 字节超过 TCP 接收窗口 | ESP8266 lwIP 默认 `TCP_WND=5840` | `platformio.ini` 添加 `-DTCP_WND=8760` |
