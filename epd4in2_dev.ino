/* Includes ------------------------------------------------------------------*/
#include "DEV_Config.h"
#include "Debug.h"
#include "EPD_4in2_V2.h"
#include "GUI_Paint.h"
#include "ImageData.h"
#include <stdlib.h>

/* Entry point ----------------------------------------------------------------*/
void setup()
{
    printf("EPD_4IN2_V2_test Demo\r\n");
    DEV_Module_Init();

    printf("e-Paper Init and Clear...\r\n");
    EPD_4IN2_V2_Init();
    EPD_4IN2_V2_Clear();
    DEV_Delay_ms(500);

    // 创建新的图像缓存
    UBYTE *BlackImage;
    UWORD Imagesize = ((EPD_4IN2_V2_WIDTH % 8 == 0)? (EPD_4IN2_V2_WIDTH / 8 ): (EPD_4IN2_V2_WIDTH / 8 + 1)) * EPD_4IN2_V2_HEIGHT;
    if((BlackImage = (UBYTE *)malloc(Imagesize)) == NULL) {
        printf("Failed to apply for black memory...\r\n");
        while (1);
    }
    printf("Paint_NewImage\r\n");
    Paint_NewImage(BlackImage, EPD_4IN2_V2_WIDTH, EPD_4IN2_V2_HEIGHT, 0, WHITE);

#if 1  // 显示 BMP 图片
    printf("show window BMP-----------------\r\n");
    Paint_SelectImage(BlackImage);
    Paint_Clear(WHITE);
    Paint_DrawBitMap(gImage_4in2);
    EPD_4IN2_V2_Display(BlackImage);
    DEV_Delay_ms(2000);
    
#endif        

#if 0  // 显示数组中的图像   
//    EPD_4IN2_V2_Init_Fast(Seconds_1_5S);
    EPD_4IN2_V2_Init_Fast(Seconds_1S);
    printf("show image for array\r\n");
    Paint_SelectImage(BlackImage);
    Paint_Clear(WHITE);
    Paint_DrawBitMap(gImage_4in2);
    EPD_4IN2_V2_Display_Fast(BlackImage);
    DEV_Delay_ms(2000);
#endif

#if 1   // 在图像上绘制
    EPD_4IN2_V2_Init();
    //1. 选择图像
    printf("SelectImage:BlackImage\r\n");
    Paint_SelectImage(BlackImage);
    Paint_Clear(WHITE);

    // 2. 在图像上绘制
    printf("Drawing:BlackImage\r\n");
    Paint_DrawPoint(10, 80, BLACK, DOT_PIXEL_1X1, DOT_STYLE_DFT);
    Paint_DrawPoint(10, 90, BLACK, DOT_PIXEL_2X2, DOT_STYLE_DFT);
    Paint_DrawPoint(10, 100, BLACK, DOT_PIXEL_3X3, DOT_STYLE_DFT);
    Paint_DrawLine(20, 70, 70, 120, BLACK, DOT_PIXEL_1X1, LINE_STYLE_SOLID);
    Paint_DrawLine(70, 70, 20, 120, BLACK, DOT_PIXEL_1X1, LINE_STYLE_SOLID);
    Paint_DrawRectangle(20, 70, 70, 120, BLACK, DOT_PIXEL_1X1, DRAW_FILL_EMPTY);
    Paint_DrawRectangle(80, 70, 130, 120, BLACK, DOT_PIXEL_1X1, DRAW_FILL_FULL);
    Paint_DrawCircle(45, 95, 20, BLACK, DOT_PIXEL_1X1, DRAW_FILL_EMPTY);
    Paint_DrawCircle(105, 95, 20, WHITE, DOT_PIXEL_1X1, DRAW_FILL_FULL);
    Paint_DrawLine(85, 95, 125, 95, BLACK, DOT_PIXEL_1X1, LINE_STYLE_DOTTED);
    Paint_DrawLine(105, 75, 105, 115, BLACK, DOT_PIXEL_1X1, LINE_STYLE_DOTTED);
    Paint_DrawString_EN(10, 0, "waveshare", &Font16, BLACK, WHITE);
    Paint_DrawString_EN(10, 20, "hello world", &Font12, WHITE, BLACK);
    Paint_DrawNum(10, 33, 123456789, &Font12, BLACK, WHITE);
    Paint_DrawNum(10, 50, 987654321, &Font16, WHITE, BLACK);
    Paint_DrawString_CN(130, 0, " 你好abc", &Font12CN, BLACK, WHITE);
    Paint_DrawString_CN(130, 20, "微雪电子", &Font24CN, WHITE, BLACK);

    printf("EPD_Display\r\n");
    EPD_4IN2_V2_Display(BlackImage);
    DEV_Delay_ms(2000);
#endif

#if 1
    printf("Partial refresh\r\n");
    Paint_NewImage(BlackImage, 120, 50, 0, WHITE);
    PAINT_TIME sPaint_time;
    sPaint_time.Hour = 12;
    sPaint_time.Min = 34;
    sPaint_time.Sec = 56;
    UBYTE num = 10;
    for (;;) {
        sPaint_time.Sec = sPaint_time.Sec + 1;
        if (sPaint_time.Sec == 60) {
            sPaint_time.Min = sPaint_time.Min + 1;
            sPaint_time.Sec = 0;
            if (sPaint_time.Min == 60) {
                sPaint_time.Hour =  sPaint_time.Hour + 1;
                sPaint_time.Min = 0;
                if (sPaint_time.Hour == 24) {
                    sPaint_time.Hour = 0;
                    sPaint_time.Min = 0;
                    sPaint_time.Sec = 0;
                }
            }
        }
        Paint_Clear(WHITE);
        Paint_DrawRectangle(1, 1, 120, 50, BLACK, DOT_PIXEL_1X1, DRAW_FILL_EMPTY);
        Paint_DrawTime(10, 15, &sPaint_time, &Font20, WHITE, BLACK);
        EPD_4IN2_V2_PartialDisplay(BlackImage, 200, 80, 320, 130);
        DEV_Delay_ms(500);//模拟时钟 1 秒
        num = num - 1;
        if(num == 0) {
            break;
        }
    }
#endif

// no enough memory, Not recommended for use
#if 0
    // EPD_4IN2_V2_Init();
    // EPD_4IN2_V2_Clear();
    EPD_4IN2_V2_Init_4Gray();
    printf("show Gray------------------------\r\n");
    free(BlackImage);
    BlackImage = NULL;
    Imagesize = ((EPD_4IN2_V2_WIDTH % 8 == 0)? (EPD_4IN2_V2_WIDTH / 4 ): (EPD_4IN2_V2_WIDTH / 4 + 1)) * EPD_4IN2_V2_HEIGHT;
    if((BlackImage = (UBYTE *)malloc(Imagesize)) == NULL) {
        printf("Failed to apply for black memory...\r\n");
        while (1);
    }
    Paint_NewImage(BlackImage, EPD_4IN2_V2_WIDTH, EPD_4IN2_V2_HEIGHT, 0, WHITE);
    Paint_SetScale(4);
    Paint_Clear(WHITE);

    Paint_DrawPoint(10, 80, BLACK, DOT_PIXEL_1X1, DOT_STYLE_DFT);
    Paint_DrawPoint(10, 90, BLACK, DOT_PIXEL_2X2, DOT_STYLE_DFT);
    Paint_DrawPoint(10, 100, BLACK, DOT_PIXEL_3X3, DOT_STYLE_DFT);
    Paint_DrawLine(20, 70, 70, 120, BLACK, DOT_PIXEL_1X1, LINE_STYLE_SOLID);
    Paint_DrawLine(70, 70, 20, 120, BLACK, DOT_PIXEL_1X1, LINE_STYLE_SOLID);
    Paint_DrawRectangle(20, 70, 70, 120, BLACK, DOT_PIXEL_1X1, DRAW_FILL_EMPTY);
    Paint_DrawRectangle(80, 70, 130, 120, BLACK, DOT_PIXEL_1X1, DRAW_FILL_FULL);
    Paint_DrawCircle(45, 95, 20, BLACK, DOT_PIXEL_1X1, DRAW_FILL_EMPTY);
    Paint_DrawCircle(105, 95, 20, WHITE, DOT_PIXEL_1X1, DRAW_FILL_FULL);
    Paint_DrawLine(85, 95, 125, 95, BLACK, DOT_PIXEL_1X1, LINE_STYLE_DOTTED);
    Paint_DrawLine(105, 75, 105, 115, BLACK, DOT_PIXEL_1X1, LINE_STYLE_DOTTED);
    Paint_DrawString_EN(10, 0, "waveshare", &Font16, BLACK, WHITE);
    Paint_DrawString_EN(10, 20, "hello world", &Font12, WHITE, BLACK);
    Paint_DrawNum(10, 33, 123456789, &Font12, BLACK, WHITE);
    Paint_DrawNum(10, 50, 987654321, &Font16, WHITE, BLACK);
    Paint_DrawString_CN(140, 0, "你好abc", &Font12CN, GRAY1, GRAY4);
    Paint_DrawString_CN(140, 40, "你好abc", &Font12CN, GRAY2, GRAY3);
    Paint_DrawString_CN(140, 80, "你好abc", &Font12CN, GRAY3, GRAY2);
    Paint_DrawString_CN(140, 120, "你好abc", &Font12CN, GRAY4, GRAY1);

    Paint_DrawString_CN(220, 0, "微雪电子", &Font24CN, GRAY1, GRAY4);
    Paint_DrawString_CN(220, 40, "微雪电子", &Font24CN, GRAY2, GRAY3);
    Paint_DrawString_CN(220, 80, "微雪电子", &Font24CN, GRAY3, GRAY2);
    Paint_DrawString_CN(220, 120, "微雪电子", &Font24CN, GRAY4, GRAY1);

    EPD_4IN2_V2_Display_4Gray(BlackImage);
    DEV_Delay_ms(2000);

#endif
    EPD_4IN2_V2_Init();
    EPD_4IN2_V2_Clear();
    printf("Goto Sleep...\r\n");
    EPD_4IN2_V2_Sleep();
    free(BlackImage);
    BlackImage = NULL;
}

/* The main loop -------------------------------------------------------------*/
void loop()
{
  // 主循环
}
