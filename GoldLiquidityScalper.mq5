//+------------------------------------------------------------------+
//|                                       GoldLiquidityScalper.mq5    |
//|   اکسپرت اسکالپ طلا بر اساس شناسایی نقدینگی (Liquidity Sweep)      |
//|   نسخه اصلاح‌شده با پیشنهادات                                     |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.01"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//============================================================
// ENUM ها
//============================================================
enum ENUM_TRAIL_MODE
  {
   TRAIL_STEP = 0,      // تریلینگ پله‌ای (Step-based)
   TRAIL_CONTINUOUS = 1 // تریلینگ پیوسته (هر تیک)
  };

enum ENUM_REPLACE_MODE
  {
   REPLACE_OFF = 0,         // غیرفعال - چند پوزیشن مستقل
   REPLACE_LOSING_ONLY = 1  // فقط جایگزینی پوزیشن ضررده با سیگنال قوی‌تر
  };

//============================================================
// ورودی‌های اکسپرت (Inputs)
//============================================================
input group "=== تنظیمات عمومی ==="
input ulong    InpMagicNumber        = 990011;     // شناسه یکتای اکسپرت (Magic Number)
input ENUM_TIMEFRAMES InpTimeframe   = PERIOD_M1;  // تایم فریم کاری
input int       InpMaxSpreadPoints   = 350;        // حداکثر اسپرد قابل قبول (پوینت)

input group "=== حجم و حد ضرر/سود ==="
input double    InpLotSize           = 0.10;       // حجم معامله (لات)
input double    InpStopLossUSD       = 5.0;        // حداکثر حد ضرر (دلار) - سقف محدودکننده
input double    InpTakeProfitUSD     = 0.0;        // حد سود ثابت (دلار) - 0 یعنی غیرفعال (فقط تریلینگ)

input group "=== سیستم تریلینگ استاپ ==="
input bool      InpUseTrailing       = true;       // فعال‌سازی تریلینگ استاپ
input double    InpTrailStartUSD     = 3.0;        // شروع تریلینگ بعد از این مقدار سود (دلار)
input double    InpTrailStepUSD      = 1.0;        // فاصله هر گام تریلینگ (دلار)
input double    InpTrailLockUSD      = 1.0;        // مقدار سود قفل‌شده در هر گام (دلار)

input group "=== مدیریت ریسک و سرمایه ==="
input double    InpMaxDrawdownPercent = 50.0;      // حداکثر افت سرمایه از اوج (درصد) - توقف کامل اکسپرت
input int       InpMaxConsecutiveLosses = 4;       // حداکثر ضررهای متوالی قبل از توقف موقت
input int       InpPauseAfterLossesMin = 60;        // مکث (دقیقه) بعد از رسیدن به سقف ضرر متوالی
input double    InpRiskPercentPerTrade = 0.0;      // ریسک به درصد بالانس برای هر معامله (0=غیرفعال،از لات ثابت استفاده شود)

input group "=== مدیریت چند پوزیشن ==="
input int       InpMaxPositions      = 1;          // حداکثر تعداد پوزیشن همزمان
input bool      InpAllowReplace      = false;       // اجازه جایگزینی پوزیشن ضررده با سیگنال قوی‌تر

input group "=== تنظیمات تشخیص Liquidity ==="
input int       InpSwingLookback     = 30;         // تعداد کندل برای جستجوی سطوح Equal High/Low
input int       InpEqualLevelTolerancePoints = 40; // تلورانس برابر بودن سطوح (پوینت)
input int       InpMinSwingBars      = 3;          // حداقل فاصله بین دو سقف/کف برای معتبر بودن
input double    InpSweepMinPoints    = 30;         // حداقل میزان نفوذ قیمت از سطح برای Sweep معتبر (پوینت)
input int       InpRejectionMaxBars  = 2;          // حداکثر تعداد کندل برای تایید برگشت بعد از Sweep
input double    InpMinBodyRatio      = 0.35;       // حداقل نسبت بدنه به کل کندل برگشتی (تایید قدرت کندل)
input double    InpMinSignalStrength = 15.0;       // حداقل قدرت سیگنال برای ورود

input group "=== لاگ ==="
input bool      InpVerboseLog        = false;      // لاگ کامل (شامل جزئیات بررسی هر تیک)

//============================================================
// متغیرهای سراسری
//============================================================
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;
CAccountInfo   accInfo;

string   g_symbol;
double   g_point;
int      g_digits;
double   g_tickValue;
double   g_tickSize;

double   g_initialBalance   = 0.0;
double   g_equityPeak       = 0.0;
bool     g_tradingHalted    = false;
string   g_haltReason       = "";

int      g_consecutiveLosses = 0;
datetime g_pauseUntil        = 0;

// برای جلوگیری از لاگ تکراری
string   g_lastScanLogMsg    = "";
datetime g_lastScanLogTime   = 0;
string   g_lastTrailLogMsg[];   // به ازای هر تیکت آخرین پیام تریلینگ
ulong    g_lastTrailTicket[];

