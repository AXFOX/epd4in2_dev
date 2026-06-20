# Project Guidelines

## Overview
ESP8266 (NodeMCU v2) 驱动 4.2 英寸黑白红三色墨水屏（400×300），通过 PlatformIO + Arduino 框架开发。
目标：在下位机上实现 HTTP Server，接收上位机请求后显示图片/文字。

## Build Commands
- **Build**: `pio run`
- **Upload**: `pio run -t upload`
- **Clean**: `pio run -t clean`
- **Monitor**: `pio device monitor`（波特率 115200）
- **Build+Upload+Monitor**: `pio run -t upload && pio device monitor`

## Hardware

### Pin Mapping
| 信号 | GPIO | 说明 |
|------|------|------|
| CS   | 15   | SPI 片选 |
| RST  | 2    | 复位 |
| DC   | 4    | 数据/命令 |
| BUSY | 5    | 忙检测（输入上拉） |

SPI 通过 `SPI.transfer()` 通信。延时统一使用 `DEV_Delay_ms()` 宏（封装自 `delay()`）。

### Reference
硬件文档：https://www.waveshare.net/wiki/E-Paper_ESP8266_Driver_Board

## Architecture
分层设计（驱动代码参考 `arduino_test_demo/` 和 `epd4in2b_V2-demo/`）：

```
应用层 ──→ GUI_Paint ──→ EPD Driver ──→ DEV_Config ──→ ESP8266 HW
                │                           │
            framebuffer                  GPIO + SPI
          绘图/文本 API                  硬件抽象层
```

### Layer Details

1. **`DEV_Config.h/.cpp`** — 硬件抽象层
   - GPIO 初始化、SPI 读写
   - 类型别名：`UBYTE`=`uint8_t`, `UWORD`=`uint16_t`, `UDOUBLE`=`uint32_t`
   - 宏：`DEV_Digital_Write()`, `DEV_Digital_Read()`, `DEV_Delay_ms()`

2. **`EPD_4in2b_V2.h/.cpp`** — 墨水屏驱动（三色 B V2）
   - 分辨率 400×300
   - `Display(blackImage, redImage)` — 双缓冲区显示
   - `Display_4Gray()` — 4 级灰度模式
   - 因内存限制，图像分 4 次发送：黑上半、黑下半、红上半、红下半
   - 对应函数：`SendHalfBimage()`, `SendHalfRYimage()`

3. **`GUI_Paint.h/.cpp`** — 帧缓冲绘图库（Waveshare V3.2）
   - 点/线/矩形/圆绘制
   - ASCII 文本 + 中文 GB2312 文本渲染
   - `Scale` 参数：`2`=1bpp 单色, `4`=2bpp 4 级灰度
   - 颜色常量：`WHITE=0xFF`, `BLACK=0x00`

4. **字体**（`fonts.h` + `font*.cpp/c`）
   - ASCII：`Font8` / `Font12` / `Font16` / `Font20` / `Font24`
   - 中文 GB2312：`Font12CN` / `Font24CN`

## Key Constraints
- **内存紧张**：ESP8266 ~80KB RAM，编译后静态占用 ~53KB，运行时空闲 ~24KB
- **HTTP body 限制**：ESP8266WebServer 不能处理大 POST body（>~5KB 会 OOM），图像数据走 TCP :81
- **图像分半发送**：每半屏 7500 字节，全屏 4 次发送 + 1 次刷新
- **刷新速度**：墨水屏全刷约 15 秒，避免频繁刷新
- **Flash 空间**：4MB (当前占用~33%)

## Project Structure
```
epd4in2_dev/
├── AGENTS.md              ← AI 代理指南
└── epd_4.2in/              ← 主开发项目（PlatformIO）
    ├── platformio.ini
    ├── test_epd.py         ← Python 上位机测试工具
    ├── src/main.cpp         ← 应用入口 (HTTP Server + TCP Raw Server)
    └── lib/epd_driver/     ← 墨水屏驱动库 (17 个文件)
```

