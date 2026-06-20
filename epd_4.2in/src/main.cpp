/**
 * @file main.cpp
 * @brief ESP8266 + 4.2" Tri-color (B/W/R) e-Paper Display
 *        HTTP Server (port 80) + Raw TCP Image Stream (port 81)
 * 
 * Hardware: NodeMCU v2 (ESP8266) + Waveshare 4.2" B V2 e-Paper (400×300)
 * Framework: PlatformIO + Arduino
 * 
 * Pin Mapping:
 *   CS  = GPIO15  (SPI chip select)
 *   RST = GPIO2   (Reset)
 *   DC  = GPIO4   (Data/Command)
 *   BUSY= GPIO5   (Busy detection, input pull-up)
 * 
 * ===================== 端口分配 =====================
 * 
 *   HTTP :80  → 状态 / 文字 / 刷新 / 清屏 / 睡眠 / OTA
 *   TCP  :81  → 原始二进制图像数据
 * 
 * ===================== TCP 图像协议 (:81) =====================
 * 
 * 每个 TCP 连接是一次独立事务:
 *   连接 → 1字节命令 → [7500字节位图] → 断开
 * 
 * 命令:
 *   0x00 = 黑色层上半    (需 7500 bytes 后续数据)
 *   0x01 = 黑色层下半    (需 7500 bytes 后续数据)
 *   0x02 = 红色层上半    (需 7500 bytes 后续数据)
 *   0x03 = 红色层下半    (需 7500 bytes 后续数据)
 *   0xFF = 刷新显示      (无后续数据)
 * 
 * 位图格式:
 *   1bpp, 行优先 (row-major), MSB first
 *   pixel(x,y) = byte[x/8 + y*50] 的 bit[7 - x%8]
 *   bit=1 → 白色, bit=0 → 该层颜色 (黑/红)
 * 
 * ===================== HTTP API (:80) =====================
 * 
 *   GET  /                   → 状态页面
 *   GET  /api/wifi           → 设备状态 (JSON)
 *   POST /display/refresh    → 刷新屏幕
 *   POST /display/clear      → 清屏 (全白)
 *   POST /display/sleep      → 屏幕睡眠
 *   POST /display/text       → 绘制文字 (JSON body)
 *   POST /update             → OTA 固件更新
 * 
 * 文字 JSON:
 *   {"layer":"black|red","half":0|1,"text":"...",
 *    "x":0,"y":0,"font":"Font16",
 *    "fg":"black|white","bg":"black|white","clear":false}
 *   字体: Font8/12/16/20/24 (ASCII) | Font12CN/24CN (中文)
 * 
 * ===================== 设计决策 =====================
 * 
 * 为什么不直接用 HTTP POST 传图像?
 *   ESP8266WebServer 内部用 String _plain 存储 body。
 *   7500 字节的二进制 body → String 扩容到 ~8K-16K。
 *   加上半缓冲区后峰值 > 14K 空闲堆 → OOM 崩溃。
 *   TCP raw socket 直接 readBytes() 进预分配缓冲区，
 *   峰值仅 7500 字节，完全可控。
 * 
 * 为什么只分配 7500 字节 (half) 而不是 15000 (full)?
 *   ESP8266 编译后静态 RAM ~53KB，
 *   运行时空闲 ~24KB (含网络栈)。
 *   全屏缓冲区 15000 字节 + 框架开销 ≈ 20KB，
 *   几乎用完空闲 RAM，WiFi/HTTP 操作会不稳定。
 */

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266HTTPUpdateServer.h>
#include <ESP8266mDNS.h>
#include <WiFiClient.h>

#include "DEV_Config.h"
#include "EPD_4in2b_V2.h"
#include "GUI_Paint.h"
#include "Debug.h"

// ============================================================
// WiFi — 凭据在 wifi_config.h (不入 git, 模板见 wifi_config.example.h)
// ============================================================
#include "wifi_config.h"

// ============================================================
// 图像数据常量
// ============================================================
#define HALF_WIDTH_BYTES  (((EPD_4IN2B_V2_WIDTH % 8 == 0) ? \
    (EPD_4IN2B_V2_WIDTH / 8) : (EPD_4IN2B_V2_WIDTH / 8 + 1)))
#define IMG_HALF_SIZE    (HALF_WIDTH_BYTES * (EPD_4IN2B_V2_HEIGHT / 2))
// = 50 * 150 = 7500 bytes