// تیکت‌هایی که به دستور خود اکسپرت (Replace) بسته شده‌اند، همراه با دلیل بستن
ulong    g_manualCloseTicket[];
string   g_manualCloseReason[];

// کنترل کندل جدید
datetime g_lastBarTime = 0;

// ساختار اطلاعات سطح نقدینگی شناسایی‌شده
struct LiquidityLevel
  {
   double   price;
   datetime time;
   int      touchCount;
   bool     isHigh; // true = سطح بالا (Equal Highs) ، false = سطح پایین (Equal Lows)
  };

// ساختار نتیجه سیگنال
struct SignalResult
  {
   bool     valid;
   bool     isBuy;
   double   entryPrice;
   double   slPrice;
   double   sweepLevel;
   double   strength;   // امتیاز قدرت سیگنال جهت مقایسه در حالت Replace
   string   description;
  };

//============================================================
// توابع لاگ (با جلوگیری از تکرار)
//============================================================
void LogInfo(string msg)
  {
   Print("[INFO] ", msg);
  }

void LogTrade(string msg)
  {
   Print("[TRADE] ", msg);
  }

void LogRisk(string msg)
  {
   Print("[RISK] ", msg);
  }

void LogTrail(string msg)
  {
   Print("[TRAIL] ", msg);
  }

// لاگ اسکن بازار - فقط وقتی پیام تغییر کرده یا بیش از N ثانیه گذشته باشه چاپ می‌شه
void LogScan(string msg)
  {
   if(!InpVerboseLog)
      return;
   if(msg == g_lastScanLogMsg && (TimeCurrent() - g_lastScanLogTime) < 30)
      return;
   g_lastScanLogMsg  = msg;
   g_lastScanLogTime = TimeCurrent();
   Print("[SCAN] ", msg);
  }

// جلوگیری از لاگ تکراری تریلینگ برای یک تیکت خاص
bool ShouldLogTrail(ulong ticket, string msg)
  {
   int sz = ArraySize(g_lastTrailTicket);
   for(int i = 0; i < sz; i++)
     {
      if(g_lastTrailTicket[i] == ticket)
        {
         if(g_lastTrailLogMsg[i] == msg)
            return false;
         g_lastTrailLogMsg[i] = msg;
         return true;
        }
     }
   ArrayResize(g_lastTrailTicket, sz + 1);
   ArrayResize(g_lastTrailLogMsg, sz + 1);
   g_lastTrailTicket[sz] = ticket;
   g_lastTrailLogMsg[sz] = msg;
   return true;
  }

void ClearTrailLogForTicket(ulong ticket)
  {
   int sz = ArraySize(g_lastTrailTicket);
   for(int i = 0; i < sz; i++)
     {
      if(g_lastTrailTicket[i] == ticket)
        {
         ArrayRemove(g_lastTrailTicket, i, 1);
         ArrayRemove(g_lastTrailLogMsg, i, 1);
         return;
        }
     }
  }

//============================================================
// مدیریت ریسک و سرمایه
//============================================================

// بررسی افت سرمایه کلی نسبت به اوج سرمایه (Equity Peak)
bool CheckGlobalDrawdown()
  {
   double equity = accInfo.Equity();
   if(equity > g_equityPeak)
      g_equityPeak = equity;

   double ddFromPeak = 0.0;
   if(g_equityPeak > 0.0)
      ddFromPeak = (g_equityPeak - equity) / g_equityPeak * 100.0;

   if(ddFromPeak >= InpMaxDrawdownPercent)
     {
      if(!g_tradingHalted)
        {
         g_tradingHalted = true;
         g_haltReason = StringFormat("افت سرمایه از اوج %.2f%% به سقف %.2f%% رسید", ddFromPeak, InpMaxDrawdownPercent);
         LogRisk("توقف کامل اکسپرت - " + g_haltReason);
        }
      return true;
     }
   return false;
  }

// بررسی تعداد ضررهای متوالی - در صورت رسیدن به سقف، یک مکث موقت اعمال می‌شود (نه توقف کامل)
bool IsInLossPause()
  {
   if(g_pauseUntil > 0 && TimeCurrent() < g_pauseUntil)
      return true;
   if(g_pauseUntil > 0 && TimeCurrent() >= g_pauseUntil)
     {
      LogRisk(StringFormat("پایان مکث موقت - اکسپرت دوباره فعال شد. زمان: %s", TimeToString(TimeCurrent())));
      g_pauseUntil = 0;
      g_consecutiveLosses = 0;
     }
   return false;
  }