> 驱动代码源自 Waveshare 官方 Arduino 示例（4.2" B V2 三色屏），已迁移至 `lib/epd_driver/`。
> 寄存器参数参考：`arduino_test_demo/`（黑白 V2）和 `epd4in2b_V2-demo/`（三色 B V2），
> 已删除但信息保留在 git 历史中。

## Network Architecture

```
上位机
  ├─ HTTP :80  → 状态 / 文字 / 刷新 / 清屏 / 睡眠 / OTA
  └─ TCP  :81  → 原始二进制图像数据 (绕过 HTTP body 内存限制)
```

### 为什么用双端口？
ESP8266WebServer 内部用 `String _plain` 存储 POST body。7500 字节的二进制 body 会导致 String 扩容到 8K~16K，结合半缓冲区后超出 ~14K 空闲堆导致崩溃。TCP raw socket 直接将数据读入预分配缓冲区，无额外 String 开销。

### TCP 图像协议 (Port 81)
每个 TCP 连接是一次独立事务：
```
连接 → 发送 1 字节命令头 → [发送 7500 字节位图数据] → 断开
```
| 命令 | 后续数据 | 说明 |
|------|---------|------|
| `0x00` | 7500 bytes | 黑色层上半 |
| `0x01` | 7500 bytes | 黑色层下半 |
| `0x02` | 7500 bytes | 红色层上半 |
| `0x03` | 7500 bytes | 红色层下半 |
| `0xFF` | — | 刷新显示 |

### HTTP API (Port 80)
| 方法 | 路径 | Body | 说明 |
|------|------|------|------|
| `GET` | `/` | — | 状态页面 (HTML) |
| `GET` | `/api/wifi` | — | 设备状态 (JSON) |
| `POST` | `/display/refresh` | — | 刷新屏幕 |
| `POST` | `/display/clear` | — | 清屏 (全白) |
| `POST` | `/display/sleep` | — | 屏幕睡眠 |
| `POST` | `/display/text` | JSON | 绘制文字 |
| `POST` | `/update` | firmware | OTA 固件更新 |

### 文字 API (`POST /display/text`)
```json
{
  "layer": "black",
  "half": 0,
  "text": "Hello",
  "x": 10, "y": 10,
  "font": "Font24",
  "fg": "black", "bg": "white",
  "clear": false
}
```
字体: `Font8/12/16/20/24` (ASCII) | `Font12CN/24CN` (中文 GB2312)

### 位图数据格式
- 半屏块 = 7500 bytes = 50 bytes/行 × 150 行
- 1bpp, 行优先, MSB first: pixel(x,y) = byte[x/8 + y×50] 的 bit[7−x%8]
- bit=1 → 白色, bit=0 → 该层颜色 (黑/红)

### 上位机发送完整图像流程
```
1. TCP 0x00 + black_top_7500b
2. TCP 0x01 + black_bottom_7500b
3. TCP 0x02 + red_top_7500b
4. TCP 0x03 + red_bottom_7500b
5. HTTP POST /display/refresh
```
也可用 TCP `0xFF` 代替第 5 步。

### 自动化刷新 (可选)
代码中已预留自动刷新逻辑 (注释掉的 `g_ChunkFlags == 0x0F` 检测)，可在收到全部 4 块后自动触发刷新。

## Conventions
- 使用 Waveshare 类型别名：`UBYTE`、`UWORD`、`UDOUBLE`
- 延时用 `DEV_Delay_ms()`，不用裸 `delay()`
- SPI 写字节用 `DEV_SPI_WriteByte()`（封装 `SPI.transfer()`）
- 调试输出用 `Debug()` 宏（`Debug.h` 定义）
- 代码风格：ESP8266 Arduino 框架标准

## Available Network Libraries
已内置在 ESP8266 Arduino 框架中，可直接 `#include`：
- `ESP8266WiFi.h` — WiFi 连接管理
- `ESP8266WebServer.h` — HTTP Server
- `ESP8266HTTPClient.h` — HTTP Client
- `DNSServer.h` — DNS Server（用于 captive portal）
- `ESP8266HTTPUpdateServer.h` — OTA 更新