// TCP 图像命令
#define CMD_BLACK_TOP    0x00
#define CMD_BLACK_BOTTOM 0x01
#define CMD_RED_TOP      0x02
#define CMD_RED_BOTTOM   0x03
#define CMD_REFRESH      0xFF

// ============================================================
// Globals
// ============================================================
static ESP8266WebServer httpServer(80);
static ESP8266HTTPUpdateServer httpUpdater;
static WiFiServer rawServer(81);       // TCP raw image port
static UBYTE *g_ImgBuf = NULL;         // 7500-byte half-screen buffer

static char g_WiFiSSID[32] = WIFI_SSID;
static char g_WiFiPass[64] = WIFI_PASS;

// ============================================================
// Forward declarations
// ============================================================
static void handleRoot(void);
static void handleDisplayRefresh(void);
static void handleDisplayClear(void);
static void handleDisplaySleep(void);
static void handleDisplayText(void);
static void handleWiFiStatus(void);
static void handleNotFound(void);
static void handleRawClient(WiFiClient &client);
static void setupWiFi(void);

// ============================================================
// 不再预分配半缓冲区。二进制 POST 直接使用 server.arg("plain") 
// 的 String 内部缓冲区 (c_str()) 发送到屏幕，避免重复分配。
// 文字 API 需要时临时分配。
// ============================================================

// ============================================================
// HTTP Handlers
// ============================================================

/**
 * GET / — Status page
 */
static void handleRoot(void)
{
    String html = "<!DOCTYPE html><html><head>";
    html += "<meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>";
    html += "<title>EPD Display</title>";
    html += "<style>body{font-family:sans-serif;margin:2em;background:#f5f5f5}";
    html += ".card{background:#fff;border-radius:8px;padding:1.5em;margin:1em 0;box-shadow:0 2px 4px rgba(0,0,0,.1)}";
    html += "code{background:#eee;padding:.2em .5em;border-radius:3px}";
    html += "table{width:100%;border-collapse:collapse}";
    html += "th,td{text-align:left;padding:.5em;border-bottom:1px solid #ddd}</style></head><body>";
    html += "<h1>📟 EPD Display Controller</h1>";
    html += "<div class='card'><h2>System</h2><table>";
    html += "<tr><td>WiFi</td><td>" + String(WiFi.SSID()) + " (" + WiFi.localIP().toString() + ")</td></tr>";
    html += "<tr><td>Signal</td><td>" + String(WiFi.RSSI()) + " dBm</td></tr>";
    html += "<tr><td>Up</td><td>" + String(millis()/1000) + "s</td></tr>";
    html += "<tr><td>Heap</td><td>" + String(ESP.getFreeHeap()) + " bytes</td></tr>";
    html += "</table></div>";
    html += "<div class='card'><h2>API</h2><table>";
    html += "<tr><th>方式</th><th>端点</th><th>说明</th></tr>";
    html += "<tr><td>TCP:81</td><td><code>0x00+7500b</code></td><td>黑色层上半</td></tr>";
    html += "<tr><td>TCP:81</td><td><code>0x01+7500b</code></td><td>黑色层下半</td></tr>";
    html += "<tr><td>TCP:81</td><td><code>0x02+7500b</code></td><td>红色层上半</td></tr>";
    html += "<tr><td>TCP:81</td><td><code>0x03+7500b</code></td><td>红色层下半</td></tr>";
    html += "<tr><td>TCP:81</td><td><code>0xFF</code></td><td>刷新显示</td></tr>";
    html += "<tr><td>POST</td><td><code>/display/refresh</code></td><td>刷新</td></tr>";
    html += "<tr><td>POST</td><td><code>/display/clear</code></td><td>清屏</td></tr>";
    html += "<tr><td>POST</td><td><code>/display/sleep</code></td><td>睡眠</td></tr>";
    html += "<tr><td>POST</td><td><code>/display/text</code></td><td>画文字</td></tr>";
    html += "<tr><td>GET</td><td><code>/api/wifi</code></td><td>状态 JSON</td></tr>";
    html += "</table></div></body></html>";
    httpServer.send(200, "text/html", html);
}