// این تابع باید بعد از بسته شدن هر پوزیشن (با چک تاریخچه) فراخوانی شود
void RegisterTradeResult(double profitUSD)
  {
   if(profitUSD < 0.0)
     {
      g_consecutiveLosses++;
      LogRisk(StringFormat("معامله بازنده ثبت شد. سود/ضرر: %.2f$ | ضررهای متوالی: %d/%d",
                            profitUSD, g_consecutiveLosses, InpMaxConsecutiveLosses));

      if(g_consecutiveLosses >= InpMaxConsecutiveLosses && InpMaxConsecutiveLosses > 0)
        {
         g_pauseUntil = TimeCurrent() + InpPauseAfterLossesMin * 60;
         LogRisk(StringFormat("سقف ضررهای متوالی (%d) رسید - مکث موقت تا %s",
                               InpMaxConsecutiveLosses, TimeToString(g_pauseUntil)));
        }
     }
   else
     {
      if(g_consecutiveLosses > 0)
         LogRisk(StringFormat("معامله برنده - شمارنده ضررهای متوالی صفر شد (قبلی: %d)", g_consecutiveLosses));
      g_consecutiveLosses = 0;
     }
  }

// محاسبه حجم معامله بر اساس ریسک درصدی (اختیاری) یا حجم ثابت ورودی
double CalculateLotSize(double slDistancePoints)
  {
   if(InpRiskPercentPerTrade <= 0.0 || slDistancePoints <= 0)
      return NormalizeVolume(InpLotSize);

   double balance   = accInfo.Balance();
   double riskUSD   = balance * (InpRiskPercentPerTrade / 100.0);
   double tickValue = g_tickValue;
   double tickSize  = g_tickSize;

   if(tickValue <= 0 || tickSize <= 0)
      return NormalizeVolume(InpLotSize);

   double valuePerPoint = (tickValue / tickSize) * g_point;
   double slCostPerLot  = slDistancePoints * valuePerPoint;
   if(slCostPerLot <= 0)
      return NormalizeVolume(InpLotSize);

   double lots = riskUSD / slCostPerLot;
   return NormalizeVolume(lots);
  }

double NormalizeVolume(double vol)
  {
   double minVol  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxVol  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double stepVol = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   if(stepVol <= 0) stepVol = 0.01;

   double steps = MathRound(vol / stepVol);
   double result = steps * stepVol;

   if(result < minVol) result = minVol;
   if(result > maxVol) result = maxVol;

   return NormalizeDouble(result, 2);
  }

// تبدیل مقدار دلاری به فاصله قیمتی (پوینت) برای حجم معین
double USDToPoints(double usd, double lots)
  {
   if(g_tickValue <= 0 || g_tickSize <= 0 || lots <= 0)
      return 0;
   double valuePerPointPerLot = (g_tickValue / g_tickSize) * g_point;
   if(valuePerPointPerLot <= 0)
      return 0;
   return usd / (valuePerPointPerLot * lots);
  }

// تبدیل فاصله قیمتی (پوینت) به مقدار دلاری برای حجم معین
double PointsToUSD(double points, double lots)
  {
   if(g_tickValue <= 0 || g_tickSize <= 0)
      return 0;
   double valuePerPointPerLot = (g_tickValue / g_tickSize) * g_point;
   return points * valuePerPointPerLot * lots;
  }

//============================================================
// تشخیص سطوح Liquidity (Equal Highs / Equal Lows)
//============================================================

// یافتن سقف‌های محلی (Swing High) در بازه lookback
int FindSwingHighs(int lookback, double &prices[], datetime &times[])
  {
   int count = 0;
   ArrayResize(prices, 0);
   ArrayResize(times, 0);

   for(int i = InpMinSwingBars; i < lookback - InpMinSwingBars; i++)
     {
      double high = iHigh(g_symbol, InpTimeframe, i);
      bool isSwing = true;
      for(int j = 1; j <= InpMinSwingBars; j++)
        {
         if(iHigh(g_symbol, InpTimeframe, i - j) > high || iHigh(g_symbol, InpTimeframe, i + j) > high)
           {
            isSwing = false;
            break;
           }
        }
      if(isSwing)
        {
         ArrayResize(prices, count + 1);
         ArrayResize(times, count + 1);
         prices[count] = high;
         times[count]  = iTime(g_symbol, InpTimeframe, i);
         count++;
        }
     }
   return count;
  }

// یافتن کف‌های محلی (Swing Low) در بازه lookback
int FindSwingLows(int lookback, double &prices[], datetime &times[])
  {
   int count = 0;
   ArrayResize(prices, 0);
   ArrayResize(times, 0);

   for(int i = InpMinSwingBars; i < lookback - InpMinSwingBars; i++)
     {
      double low = iLow(g_symbol, InpTimeframe, i);
      bool isSwing = true;
      for(int j = 1; j <= InpMinSwingBars; j++)
        {
         if(iLow(g_symbol, InpTimeframe, i - j) < low || iLow(g_symbol, InpTimeframe, i + j) < low)
           {
            isSwing = false;
            break;
           }
        }
      if(isSwing)
        {
         ArrayResize(prices, count + 1);
         ArrayResize(times, count + 1);
         prices[count] = low;
         times[count]  = iTime(g_symbol, InpTimeframe, i);
         count++;
        }
     }
   return count;
  }

// گروه‌بندی سقف‌های نزدیک به هم به عنوان "سطح نقدینگی بالا" (Equal Highs)
int BuildEqualHighLevels(LiquidityLevel &levels[])
  {
   double prices[];
   datetime times[];
   int n = FindSwingHighs(InpSwingLookback, prices, times);
   int levelCount = 0;
   ArrayResize(levels, 0);

   double tolerance = InpEqualLevelTolerancePoints * g_point;

   for(int i = 0; i < n; i++)
     {
      bool merged = false;
      for(int k = 0; k < levelCount; k++)
        {
         if(MathAbs(levels[k].price - prices[i]) <= tolerance)
           {
            // به‌روزرسانی سطح موجود - میانگین‌گیری ساده و افزایش شمارنده تماس
            levels[k].price = (levels[k].price * levels[k].touchCount + prices[i]) / (levels[k].touchCount + 1);
            levels[k].touchCount++;
            if(times[i] > levels[k].time)
               levels[k].time = times[i];
            merged = true;
            break;
           }
        }
      if(!merged)
        {
         ArrayResize(levels, levelCount + 1);
         levels[levelCount].price      = prices[i];
         levels[levelCount].time       = times[i];
         levels[levelCount].touchCount = 1;
         levels[levelCount].isHigh     = true;
         levelCount++;
        }
     }
   return levelCount;
  }

// گروه‌بندی کف‌های نزدیک به هم به عنوان "سطح نقدینگی پایین" (Equal Lows)
int BuildEqualLowLevels(LiquidityLevel &levels[])
  {
   double prices[];
   datetime times[];
   int n = FindSwingLows(InpSwingLookback, prices, times);
   int levelCount = 0;
   ArrayResize(levels, 0);

   double tolerance = InpEqualLevelTolerancePoints * g_point;

   for(int i = 0; i < n; i++)
     {
      bool merged = false;
      for(int k = 0; k < levelCount; k++)
        {
         if(MathAbs(levels[k].price - prices[i]) <= tolerance)
           {
            levels[k].price = (levels[k].price * levels[k].touchCount + prices[i]) / (levels[k].touchCount + 1);
            levels[k].touchCount++;
            if(times[i] > levels[k].time)
               levels[k].time = times[i];
            merged = true;
            break;
           }
        }
      if(!merged)
        {
         ArrayResize(levels, levelCount + 1);
         levels[levelCount].price      = prices[i];
         levels[levelCount].time       = times[i];
         levels[levelCount].touchCount = 1;
         levels[levelCount].isHigh     = false;
         levelCount++;
        }
     }
   return levelCount;
  }

// محاسبه نسبت بدنه کندل به کل رنج کندل (برای تایید قدرت کندل برگشتی)
double CandleBodyRatio(int shift)
  {
   double open  = iOpen(g_symbol, InpTimeframe, shift);
   double close = iClose(g_symbol, InpTimeframe, shift);
   double high  = iHigh(g_symbol, InpTimeframe, shift);
   double low   = iLow(g_symbol, InpTimeframe, shift);
   double range = high - low;
   if(range <= 0)
      return 0;
   return MathAbs(close - open) / range;
  }