// ============================================================
// TCP 图像处理 (:81)
//
// 内存策略: g_ImgBuf 懒惰分配，只在首次 TCP 连接时 malloc。
// 不会与 HTTP body String 同时存在（TCP 直接读入缓冲区，
// 无服务器侧 body 字符串），峰值内存 ~7500 字节。
// ============================================================
static void handleRawClient(WiFiClient &client)
{
    // Read command byte
    int cmd = client.read();
    if (cmd < 0) return;

    Debug("TCP cmd=");
    Debug(String(cmd, HEX).c_str());
    Debug("\r\n");

    if (cmd == CMD_REFRESH) {
        EPD_4IN2B_V2_TurnOnDisplay();
        client.stop();
        return;
    }

    // Ensure buffer is allocated
    if (g_ImgBuf == NULL) {
        g_ImgBuf = (UBYTE *)malloc(IMG_HALF_SIZE);
        if (g_ImgBuf == NULL) {
            Debug("TCP: malloc failed!\r\n");
            client.stop();
            return;
        }
    }

    // Read exactly IMG_HALF_SIZE bytes with timeout
    size_t n = client.readBytes(g_ImgBuf, IMG_HALF_SIZE);
    if (n != IMG_HALF_SIZE) {
        Debug("TCP: expected ");
        Debug(String(IMG_HALF_SIZE).c_str());
        Debug(" got ");
        Debug(String((int)n).c_str());
        Debug("\r\n");
        client.stop();
        return;
    }

    // Send to EPD
    switch (cmd) {
    case CMD_BLACK_TOP:    
        EPD_4IN2B_V2_SendHalfBimage(0, g_ImgBuf); break;
    case CMD_BLACK_BOTTOM: 
        EPD_4IN2B_V2_SendHalfBimage(1, g_ImgBuf); break;
    case CMD_RED_TOP:      
        EPD_4IN2B_V2_SendHalfRYimage(0, g_ImgBuf); break;
    case CMD_RED_BOTTOM:   
        EPD_4IN2B_V2_SendHalfRYimage(1, g_ImgBuf); break;
    default:
        Debug("TCP: unknown cmd\r\n"); break;
    }

    client.stop();
}

/**
 * POST /display/refresh
 */
static void handleDisplayRefresh(void)
{
    EPD_4IN2B_V2_TurnOnDisplay();
    httpServer.send(200, "text/plain", "Refreshed");
}

/**
 * POST /display/clear
 */
static void handleDisplayClear(void)
{
    EPD_4IN2B_V2_Clear();
    httpServer.send(200, "text/plain", "Cleared");
}

/**
 * POST /display/sleep
 */
static void handleDisplaySleep(void)
{
    EPD_4IN2B_V2_Sleep();
    httpServer.send(200, "text/plain", "Sleeping");
}

/**
 * POST /display/text — 绘制文字
 * 
 * 临时分配 7500 字节缓冲区用于绘图，绘制完成后立即释放。
 * 文字 JSON 较小，不会触发 OOM。
 */
static void handleDisplayText(void)
{
    String body = httpServer.arg("plain");
    
    auto getStr = [&](const String &key, const String &def) -> String {
        int idx = body.indexOf("\"" + key + "\"");
        if (idx < 0) return def;
        int colon = body.indexOf(':', idx);
        if (colon < 0) return def;
        while (colon+1 < (int)body.length() && body[colon+1]==' ') colon++;
        if (body[colon+1] == '"') {
            int s = colon+2, e = body.indexOf('"', s);
            return (e<0) ? def : body.substring(s, e);
        }
        int e = colon+1;
        while (e < (int)body.length() && body[e]!=',' && body[e]!='}') e++;
        return body.substring(colon+1, e);
    };
    auto getInt = [&](const String &k, int d) -> int { return getStr(k, String(d)).toInt(); };

    String layer   = getStr("layer", "black");
    int half       = getInt("half", 0);
    String text    = getStr("text", "");
    int x          = getInt("x", 0);
    int y          = getInt("y", 0);
    String fontStr = getStr("font", "Font16");
    String fgStr   = getStr("fg", "black");
    String bgStr   = getStr("bg", "white");
    bool clr       = getStr("clear", "false") == "true";

    UWORD fg = (fgStr=="white") ? WHITE : BLACK;
    UWORD bg = (bgStr=="white") ? WHITE : BLACK;
    bool isCN = false;

    sFONT *font = &Font16;
    cFONT *cn = NULL;
    if      (fontStr=="Font8")    font=&Font8;
    else if (fontStr=="Font12")   font=&Font12;
    else if (fontStr=="Font20")   font=&Font20;
    else if (fontStr=="Font24")   font=&Font24;
    else if (fontStr=="Font12CN") { cn=&Font12CN; isCN=true; }
    else if (fontStr=="Font24CN") { cn=&Font24CN; isCN=true; }

    UBYTE *buf = (UBYTE*)malloc(IMG_HALF_SIZE);
    if (!buf) { httpServer.send(503, "text/plain", "OOM"); return; }
    
    Paint_NewImage(buf, EPD_4IN2B_V2_WIDTH, EPD_4IN2B_V2_HEIGHT/2, 0, WHITE);
    Paint_SelectImage(buf);
    Paint_SetScale(2);
    if (clr) Paint_Clear(WHITE);

    if (isCN && cn) Paint_DrawString_CN(x, y, text.c_str(), cn, fg, bg);
    else            Paint_DrawString_EN(x, y, text.c_str(), font, fg, bg);

    if (layer=="black") EPD_4IN2B_V2_SendHalfBimage(half, buf);
    else                EPD_4IN2B_V2_SendHalfRYimage(half, buf);
    
    free(buf);
    httpServer.send(200, "text/plain", "OK");
}