//============================================================
// موتور اصلی تشخیص سیگنال (Liquidity Sweep + Rejection)
// (اصلاح‌شده: کندل Sweep نیز بررسی می‌شود، کندل باز استفاده نمی‌شود، توالی زمانی رعایت شده)
//============================================================
SignalResult DetectLiquiditySweepSignal()
  {
   SignalResult result;
   result.valid = false;
   result.isBuy = false;
   result.entryPrice = 0;
   result.slPrice = 0;
   result.sweepLevel = 0;
   result.strength = 0;
   result.description = "";

   LiquidityLevel highLevels[];
   LiquidityLevel lowLevels[];
   int highCount = BuildEqualHighLevels(highLevels);
   int lowCount  = BuildEqualLowLevels(lowLevels);

   double sweepMin = InpSweepMinPoints * g_point;

   // -------- بررسی Sweep سطح بالا -> به دنبال سیگنال SELL --------
   for(int L = 0; L < highCount; L++)
     {
      if(highLevels[L].touchCount < 2)
         continue;

      for(int b = 1; b <= InpRejectionMaxBars; b++)
        {
         // اطمینان از اینکه کندل Sweep بعد از آخرین لمس سطح تشکیل شده است
         if(iTime(g_symbol, InpTimeframe, b) <= highLevels[L].time)
            continue;

         double barHigh  = iHigh(g_symbol, InpTimeframe, b);
         double barClose = iClose(g_symbol, InpTimeframe, b);

         bool sweepHappened = (barHigh >= highLevels[L].price + sweepMin);
         bool closedBack     = (barClose < highLevels[L].price);

         if(sweepHappened && closedBack)
           {
            // کندل تأیید می‌تواند خود کندل Sweep (b) یا کندل‌های بعدی (b-1 تا 1) باشد، کندل 0 (باز) استفاده نمی‌شود
            for(int c = b; c >= 1; c--)
              {
               double bodyRatio = CandleBodyRatio(c);
               double cClose = iClose(g_symbol, InpTimeframe, c);
               double cOpen  = iOpen(g_symbol, InpTimeframe, c);
               bool bearish  = cClose < cOpen;

               if(bearish && bodyRatio >= InpMinBodyRatio && cClose < highLevels[L].price)
                 {
                  result.valid       = true;
                  result.isBuy       = false;
                  result.entryPrice  = SymbolInfoDouble(g_symbol, SYMBOL_BID);
                  result.sweepLevel  = highLevels[L].price;
                  result.slPrice     = barHigh + (5 * g_point); // کمی بالاتر از قله Sweep
                  result.strength    = highLevels[L].touchCount * 10.0 + bodyRatio * 10.0
                                        + (sweepMin > 0 ? (barHigh - highLevels[L].price) / sweepMin : 0);
                  result.description = StringFormat(
                     "SELL سیگنال: Sweep سطح %.2f (لمس=%d بار) | نفوذ=%.1f پوینت | برگشت با کندل نزولی (بدنه=%.0f%%)",
                     highLevels[L].price, highLevels[L].touchCount,
                     (barHigh - highLevels[L].price) / g_point, bodyRatio * 100.0);
                  return result;
                 }
              }
           }
        }
     }

   // -------- بررسی Sweep سطح پایین -> به دنبال سیگنال BUY --------
   for(int L = 0; L < lowCount; L++)
     {
      if(lowLevels[L].touchCount < 2)
         continue;

      for(int b = 1; b <= InpRejectionMaxBars; b++)
        {
         if(iTime(g_symbol, InpTimeframe, b) <= lowLevels[L].time)
            continue;

         double barLow   = iLow(g_symbol, InpTimeframe, b);
         double barClose = iClose(g_symbol, InpTimeframe, b);

         bool sweepHappened = (barLow <= lowLevels[L].price - sweepMin);
         bool closedBack     = (barClose > lowLevels[L].price);

         if(sweepHappened && closedBack)
           {
            for(int c = b; c >= 1; c--)
              {
               double bodyRatio = CandleBodyRatio(c);
               double cClose = iClose(g_symbol, InpTimeframe, c);
               double cOpen  = iOpen(g_symbol, InpTimeframe, c);
               bool bullish  = cClose > cOpen;

               if(bullish && bodyRatio >= InpMinBodyRatio && cClose > lowLevels[L].price)
                 {
                  result.valid       = true;
                  result.isBuy       = true;
                  result.entryPrice  = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
                  result.sweepLevel  = lowLevels[L].price;
                  result.slPrice     = barLow - (5 * g_point);
                  result.strength    = lowLevels[L].touchCount * 10.0 + bodyRatio * 10.0
                                        + (sweepMin > 0 ? (lowLevels[L].price - barLow) / sweepMin : 0);
                  result.description = StringFormat(
                     "BUY سیگنال: Sweep سطح %.2f (لمس=%d بار) | نفوذ=%.1f پوینت | برگشت با کندل صعودی (بدنه=%.0f%%)",
                     lowLevels[L].price, lowLevels[L].touchCount,
                     (lowLevels[L].price - barLow) / g_point, bodyRatio * 100.0);
                  return result;
                 }
              }
           }
        }
     }

   return result;
  }

//============================================================
// توابع کمکی پوزیشن
//============================================================

// شمارش پوزیشن‌های باز متعلق به این اکسپرت (با همین Magic Number)
int CountMyPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Symbol() == g_symbol && posInfo.Magic() == InpMagicNumber)
            count++;
        }
     }
   return count;
  }

// یافتن ضررده‌ترین پوزیشن باز فعلی (برای منطق Replace) - بازمی‌گرداند آیا یافت شد یا نه
bool FindWorstLosingPosition(ulong &ticket, double &profitUSD)
  {
   bool found = false;
   double worst = 0;
   ulong worstTicket = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Symbol() == g_symbol && posInfo.Magic() == InpMagicNumber)
           {
            double p = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();
            if(p < 0 && (!found || p < worst))
              {
               worst = p;
               worstTicket = posInfo.Ticket();
               found = true;
              }
           }
        }
     }
   if(found)
     {
      ticket    = worstTicket;
      profitUSD = worst;
     }
   return found;
  }

// باز کردن پوزیشن جدید بر اساس سیگنال
bool OpenPosition(const SignalResult &sig)
  {
   // بررسی دوباره اسپرد در لحظه ارسال سفارش
   double spreadPoints = (SymbolInfoDouble(g_symbol, SYMBOL_ASK) - SymbolInfoDouble(g_symbol, SYMBOL_BID)) / g_point;
   if(spreadPoints > InpMaxSpreadPoints)
     {
      LogTrade(StringFormat("رد ورود - اسپرد بالا (%.1f پوینت) در لحظه ارسال سفارش", spreadPoints));
      return false;
     }

   double slDistancePoints = MathAbs(sig.entryPrice - sig.slPrice) / g_point;

   double lots = CalculateLotSize(slDistancePoints);
   double maxAllowedPoints = USDToPoints(InpStopLossUSD, lots);

   double finalSlPrice = sig.slPrice;
   bool   cappedByUSD = false;

   if(maxAllowedPoints > 0 && slDistancePoints > maxAllowedPoints)
     {
      cappedByUSD = true;
      if(sig.isBuy)
         finalSlPrice = sig.entryPrice - maxAllowedPoints * g_point;
      else
         finalSlPrice = sig.entryPrice + maxAllowedPoints * g_point;
      slDistancePoints = maxAllowedPoints;
     }

   double tpPrice = 0.0;
   if(InpTakeProfitUSD > 0.0)
     {
      double tpPoints = USDToPoints(InpTakeProfitUSD, lots);
      if(sig.isBuy)
         tpPrice = sig.entryPrice + tpPoints * g_point;
      else
         tpPrice = sig.entryPrice - tpPoints * g_point;
     }

   finalSlPrice = NormalizeDouble(finalSlPrice, g_digits);
   if(tpPrice > 0)
      tpPrice = NormalizeDouble(tpPrice, g_digits);

   double estimatedRiskUSD = PointsToUSD(slDistancePoints, lots);

   bool sent;
   string comment = StringFormat("LiqSweep_%s", sig.isBuy ? "BUY" : "SELL");

   if(sig.isBuy)
      sent = trade.Buy(lots, g_symbol, 0.0, finalSlPrice, tpPrice, comment);
   else
      sent = trade.Sell(lots, g_symbol, 0.0, finalSlPrice, tpPrice, comment);

   if(sent)
     {
      LogTrade(StringFormat(
         "پوزیشن باز شد | %s | حجم=%.2f | قیمت ورود≈%.2f | SL=%.2f (%s) | TP=%s | ریسک تخمینی=%.2f$ | %s",
         sig.isBuy ? "BUY" : "SELL", lots, sig.entryPrice, finalSlPrice,
         cappedByUSD ? "محدود شده با سقف دلاری" : "بر اساس ساختار قیمت",
         (tpPrice > 0 ? DoubleToString(tpPrice, g_digits) : "ندارد (فقط تریلینگ)"),
         estimatedRiskUSD, sig.description));
      return true;
     }
   else
     {
      LogTrade(StringFormat("خطا در ارسال سفارش %s | کد خطا=%d | %s",
                             sig.isBuy ? "BUY" : "SELL", GetLastError(), sig.description));
      return false;
     }
  }

// بستن یک پوزیشن مشخص با ذکر دلیل در لاگ
bool CloseSpecificPosition(ulong ticket, string reason)
  {
   if(!posInfo.SelectByTicket(ticket))
      return false;

   double profit = posInfo.Profit() + posInfo.Swap() + posInfo.Commission();

   int sz = ArraySize(g_manualCloseTicket);
   ArrayResize(g_manualCloseTicket, sz + 1);
   ArrayResize(g_manualCloseReason, sz + 1);
   g_manualCloseTicket[sz] = ticket;
   g_manualCloseReason[sz] = reason;

   bool closed = trade.PositionClose(ticket);
   if(closed)
     {
      LogTrade(StringFormat("درخواست بسته‌شدن پوزیشن #%I64u ارسال شد | سود/ضرر≈%.2f$ | دلیل: %s", ticket, profit, reason));
     }
   else
     {
      for(int i = ArraySize(g_manualCloseTicket) - 1; i >= 0; i--)
        {
         if(g_manualCloseTicket[i] == ticket)
           {
            ArrayRemove(g_manualCloseTicket, i, 1);
            ArrayRemove(g_manualCloseReason, i, 1);
            break;
           }
        }
      LogTrade(StringFormat("خطا در بستن پوزیشن #%I64u | کد خطا=%d", ticket, GetLastError()));
     }
   return closed;
  }