/**
 * GET /api/wifi
 */
static void handleWiFiStatus(void)
{
    String j = "{";
    j += "\"ssid\":\"" + String(WiFi.SSID()) + "\",";
    j += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
    j += "\"rssi\":" + String(WiFi.RSSI()) + ",";
    j += "\"mac\":\"" + WiFi.macAddress() + "\",";
    j += "\"freeHeap\":" + String(ESP.getFreeHeap()) + ",";
    j += "\"uptime\":" + String(millis()/1000);
    j += "}";
    httpServer.send(200, "application/json", j);
}

static void handleNotFound(void)
{
    httpServer.send(404, "text/plain", "Not Found: " + httpServer.uri());
}

// ============================================================
// WiFi
// ============================================================
static void setupWiFi(void)
{
    WiFi.mode(WIFI_AP_STA);
    WiFi.begin(g_WiFiSSID, g_WiFiPass);
    WiFi.setAutoReconnect(true);

    IPAddress apIP(192,168,4,1);
    WiFi.softAPConfig(apIP, apIP, IPAddress(255,255,255,0));
    WiFi.softAP("EPD-Setup", "config123");

    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) {
        delay(500);
        Debug(".");
    }
    Debug("\r\n");

    if (WiFi.status() == WL_CONNECTED) {
        Debug("WiFi: ");
        Debug(WiFi.localIP().toString().c_str());
        Debug("\r\n");
        WiFi.softAPdisconnect(true);

        // mDNS for easy device discovery
        if (MDNS.begin("epd-display")) {
            MDNS.addService("http", "tcp", 80);
            Debug("mDNS: epd-display.local\r\n");
        }
    } else {
        Debug("WiFi fail, AP: EPD-Setup / 192.168.4.1\r\n");
    }
}

// ============================================================
// Setup
// ============================================================
void setup()
{
    DEV_Module_Init();

    Debug("\r\n========================================\r\n");
    Debug("EPD 4.2\" B V2 — HTTP:80 + TCP:81\r\n");
    Debug("========================================\r\n");

    EPD_4IN2B_V2_Init();
    EPD_4IN2B_V2_Clear();
    Debug("EPD ready.\r\n");

    setupWiFi();

    // HTTP routes
    httpServer.on("/", HTTP_GET, handleRoot);
    httpServer.on("/display/refresh", HTTP_POST, handleDisplayRefresh);
    httpServer.on("/display/clear", HTTP_POST, handleDisplayClear);
    httpServer.on("/display/sleep", HTTP_POST, handleDisplaySleep);
    httpServer.on("/display/text", HTTP_POST, handleDisplayText);
    httpServer.on("/api/wifi", HTTP_GET, handleWiFiStatus);
    httpServer.onNotFound(handleNotFound);
    httpUpdater.setup(&httpServer, "/update");

    httpServer.begin();
    rawServer.begin();

    Debug("HTTP :80  TCP :81\r\n");
}

// ============================================================
// Loop
// ============================================================
void loop()
{
    httpServer.handleClient();
    MDNS.update();

    // Handle raw TCP image connections
    WiFiClient raw = rawServer.accept();
    if (raw && raw.connected()) {
        handleRawClient(raw);
    }

    yield();
}