//============================================================
// سیستم تریلینگ استاپ (بر اساس سود دلاری)
// (اصلاح‌شده: استفاده از SYMBOL_TRADE_STOPS_LEVEL برای تلورانس حرکت SL)
//============================================================
void ManageTrailingStop()
  {
   if(!InpUseTrailing)
      return;

   long stopsLevel = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = stopsLevel * g_point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != g_symbol || posInfo.Magic() != InpMagicNumber)
         continue;

      ulong  ticket   = posInfo.Ticket();
      double openPrice = posInfo.PriceOpen();
      double currentSL = posInfo.StopLoss();
      bool   isBuy     = (posInfo.PositionType() == POSITION_TYPE_BUY);
      double volume    = posInfo.Volume();

      double currentPrice = isBuy ? SymbolInfoDouble(g_symbol, SYMBOL_BID)
                                    : SymbolInfoDouble(g_symbol, SYMBOL_ASK);

      double profitPoints = isBuy ? (currentPrice - openPrice) / g_point
                                    : (openPrice - currentPrice) / g_point;
      double profitUSD = PointsToUSD(profitPoints, volume);

      if(profitUSD < InpTrailStartUSD)
         continue;

      double extraProfit = profitUSD - InpTrailStartUSD;
      int    stepsPassed  = (InpTrailStepUSD > 0) ? (int)MathFloor(extraProfit / InpTrailStepUSD) : 0;

      double lockUSD = InpTrailLockUSD * (1 + stepsPassed);
      if(lockUSD >= profitUSD)
         lockUSD = profitUSD - (InpTrailStepUSD * 0.5);
      if(lockUSD < 0)
         lockUSD = 0;

      double lockPoints = USDToPoints(lockUSD, volume);
      double newSL = isBuy ? (openPrice + lockPoints * g_point)
                            : (openPrice - lockPoints * g_point);
      newSL = NormalizeDouble(newSL, g_digits);

      // بهبود فقط در صورتی که فاصله از SL فعلی بیشتر از حداقل فاصله مجاز بروکر باشد
      bool improves = false;
      if(currentSL == 0.0)
         improves = true;
      else if(isBuy  && newSL > currentSL + minDist)
         improves = true;
      else if(!isBuy && newSL < currentSL - minDist)
         improves = true;

      if(improves)
        {
         double tp = posInfo.TakeProfit();
         bool modified = trade.PositionModify(ticket, newSL, tp);
         if(modified)
           {
            string msg = StringFormat("ticket=%I64u SL_new=%.2f lock=%.2f$ profit=%.2f$ step=%d",
                                       ticket, newSL, lockUSD, profitUSD, stepsPassed);
            if(ShouldLogTrail(ticket, msg))
              {
               LogTrail(StringFormat(
                  "پوزیشن #%I64u (%s) | سود فعلی=%.2f$ | SL جدید=%.2f (سود قفل‌شده=%.2f$) | گام تریلینگ=%d",
                  ticket, isBuy ? "BUY" : "SELL", profitUSD, newSL, lockUSD, stepsPassed));
              }
           }
         else
           {
            LogTrail(StringFormat("خطا در تریلینگ پوزیشن #%I64u | کد خطا=%d", ticket, GetLastError()));
           }
        }
     }
  }

// بستن تمام پوزیشن‌های باز متعلق به این اکسپرت - برای حالت توقف کامل اضطراری
void CloseAllMyPositions(string reason)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Symbol() == g_symbol && posInfo.Magic() == InpMagicNumber)
           {
            CloseSpecificPosition(posInfo.Ticket(), reason);
           }
        }
     }
  }

//============================================================
// منطق اصلی تصمیم‌گیری ورود (ترکیب سیگنال + مدیریت پوزیشن‌ها)
//============================================================
void ProcessEntryLogic()
  {
   int openPositions = CountMyPositions();

   double spreadPoints = (SymbolInfoDouble(g_symbol, SYMBOL_ASK) - SymbolInfoDouble(g_symbol, SYMBOL_BID)) / g_point;
   if(spreadPoints > InpMaxSpreadPoints)
     {
      LogScan(StringFormat("رد بررسی: اسپرد بالا (%.1f پوینت > سقف %d)", spreadPoints, InpMaxSpreadPoints));
      return;
     }

   SignalResult sig = DetectLiquiditySweepSignal();

   if(!sig.valid)
     {
      LogScan(StringFormat("در حال بررسی بازار... پوزیشن‌های باز=%d/%d | سیگنالی یافت نشد",
                            openPositions, InpMaxPositions));
      return;
     }

   // فیلتر قدرت سیگنال
   if(sig.strength < InpMinSignalStrength)
     {
      LogScan(StringFormat("سیگنال شناسایی شد ولی قدرت کافی ندارد (%.1f < %.1f): %s",
                            sig.strength, InpMinSignalStrength, sig.description));
      return;
     }

   // ----- ظرفیت خالی داریم -> مستقیم باز کن -----
   if(openPositions < InpMaxPositions)
     {
      LogTrade("سیگنال شناسایی شد: " + sig.description);
      OpenPosition(sig);
      return;
     }

   // ----- ظرفیت پر است -----
   if(!InpAllowReplace)
     {
      LogScan(StringFormat("سیگنال یافت شد ولی ظرفیت پر است (%d/%d) و Replace غیرفعال است: %s",
                            openPositions, InpMaxPositions, sig.description));
      return;
     }

   // منطق Replace: فقط اگر پوزیشن ضررده داریم و سیگنال جدید قوی‌تر تشخیص داده شود
   ulong losingTicket;
   double losingProfit;
   if(FindWorstLosingPosition(losingTicket, losingProfit))
     {
      // از InpMinSignalStrength به عنوان آستانه استفاده می‌کنیم (پیشتر چک شده)
      LogTrade(StringFormat(
         "سیگنال جدید قوی شناسایی شد (قدرت=%.1f) در حالی که پوزیشن #%I64u در ضرر (%.2f$) است -> جایگزینی",
         sig.strength, losingTicket, losingProfit));
      if(CloseSpecificPosition(losingTicket, "جایگزینی با سیگنال قوی‌تر"))
        {
         if(!OpenPosition(sig))
            LogTrade("هشدار: پوزیشن قبلی بسته شد اما باز کردن پوزیشن جدید ناموفق بود!");
        }
     }
   else
     {
      LogScan("سیگنال یافت شد ولی همه پوزیشن‌های باز سودده هستند - جایگزینی انجام نمی‌شود");
     }
  }

//============================================================
// OnInit
//============================================================
int OnInit()
  {
   g_symbol = _Symbol;

   if(!symInfo.Name(g_symbol))
     {
      Print("[ERROR] خطا در بارگذاری اطلاعات نماد");
      return INIT_FAILED;
     }

   g_point     = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
   g_digits    = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   g_tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(g_symbol);

   g_initialBalance = accInfo.Balance();
   g_equityPeak      = accInfo.Equity();
   g_tradingHalted   = false;
   g_consecutiveLosses = 0;
   g_pauseUntil = 0;
   g_lastBarTime = 0;

   ArrayResize(g_lastTrailTicket, 0);
   ArrayResize(g_lastTrailLogMsg, 0);
   ArrayResize(g_manualCloseTicket, 0);
   ArrayResize(g_manualCloseReason, 0);

   LogInfo(StringFormat(
      "اکسپرت راه‌اندازی شد | نسخه 1.01 | نماد=%s | تایم‌فریم=%s | بالانس اولیه=%.2f$ | حداکثر افت مجاز از اوج=%.1f%% | حداکثر پوزیشن=%d | Replace=%s",
      g_symbol, EnumToString(InpTimeframe), g_initialBalance, InpMaxDrawdownPercent,
      InpMaxPositions, InpAllowReplace ? "فعال" : "غیرفعال"));

   return INIT_SUCCEEDED;
  }

//============================================================
// OnDeinit
//============================================================
void OnDeinit(const int reason)
  {
   LogInfo(StringFormat("اکسپرت متوقف شد | دلیل کد=%d", reason));
  }

//============================================================
// OnTick
//============================================================
void OnTick()
  {
   // ---- 1) چک سلامت سرمایه (در هر تیک) ----
   if(CheckGlobalDrawdown())
     {
      CloseAllMyPositions("توقف کامل اکسپرت به دلیل رسیدن به سقف افت سرمایه (" + g_haltReason + ")");
      return;
     }

   // ---- 2) تریلینگ استاپ (هر تیک) ----
   ManageTrailingStop();

   // ---- 3) چک مکث موقت ناشی از ضررهای متوالی ----
   if(IsInLossPause())
     {
      LogScan(StringFormat("اکسپرت در مکث موقت است تا %s (ضررهای متوالی به سقف رسید)",
                            TimeToString(g_pauseUntil)));
      return;
     }

   // ---- 4) منطق ورود فقط در آغاز کندل جدید ----
   datetime currentBarTime = iTime(g_symbol, InpTimeframe, 0);
   if(currentBarTime == g_lastBarTime)
      return;

   g_lastBarTime = currentBarTime;

   int bars = iBars(g_symbol, InpTimeframe);
   if(bars < InpSwingLookback + InpMinSwingBars * 2 + 5)
     {
      LogScan("داده کافی برای تحلیل وجود ندارد - منتظر کندل‌های بیشتر");
      return;
     }

   ProcessEntryLogic();
  }

//============================================================
// OnTradeTransaction - برای ثبت دقیق نتیجه معاملات بسته‌شده
//============================================================
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket))
      return;

   long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY)
      return;

   long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if((ulong)magic != InpMagicNumber)
      return;

   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(dealSymbol != g_symbol)
      return;

   double profit   = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double swap     = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double totalPL  = profit + swap + commission;

   ulong posTicket = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   string closeReason = "";
   bool wasManual = false;
   for(int i = ArraySize(g_manualCloseTicket) - 1; i >= 0; i--)
     {
      if(g_manualCloseTicket[i] == posTicket)
        {
         closeReason = g_manualCloseReason[i];
         wasManual = true;
         ArrayRemove(g_manualCloseTicket, i, 1);
         ArrayRemove(g_manualCloseReason, i, 1);
         break;
        }
     }

   if(wasManual)
      LogTrade(StringFormat("پوزیشن #%I64u بسته شد | سود/ضرر نهایی=%.2f$ | دلیل: %s", posTicket, totalPL, closeReason));
   else
      LogTrade(StringFormat("پوزیشن #%I64u توسط SL/TP یا بستن دستی در ترمینال بسته شد | سود/ضرر نهایی=%.2f$", posTicket, totalPL));

   RegisterTradeResult(totalPL);
   ClearTrailLogForTicket(posTicket);
  }