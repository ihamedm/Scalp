//+------------------------------------------------------------------+
//|                                           GoldenTrendTrailEA.mq5  |
//|                 ورود با کراس مووینگ اوریج و تریلینگ ATR          |
//+------------------------------------------------------------------+
#property copyright "Hamed Movasaqpoor"
#property link      "hamed.movasaqpoor@gmail.com"
#property version   "1.07"
#property strict
#include <Trade\Trade.mqh>

enum ENUM_ENTRY_SIGNAL_MODE
  {
   ENTRY_SIGNAL_CROSS_ONLY = 0,        // فقط کراس MA
   ENTRY_SIGNAL_MOMENTUM_ONLY = 1,     // فقط ایمپالس/بریک‌اوت
   ENTRY_SIGNAL_CROSS_OR_MOMENTUM = 2  // کراس یا ایمپالس/بریک‌اوت
  };

input group "=== تنظیمات کلی ==="
input int             MagicNumber          = 120032;   // شماره جادویی اکسپرت
input string          ExpectedSymbol       = "XAUUSD"; // برای مجاز بودن همه نمادها خالی بگذارید
input ENUM_TIMEFRAMES SignalTimeframe      = PERIOD_M1;
input int             MaxSpreadPoints      = 80;       // عدد صفر فیلتر اسپرد را غیرفعال می‌کند
input int             MaxOpenPositions     = 1;
input int             DeviationPoints      = 20;
input group "=== سیگنال ورود ==="
input int                FastMAPeriod          = 12;
input int                SlowMAPeriod          = 32;
input ENUM_MA_METHOD     MAMethod              = MODE_EMA;
input ENUM_APPLIED_PRICE MAPrice               = PRICE_CLOSE;
input double             NearCrossPoints       = 30.0; // وقتی فاصله MAها کمتر از این مقدار شود لاگ ثبت می‌شود
input ENUM_ENTRY_SIGNAL_MODE EntrySignalMode   = ENTRY_SIGNAL_CROSS_OR_MOMENTUM;
input bool               CloseOnOppositeSignal = false;
input bool               ReEntryInTrend        = false; // ورود مجدد در ادامه روند بعد از بسته شدن پوزیشن
input int                ReEntryMinBars        = 3;     // حداقل فاصله کندلی بین ورودها در حالت ورود مجدد

input group "=== سیگنال ایمپالس/بریک‌اوت ==="
input int    MomentumBreakoutLookback     = 6;    // شکست سقف/کف چند کندل قبل
input double MomentumMinBodyATR           = 0.45; // حداقل بدنه کندل سیگنال نسبت به ATR
input double MomentumMinRangeATR          = 0.70; // حداقل کل رنج کندل سیگنال نسبت به ATR
input double MomentumMaxWickPercent       = 35.0; // حداکثر شادو مخالف جهت، درصدی از کل کندل
input double MomentumBreakoutBufferPoints = 5.0;  // فاصله اضافه شکست سقف/کف بر حسب پوینت
input double MomentumMaxPriceFastATR      = 1.20; // اگر قیمت خیلی از MA سریع دور شده باشد ورود نکند
input double MomentumMinFastSlopePoints   = 2.0;  // حداقل شیب MA سریع روی کندل بسته‌شده

input group "=== فیلتر حداقل فاصله MA ==="
input bool   UseMinMADistanceFilter = false;  //UseMinMADistanceFilter فعال‌سازی فیلتر حداقل فاصله MAها
input double MinMADistanceATR      = 5.0;  //MinMADistanceATR حداقل فاصله MA بر حسب چند برابر ATR (مثلاً ۵ برابر)
input double MinMADistancePoints    = 80.0;  //MinMADistancePoints حداقل فاصله بین MA سریع و کند (پوینت)

input group "=== فیلتر ADX ==="
input bool   UseADXFilter           = false;
input int    ADXPeriod              = 14;
input double ADXThreshold           = 25.0;  //ADXThreshold حداقل ADX برای روند قوی

input group "=== فیلتر قیمت روی MA ==="
input bool   UsePriceAboveMAFilter  = false;  //UsePriceAboveMAFilter قیمت باید در سمت درست MAها باشد

input group "=== فیلتر RSI ==="
input bool   UseRSIFilter           = false; //UseRSIFilter فیلتر RSI (اختیاری، شاید خیلی محدودکننده شود)
input int    RSIPeriod              = 14;
input double RSIOverbought          = 70.0;  //RSIOverbought برای خرید بالای این عدد ورود ممنوع
input double RSIOversold            = 30.0;  //RSIOversold برای فروش زیر این عدد ورود ممنوع

input group "=== فیلتر تایم‌فریم بالاتر ==="
input bool   UseMultiTimeframeFilter = false; //UseMultiTimeframeFilter تایید تایم‌فریم بالاتر
input ENUM_TIMEFRAMES HigherTF      = PERIOD_M5;
input int    HigherTF_FastMAPeriod  = 12;
input int    HigherTF_SlowMAPeriod  = 32;
input ENUM_MA_METHOD HigherTF_MAMethod = MODE_EMA;
input ENUM_APPLIED_PRICE HigherTF_MAPrice = PRICE_CLOSE;

input group "=== فیلتر قدرت کندل ==="
input bool   UseCandleStrengthFilter = false;
input double MinCandleBodyATR   = 0.5;  //MinCandleBodyATR حداقل نسبت بدنه کندل به ATR
input double MinCandleTotalATR  = 0.8;  //MinCandleTotalATR حداقل نسبت کل اندازه کندل (High-Low) به ATR

input group "=== فیلتر حمایت/مقاومت ==="
input bool   UseSRProximityFilter      = false;   // UseSRProximityFilter فعال‌سازی فیلتر نزدیکی به حمایت/مقاومت
input double MinDistanceFromSRPoints  = 80.0;   // حداقل فاصله از سطح S/R بر حسب پوینت
input int    SRLookbackBars            = 40;     // SRLookbackBars تعداد کندل برای یافتن سطوح استاتیک
input bool   UseMAAsDynamicSR          = true;   // UseMAAsDynamicSR استفاده از MAهای فعلی به عنوان سطوح داینامیک

input group "=== تنظیمات ورود منعطف ==="
input bool   UseFlexibleEntryConfirmations = true; // اگر فعال باشد فقط تعداد مشخصی از تاییدیه‌های فعال لازم است
input int    MinEntryConfirmations        = 3;    // حداقل تعداد تاییدیه‌های فعال برای ورود

input group "=== پوزیشن ==="
input double LotSize          = 0.01;
input double StopLossPoints   = 0.0; // عدد صفر یعنی حد ضرر اولیه ثبت نشود
input bool   UseDisableInitialSL = false; // اگر فعال باشد هیچ SL اولیه‌ای ارسال نمی‌شود
input double TakeProfitPoints = 0.0; // عدد صفر یعنی حد سود اولیه ثبت نشود

input group "=== تریلینگ ساده و تهاجمی ==="
input bool   UseATRTrailing          = true;   // فعال‌سازی تریلینگ
input int    ATRPeriod               = 14;     // دوره ATR
input double TrailStartATR           = 0.4;    // شروع تریلینگ بعد از این مقدار سود (بر حسب ATR)
input double SLTrailATRMult          = 0.7;    // فاصله حد ضرر از قیمت (چند برابر ATR)
input double StaticTP_ATRFactor      = 1.8;    // ضریب ATR برای حد سود ثابت (۰ = بدون TP)
input bool   UpdateSLOnBarCloseOnly  = true;   // آپدیت SL فقط در بسته شدن کندل
input bool   UseBreakevenProtection  = true;   // انتقال SL به نقطه ورود بعد از سود مشخص
input double BreakevenATR            = 0.8;    // سود لازم برای Breakeven (بر حسب ATR)
input double BreakevenBufferPoints   = 10.0;   // بافر Breakeven (پوینت)


input group "=== لاگ تستر ==="
input bool   TesterVerboseLogs       = true;  // فقط در Strategy Tester لاگ‌های دقیق چاپ می‌کند
input int    TesterLogLevel          = 1;     // 1=خلاصه، 2=جزئیات مهم، 3=خیلی ریز
input group "=== دکمه‌های چارت ==="
input int ButtonX = 120; // فاصله پنل از سمت راست چارت
input int ButtonY = 28; // فاصله پنل از بالای چارت
CTrade trade;


const string EA_VERSION = "1.07";
const int NO_SIGNAL = -1;
const string BTN_START = "GTT_BtnStart";
const string BTN_STOP  = "GTT_BtnStop";
const string BTN_MANUAL_BUY  = "GTT_BtnManualBuy";
const string BTN_MANUAL_SELL = "GTT_BtnManualSell";
const string LBL_STATE = "GTT_LblState";
int      g_fastHandle       = INVALID_HANDLE;
int      g_slowHandle       = INVALID_HANDLE;
int      g_atrHandle        = INVALID_HANDLE;
bool     g_isActive         = false;
datetime g_lastSignalBarTime = 0;
datetime g_lastReEntryBarTime = 0;
datetime g_lastEntryBarTime   = 0;
int      g_lastEntryDirection = NO_SIGNAL;
datetime g_lastNearLogTime   = 0;
datetime g_lastEnvLogTime    = 0;
datetime g_lastTesterTrailLogTime = 0;
// ردیابی آخرین کندل آپدیت SL به ازای هر تیکت (برای UpdateSLOnBarCloseOnly)
datetime g_lastSLBarTime     = 0;

int      g_adxHandle        = INVALID_HANDLE;
int      g_rsiHandle        = INVALID_HANDLE;
int      g_higherFastMA     = INVALID_HANDLE;
int      g_higherSlowMA     = INVALID_HANDLE;
//+------------------------------------------------------------------+
//| مقداردهی اولیه اکسپرت                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(FastMAPeriod <= 0 || SlowMAPeriod <= 0 || FastMAPeriod == SlowMAPeriod)
     {
      Print("دوره‌های مووینگ اوریج نامعتبر هستند. دوره سریع و کند باید مثبت و متفاوت باشند.");
      return INIT_PARAMETERS_INCORRECT;
     }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   PrintFormat("GoldenTrendTrailEA نسخه %s بارگذاری شد.", EA_VERSION);

   g_fastHandle = iMA(_Symbol, SignalTimeframe, FastMAPeriod, 0, MAMethod, MAPrice);
   g_slowHandle = iMA(_Symbol, SignalTimeframe, SlowMAPeriod, 0, MAMethod, MAPrice);

   if(UseADXFilter)
     {
      g_adxHandle = iADX(_Symbol, SignalTimeframe, ADXPeriod);
      if(g_adxHandle == INVALID_HANDLE)
        {
         Print("خطا در ساخت هندل ADX");
         return INIT_FAILED;
        }
     }

   if(UseRSIFilter)
     {
      g_rsiHandle = iRSI(_Symbol, SignalTimeframe, RSIPeriod, PRICE_CLOSE);
      if(g_rsiHandle == INVALID_HANDLE)
        {
         Print("خطا در ساخت هندل RSI");
         return INIT_FAILED;
        }
     }

   if(UseMultiTimeframeFilter)
     {
      g_higherFastMA = iMA(_Symbol, HigherTF, HigherTF_FastMAPeriod, 0, HigherTF_MAMethod, HigherTF_MAPrice);
      g_higherSlowMA = iMA(_Symbol, HigherTF, HigherTF_SlowMAPeriod, 0, HigherTF_MAMethod, HigherTF_MAPrice);
      if(g_higherFastMA == INVALID_HANDLE || g_higherSlowMA == INVALID_HANDLE)
        {
         Print("خطا در ساخت هندل‌های MA تایم‌فریم بالاتر");
         return INIT_FAILED;
        }
     }


   if(g_fastHandle == INVALID_HANDLE || g_slowHandle == INVALID_HANDLE)
     {
      Print("خطا در ساخت هندل اندیکاتورهای مووینگ اوریج.");
      return INIT_FAILED;
     }
   g_atrHandle = iATR(_Symbol, SignalTimeframe, ATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("خطا در ساخت هندل اندیکاتور ATR.");
      return INIT_FAILED;
     }
   if(IsTester())
     {
      g_isActive = true;
      Print("حالت تستر: GoldenTrendTrailEA به‌صورت خودکار شروع شد.");
     }
   else
     {
      CreateControlButtons();
      g_isActive = false;
      Print("GoldenTrendTrailEA منتظر کلیک روی دکمه شروع معامله است.");
     }
   PrintFormat("سیگنال: %s | MA(%d/%d) در %s | نماد=%s | حداکثر پوزیشن=%d",
               EntrySignalModeText(), FastMAPeriod, SlowMAPeriod, EnumToString(SignalTimeframe), _Symbol, MaxOpenPositions);
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//| پایان کار اکسپرت                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_fastHandle != INVALID_HANDLE) IndicatorRelease(g_fastHandle);
   if(g_slowHandle != INVALID_HANDLE) IndicatorRelease(g_slowHandle);
   if(g_atrHandle  != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);
   if(g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if(g_higherFastMA != INVALID_HANDLE) IndicatorRelease(g_higherFastMA);
   if(g_higherSlowMA != INVALID_HANDLE) IndicatorRelease(g_higherSlowMA);
   ObjectDelete(0, BTN_START);
   ObjectDelete(0, BTN_STOP);
   ObjectDelete(0, BTN_MANUAL_BUY);
   ObjectDelete(0, BTN_MANUAL_SELL);
   ObjectDelete(0, LBL_STATE);
   Comment("");
  }
//+------------------------------------------------------------------+
//| پردازش هر تیک                                                     |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageOpenPositions();
   if(!g_isActive)
     {
      DrawStatus("متوقف");
      return;
     }
   DrawStatus("در حال اجرا");
   if(!IsTradingEnvironmentReady()) return;
   if(!IsSymbolAllowed()) return;
   LogNearCross();
   int direction = GetEntrySignal();
   bool isReEntry = false;
   if(direction == NO_SIGNAL)
     {
      direction = GetReEntrySignal();
      isReEntry = (direction != NO_SIGNAL);
     }
   if(direction == NO_SIGNAL) return;
   if(CloseOnOppositeSignal)
      CloseOppositePositions(direction);
   if(CountOwnOpenPositions() >= MathMax(MaxOpenPositions, 0))
     {
      PrintFormat("سیگنال شناسایی شد، اما سقف تعداد پوزیشن‌های باز (%d) قبلاً پر شده است.", MaxOpenPositions);
      return;
     }
   if(!CanEnterTrade(direction))
     {
      Print("سیگنال شناسایی شد، اما تاییدیه‌های تابع CanEnterTrade اجازه ورود ندادند.");
      return;
     }
   PrintFormat("%s نهایی شد؛ تلاش برای باز کردن پوزیشن %s انجام می‌شود.",
               isReEntry ? "سیگنال ورود مجدد" : "سیگنال کراس",
               direction == ORDER_TYPE_BUY ? "خرید" : "فروش");
   OpenPosition(direction);
  }
//+------------------------------------------------------------------+
//| رویدادهای چارت                                                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;
   if(sparam == BTN_START)
     {
      g_isActive = true;
      Print("دکمه شروع معامله کلیک شد. اکسپرت از این لحظه دنبال نقطه ورود می‌گردد.");
      UpdateButtonState();
      return;
     }
   if(sparam == BTN_STOP)
     {
      g_isActive = false;
      Print("دکمه توقف اکسپرت کلیک شد. ورودهای جدید متوقف شدند، اما پوزیشن‌های باز همچنان تریل می‌شوند.");
      UpdateButtonState();
      return;
     }
   if(sparam == BTN_MANUAL_BUY)
     {
      OpenManualPosition(ORDER_TYPE_BUY);
      UpdateButtonState();
      return;
     }
   if(sparam == BTN_MANUAL_SELL)
     {
      OpenManualPosition(ORDER_TYPE_SELL);
      UpdateButtonState();
      return;
     }
  }
//+------------------------------------------------------------------+
//| لاگ معاملات بسته‌شده در تستر                                     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!IsTesterLogEnabled(1)) return;
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if((int)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) return;

   double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double dealPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double dealVolume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   long dealReason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);

   TesterLog(1, StringFormat("خروج از معامله | deal=%I64u | نوع=%s | حجم=%.2f | قیمت خروج=%s | سود=%.2f | دلیل=%s",
                          trans.deal,
                          dealType == DEAL_TYPE_BUY ? "خرید" : "فروش",
                          dealVolume,
                          PriceToText(dealPrice),
                          dealProfit,
                          EnumToString((ENUM_DEAL_REASON)dealReason)));
  }
int CountActiveEntryFilters()
  {
   int count = 0;
   if(UseMinMADistanceFilter) count++;
   if(UseADXFilter) count++;
   if(UsePriceAboveMAFilter) count++;
   if(UseRSIFilter) count++;
   if(UseMultiTimeframeFilter) count++;
   if(UseCandleStrengthFilter) count++;
   if(UseSRProximityFilter) count++;
   return count;
  }

//+------------------------------------------------------------------+
//| دروازه اصلی ورود؛ تاییدیه‌های آینده اینجا اضافه می‌شوند.          |
//+------------------------------------------------------------------+
bool CanEnterTrade(const int direction)
  {
   if(!UseFlexibleEntryConfirmations)
     {
      if(UseMinMADistanceFilter && !CheckMinMADistanceFilter()) return false;
      if(UseADXFilter && !CheckADXFilter()) return false;
      if(UsePriceAboveMAFilter && !CheckPriceAboveMAFilter(direction)) return false;
      if(UseRSIFilter && !CheckRSIFilter(direction)) return false;
      if(UseMultiTimeframeFilter && !CheckMultiTimeframeFilter(direction)) return false;
      if(UseCandleStrengthFilter && !CheckCandleStrengthFilter()) return false;
      if(UseSRProximityFilter && !CheckSRProximityFilter(direction)) return false;
      return true;
     }

   int confirmed = 0;
   int enabled   = CountActiveEntryFilters();

   if(UseMinMADistanceFilter && CheckMinMADistanceFilter()) confirmed++;
   if(UseADXFilter && CheckADXFilter()) confirmed++;
   if(UsePriceAboveMAFilter && CheckPriceAboveMAFilter(direction)) confirmed++;
   if(UseRSIFilter && CheckRSIFilter(direction)) confirmed++;
   if(UseMultiTimeframeFilter && CheckMultiTimeframeFilter(direction)) confirmed++;
   if(UseCandleStrengthFilter && CheckCandleStrengthFilter()) confirmed++;
   if(UseSRProximityFilter && CheckSRProximityFilter(direction)) confirmed++;

   if(enabled == 0)
      return true;

   int required = MathMin(enabled, MathMax(MinEntryConfirmations, 1));
   if(confirmed < required)
     {
      string msg = StringFormat("ورود رد شد: فقط %d/%d تاییدیه فیلتر دریافت شد (حداقل %d لازم است).",
                                 confirmed, enabled, required);
      Print(msg);
      if(IsTesterLogEnabled()) TesterLog(msg);
      return false;
     }
   if(IsTesterLogEnabled())
      TesterLog(StringFormat("ورود تایید شد: %d/%d تاییدیه فیلتر دریافت شد.", confirmed, enabled));
   return true;
  }

bool CheckMinMADistanceFilter()
  {
   if(!UseMinMADistanceFilter) return true;

   double atrDist = GetATR();
   double fast1[], slow1[];
   ArraySetAsSeries(fast1, true);
   ArraySetAsSeries(slow1, true);
   if(CopyBuffer(g_fastHandle, 0, 1, 1, fast1) < 1 ||
      CopyBuffer(g_slowHandle, 0, 1, 1, slow1) < 1)
      return true;

   double maDistPoints = MathAbs(fast1[0] - slow1[0]) / _Point;
   double requiredDist = (MinMADistanceATR > 0)
                         ? MinMADistanceATR * (atrDist / _Point)
                         : MinMADistancePoints;

   if(maDistPoints < requiredDist)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر حداقل فاصله MA: رد شد (فاصله=%.1fpt, نیاز=%.1fpt, ATR=%.1fpt)",
                                maDistPoints, requiredDist, atrDist / _Point));
      return false;
     }
   return true;
  }

bool CheckADXFilter()
  {
   if(!UseADXFilter) return true;

   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(g_adxHandle, 0, 0, 1, adx) < 1)
     {
      if(IsTesterLogEnabled())
         TesterLog("فیلتر ADX: رد شد (عدم توانایی در دریافت مقدار ADX)");
      return false;
     }

   if(adx[0] < ADXThreshold)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر ADX: رد شد (ADX=%.2f, آستانه=%.2f)", adx[0], ADXThreshold));
      return false;
     }
   return true;
  }

bool CheckPriceAboveMAFilter(const int direction)
  {
   if(!UsePriceAboveMAFilter) return true;

   double close[], fast2[], slow2[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(fast2, true);
   ArraySetAsSeries(slow2, true);
   if(CopyClose(_Symbol, SignalTimeframe, 0, 1, close) < 1 ||
      CopyBuffer(g_fastHandle, 0, 0, 1, fast2) < 1 ||
      CopyBuffer(g_slowHandle, 0, 0, 1, slow2) < 1)
      return true;

   if(direction == ORDER_TYPE_BUY)
     {
      if(!(close[0] > fast2[0] && fast2[0] > slow2[0]))
        {
         if(IsTesterLogEnabled())
            TesterLog(StringFormat("فیلتر قیمت/MA: رد شد (close=%.5f, fastMA=%.5f, slowMA=%.5f)",
                                   close[0], fast2[0], slow2[0]));
         return false;
        }
     }
   else
     {
      if(!(close[0] < fast2[0] && fast2[0] < slow2[0]))
        {
         if(IsTesterLogEnabled())
            TesterLog(StringFormat("فیلتر قیمت/MA: رد شد (close=%.5f, fastMA=%.5f, slowMA=%.5f)",
                                   close[0], fast2[0], slow2[0]));
         return false;
        }
     }
   return true;
  }

bool CheckRSIFilter(const int direction)
  {
   if(!UseRSIFilter) return true;

   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(g_rsiHandle, 0, 0, 1, rsi) < 1) return true;

   if(direction == ORDER_TYPE_BUY && rsi[0] > RSIOverbought)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر RSI: رد شد (RSI=%.2f, Overbought=%.2f)", rsi[0], RSIOverbought));
      return false;
     }
   if(direction == ORDER_TYPE_SELL && rsi[0] < RSIOversold)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر RSI: رد شد (RSI=%.2f, Oversold=%.2f)", rsi[0], RSIOversold));
      return false;
     }
   return true;
  }

bool CheckMultiTimeframeFilter(const int direction)
  {
   if(!UseMultiTimeframeFilter) return true;

   double fastH[], slowH[];
   ArraySetAsSeries(fastH, true);
   ArraySetAsSeries(slowH, true);
   if(CopyBuffer(g_higherFastMA, 0, 0, 1, fastH) < 1 ||
      CopyBuffer(g_higherSlowMA, 0, 0, 1, slowH) < 1)
     {
      if(IsTesterLogEnabled())
         TesterLog("فیلتر تایم‌فریم بالاتر: رد شد (عدم توانایی در دریافت MA تایم‌فریم بالاتر)");
      return false;
     }

   bool higherBuyTrend = (fastH[0] > slowH[0]);
   if(direction == ORDER_TYPE_BUY && !higherBuyTrend)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر تایم‌فریم بالاتر: رد شد (HigherFast=%.5f, HigherSlow=%.5f)", fastH[0], slowH[0]));
      return false;
     }
   if(direction == ORDER_TYPE_SELL && higherBuyTrend)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر تایم‌فریم بالاتر: رد شد (HigherFast=%.5f, HigherSlow=%.5f)", fastH[0], slowH[0]));
      return false;
     }
   return true;
  }

bool CheckCandleStrengthFilter()
  {
   if(!UseCandleStrengthFilter) return true;

   double atr = GetATR();
   if(atr <= 0) return true;

   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   if(CopyOpen(_Symbol, SignalTimeframe, 1, 1, open) < 1 ||
      CopyHigh(_Symbol, SignalTimeframe, 1, 1, high) < 1 ||
      CopyLow(_Symbol, SignalTimeframe, 1, 1, low) < 1 ||
      CopyClose(_Symbol, SignalTimeframe, 1, 1, close) < 1)
      return true;

   double body = MathAbs(close[0] - open[0]);
   double total = high[0] - low[0];
   if(body < MinCandleBodyATR * atr || total < MinCandleTotalATR * atr)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر قدرت کندل: رد شد (body=%.1fpt, total=%.1fpt, ATR=%.1fpt, body/ATR=%.2f, total/ATR=%.2f)",
                                body / _Point, total / _Point, atr / _Point, body / atr, total / atr));
      return false;
     }
   return true;
  }

bool CheckSRProximityFilter(const int direction)
  {
   if(!UseSRProximityFilter) return true;

   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, SignalTimeframe, 0, 1, close) < 1)
      return true;

   double price = close[0];
   int bars = Bars(_Symbol, SignalTimeframe);
   int lookback = MathMin(SRLookbackBars, bars - 1);
   if(lookback < 2) return true;

   double highest = 0.0;
   double lowest = 0.0;
   for(int i = 1; i <= lookback; i++)
     {
      double h = iHigh(_Symbol, SignalTimeframe, i);
      double l = iLow(_Symbol, SignalTimeframe, i);
      if(i == 1 || h > highest) highest = h;
      if(i == 1 || l < lowest) lowest = l;
     }

   double fastMA[];
   double slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);
   bool maOk = true;
   if(UseMAAsDynamicSR)
     if(CopyBuffer(g_fastHandle, 0, 0, 1, fastMA) < 1 || CopyBuffer(g_slowHandle, 0, 0, 1, slowMA) < 1)
        maOk = false;

   double closestDistance = 1.0e308;
   string nearestLabel = "نامشخص";
   double nearestLevel = 0.0;

   if(direction == ORDER_TYPE_BUY)
     {
      if(highest > price)
        {
         double d = MathAbs(price - highest);
         if(d < closestDistance)
           {
            closestDistance = d;
            nearestLabel = "StaticResistance";
            nearestLevel = highest;
           }
        }
      if(UseMAAsDynamicSR && maOk)
        {
         if(fastMA[0] > price)
           {
            double d = MathAbs(price - fastMA[0]);
            if(d < closestDistance)
              {
               closestDistance = d;
               nearestLabel = "FastMA-Resistance";
               nearestLevel = fastMA[0];
              }
           }
         if(slowMA[0] > price)
           {
            double d = MathAbs(price - slowMA[0]);
            if(d < closestDistance)
              {
               closestDistance = d;
               nearestLabel = "SlowMA-Resistance";
               nearestLevel = slowMA[0];
              }
           }
        }
     }
   else
     {
      if(lowest < price)
        {
         double d = MathAbs(price - lowest);
         if(d < closestDistance)
           {
            closestDistance = d;
            nearestLabel = "StaticSupport";
            nearestLevel = lowest;
           }
        }
      if(UseMAAsDynamicSR && maOk)
        {
         if(fastMA[0] < price)
           {
            double d = MathAbs(price - fastMA[0]);
            if(d < closestDistance)
              {
               closestDistance = d;
               nearestLabel = "FastMA-Support";
               nearestLevel = fastMA[0];
              }
           }
         if(slowMA[0] < price)
           {
            double d = MathAbs(price - slowMA[0]);
            if(d < closestDistance)
              {
               closestDistance = d;
               nearestLabel = "SlowMA-Support";
               nearestLevel = slowMA[0];
              }
           }
        }
     }

   if(closestDistance > 1.0e307)
      return true;

   double distancePoints = closestDistance / _Point;
   if(distancePoints < MinDistanceFromSRPoints)
     {
      if(IsTesterLogEnabled())
         TesterLog(StringFormat("فیلتر S/R: رد شد (%s نزدیک است، فاصله=%.1fpt، نیاز=%.1fpt، سطح=%s)",
                                nearestLabel, distancePoints, MinDistanceFromSRPoints, PriceToText(nearestLevel)));
      return false;
     }

   if(IsTesterLogEnabled())
      TesterLog(StringFormat("فیلتر S/R: قبول شد (%s فاصله=%.1fpt)", nearestLabel, distancePoints));
   return true;
  }

//+------------------------------------------------------------------+
//| خروجی: ORDER_TYPE_BUY، ORDER_TYPE_SELL یا NO_SIGNAL.              |
//+------------------------------------------------------------------+
int GetEntrySignal()
  {
   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(g_fastHandle, 0, 0, 4, fast) < 4 ||
      CopyBuffer(g_slowHandle, 0, 0, 4, slow) < 4)
     {
      Print("امکان کپی کردن بافرهای مووینگ اوریج وجود ندارد.");
      return NO_SIGNAL;
     }
   datetime barTime = iTime(_Symbol, SignalTimeframe, 1);
   if(barTime <= 0 || barTime == g_lastSignalBarTime)
      return NO_SIGNAL;

   bool allowCross = (EntrySignalMode == ENTRY_SIGNAL_CROSS_ONLY ||
                      EntrySignalMode == ENTRY_SIGNAL_CROSS_OR_MOMENTUM);
   bool allowMomentum = (EntrySignalMode == ENTRY_SIGNAL_MOMENTUM_ONLY ||
                         EntrySignalMode == ENTRY_SIGNAL_CROSS_OR_MOMENTUM);

   bool bullishCross = (fast[2] <= slow[2] && fast[1] > slow[1]);
   bool bearishCross = (fast[2] >= slow[2] && fast[1] < slow[1]);
   int crossDirection = NO_SIGNAL;
   if(allowCross && bullishCross)
      crossDirection = ORDER_TYPE_BUY;
   if(allowCross && bearishCross)
      crossDirection = ORDER_TYPE_SELL;

   if(IsTesterLogEnabled() && crossDirection != NO_SIGNAL)
      TesterLog(StringFormat("جزئیات کراس | کندل=%s | fast[2]=%s slow[2]=%s | fast[1]=%s slow[1]=%s",
                             TimeToString(barTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS),
                             PriceToText(fast[2]),
                             PriceToText(slow[2]),
                             PriceToText(fast[1]),
                             PriceToText(slow[1])));

   int momentumDirection = allowMomentum ? GetMomentumEntrySignal(fast) : NO_SIGNAL;
   if(momentumDirection != NO_SIGNAL && crossDirection != NO_SIGNAL && momentumDirection != crossDirection)
     {
      TesterLog(1, "سیگنال رد شد: کراس و ایمپالس جهت مخالف دارند.");
      return NO_SIGNAL;
     }

   int direction = (momentumDirection != NO_SIGNAL) ? momentumDirection : crossDirection;
   if(direction == NO_SIGNAL)
      return NO_SIGNAL;

   g_lastSignalBarTime = barTime;
   if(momentumDirection != NO_SIGNAL)
     {
      PrintFormat("ورود %s تایید شد: کندل ایمپالس/بریک‌اوت تازه شناسایی شد.",
                  direction == ORDER_TYPE_BUY ? "خرید" : "فروش");
      return direction;
     }

   if(direction == ORDER_TYPE_BUY)
     {
      PrintFormat("ورود خرید تایید شد: MA(%d) از بالای MA(%d) عبور کرد.", FastMAPeriod, SlowMAPeriod);
      return ORDER_TYPE_BUY;
     }

   PrintFormat("ورود فروش تایید شد: MA(%d) از پایین MA(%d) عبور کرد.", FastMAPeriod, SlowMAPeriod);
   return ORDER_TYPE_SELL;
  }

int GetMomentumEntrySignal(double &fast[])
  {
   double atr = GetATR();
   if(atr <= 0) return NO_SIGNAL;

   int lookback = MathMax(MomentumBreakoutLookback, 2);
   int needed = lookback + 2;
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   if(CopyOpen(_Symbol, SignalTimeframe, 1, needed, open) < needed ||
      CopyHigh(_Symbol, SignalTimeframe, 1, needed, high) < needed ||
      CopyLow(_Symbol, SignalTimeframe, 1, needed, low) < needed ||
      CopyClose(_Symbol, SignalTimeframe, 1, needed, close) < needed)
     {
      Print("امکان کپی کردن داده‌ها برای سیگنال ایمپالس وجود ندارد.");
      return NO_SIGNAL;
     }

   double body = MathAbs(close[0] - open[0]);
   double range = high[0] - low[0];
   if(range <= 0) return NO_SIGNAL;
   if(body < MomentumMinBodyATR * atr || range < MomentumMinRangeATR * atr)
      return NO_SIGNAL;

   double upperWick = high[0] - MathMax(open[0], close[0]);
   double lowerWick = MathMin(open[0], close[0]) - low[0];
   double maxOppositeWick = MathMax(MomentumMaxWickPercent, 0.0) / 100.0 * range;
   double buffer = MomentumBreakoutBufferPoints * _Point;
   double highestBefore = high[1];
   double lowestBefore = low[1];
   for(int i = 2; i <= lookback; i++)
     {
      if(high[i] > highestBefore) highestBefore = high[i];
      if(low[i] < lowestBefore) lowestBefore = low[i];
     }

   double fastSlopePoints = (fast[1] - fast[2]) / _Point;
   bool priceNotOverextended = (MomentumMaxPriceFastATR <= 0.0 ||
                                MathAbs(close[0] - fast[1]) <= MomentumMaxPriceFastATR * atr);
   bool buyImpulse = (close[0] > open[0] &&
                      close[0] > highestBefore + buffer &&
                      close[0] > fast[1] &&
                      fastSlopePoints >= MomentumMinFastSlopePoints &&
                      upperWick <= maxOppositeWick &&
                      priceNotOverextended);
   bool sellImpulse = (close[0] < open[0] &&
                       close[0] < lowestBefore - buffer &&
                       close[0] < fast[1] &&
                       fastSlopePoints <= -MomentumMinFastSlopePoints &&
                       lowerWick <= maxOppositeWick &&
                       priceNotOverextended);

   if(IsTesterLogEnabled(2) && (buyImpulse || sellImpulse))
      TesterLog(2, StringFormat("جزئیات ایمپالس | body/ATR=%.2f | range/ATR=%.2f | close=%s | fast=%s | slope=%.1fpt | highBreak=%s | lowBreak=%s",
                                body / atr,
                                range / atr,
                                PriceToText(close[0]),
                                PriceToText(fast[1]),
                                fastSlopePoints,
                                PriceToText(highestBefore),
                                PriceToText(lowestBefore)));

   if(buyImpulse) return ORDER_TYPE_BUY;
   if(sellImpulse) return ORDER_TYPE_SELL;
   return NO_SIGNAL;
  }
//+------------------------------------------------------------------+
//| سیگنال ورود مجدد در ادامه روند                                    |
//+------------------------------------------------------------------+
int GetReEntrySignal()
  {
   if(!ReEntryInTrend) return NO_SIGNAL;
   if(g_lastEntryDirection != ORDER_TYPE_BUY && g_lastEntryDirection != ORDER_TYPE_SELL)
      return NO_SIGNAL;
   if(CountOwnOpenPositions() > 0)
      return NO_SIGNAL;

   datetime currentBar = iTime(_Symbol, SignalTimeframe, 0);
   if(currentBar <= 0 || currentBar == g_lastReEntryBarTime)
      return NO_SIGNAL;

   int minBars = MathMax(ReEntryMinBars, 1);
   int tfSeconds = PeriodSeconds(SignalTimeframe);
   if(tfSeconds > 0 && g_lastEntryBarTime > 0 && currentBar - g_lastEntryBarTime < minBars * tfSeconds)
      return NO_SIGNAL;

   double fast[], slow[], cls[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(cls, true);
   if(CopyBuffer(g_fastHandle, 0, 0, 4, fast) < 4 ||
      CopyBuffer(g_slowHandle, 0, 0, 4, slow) < 4 ||
      CopyClose(_Symbol, SignalTimeframe, 0, 4, cls) < 4)
     {
      Print("امکان کپی کردن داده‌ها برای بررسی ورود مجدد وجود ندارد.");
      return NO_SIGNAL;
     }

   bool buyTrend = fast[1] > slow[1] && fast[1] > fast[2] && cls[1] > fast[1];
   bool sellTrend = fast[1] < slow[1] && fast[1] < fast[2] && cls[1] < fast[1];
   if(IsTesterLogEnabled() && (buyTrend || sellTrend))
      TesterLog( StringFormat("جزئیات ورود مجدد | جهت قبلی=%s | fast[2]=%s fast[1]=%s slow[1]=%s close[1]=%s | buyTrend=%s sellTrend=%s",
                             g_lastEntryDirection == ORDER_TYPE_BUY ? "خرید" : "فروش",
                             PriceToText(fast[2]),
                             PriceToText(fast[1]),
                             PriceToText(slow[1]),
                             PriceToText(cls[1]),
                             buyTrend ? "true" : "false",
                             sellTrend ? "true" : "false"));

   if(g_lastEntryDirection == ORDER_TYPE_BUY && buyTrend)
     {
      g_lastReEntryBarTime = currentBar;
      return ORDER_TYPE_BUY;
     }
   if(g_lastEntryDirection == ORDER_TYPE_SELL && sellTrend)
     {
      g_lastReEntryBarTime = currentBar;
      return ORDER_TYPE_SELL;
     }

   return NO_SIGNAL;
  }
//+------------------------------------------------------------------+
//| لاگ نزدیک شدن به کراس روی هر تیک، با محدودیت یک بار در هر کندل.   |
//+------------------------------------------------------------------+
void LogNearCross()
  {
   if(NearCrossPoints <= 0) return;
   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(g_fastHandle, 0, 0, 2, fast) < 2 ||
      CopyBuffer(g_slowHandle, 0, 0, 2, slow) < 2)
      return;
   double distancePoints = MathAbs(fast[0] - slow[0]) / _Point;
   datetime currentBar = iTime(_Symbol, SignalTimeframe, 0);
   if(distancePoints <= NearCrossPoints && currentBar != g_lastNearLogTime)
     {
      string bias = fast[0] >= slow[0] ? "تمایل به خرید" : "تمایل به فروش";
      PrintFormat("خطوط MA به کراس نزدیک شده‌اند: فاصله=%.1f پوینت، %s.", distancePoints, bias);
      g_lastNearLogTime = currentBar;
     }
  }
//+------------------------------------------------------------------+
//| باز کردن پوزیشن بازار                                            |
//+------------------------------------------------------------------+
bool OpenManualPosition(const int direction)
  {
   PrintFormat("درخواست دستی برای باز کردن پوزیشن %s دریافت شد.",
               direction == ORDER_TYPE_BUY ? "خرید" : "فروش");
   if(!IsTradingEnvironmentReady()) return false;
   if(!IsSymbolAllowed()) return false;
   if(CountOwnOpenPositions() >= MathMax(MaxOpenPositions, 0))
     {
      PrintFormat("ورود دستی انجام نشد؛ سقف تعداد پوزیشن‌های باز (%d) پر شده است.", MaxOpenPositions);
      return false;
     }
   if(!CanEnterTrade(direction))
     {
      Print("ورود دستی انجام نشد؛ تاییدیه‌های تابع CanEnterTrade اجازه ورود ندادند.");
      return false;
     }
   PrintFormat("ورود دستی تایید شد؛ تلاش برای باز کردن پوزیشن %s انجام می‌شود.",
               direction == ORDER_TYPE_BUY ? "خرید" : "فروش");
   return OpenPosition(direction);
  }
void LogOpenPositionAttempt(const int direction, const double price, const double lot, const double sl, const double tp)
  {
   string dirText = direction == ORDER_TYPE_BUY ? "خرید" : "فروش";
   string msg = StringFormat("ارسال سفارش بازار: نوع=%s | قیمت مرجع=%s | لات=%.2f | حد ضرر=%s | حد سود=%s",
                             dirText,
                             PriceToText(price),
                             lot,
                             PriceToText(sl),
                             PriceToText(tp));
   Print(msg);
   TesterLog(2, msg);
  }

void LogOpenPositionFailure(const int direction, const string reason)
  {
   string dirText = direction == ORDER_TYPE_BUY ? "خرید" : "فروش";
   string msg = StringFormat("باز کردن پوزیشن %s ناموفق شد: %s", dirText, reason);
   Print(msg);
   TesterLog(1, msg);
  }

void LogOpenPositionSuccess(const int direction, const double lot, const double sl, const double tp)
  {
   string dirText = direction == ORDER_TYPE_BUY ? "خرید" : "فروش";
   string msg = StringFormat("پوزیشن %s باز شد | لات=%.2f | حد ضرر=%s | حد سود=%s",
                             dirText,
                             lot,
                             PriceToText(sl),
                             PriceToText(tp));
   Print(msg);
   if(IsTesterLogEnabled())
      TesterLog(1, StringFormat("ورود موفق | نوع=%s | order=%I64u | deal=%I64u | قیمت اجرا=%s | کد=%d %s",
                             dirText,
                             trade.ResultOrder(),
                             trade.ResultDeal(),
                             PriceToText(trade.ResultPrice()),
                             trade.ResultRetcode(),
                             trade.ResultRetcodeDescription()));
  }

bool PrepareOpenPosition(const int direction, double &lot, double &price, double &sl, double &tp)
  {
   lot = NormalizeLot(LotSize);
   if(lot <= 0)
     {
      LogOpenPositionFailure(direction, "حجم لات نامعتبر است.");
      return false;
     }

   if(!IsTradingEnvironmentReady())
     {
      LogOpenPositionFailure(direction, "محیط معامله آماده نیست.");
      return false;
     }

   if(!IsSymbolAllowed())
     {
      LogOpenPositionFailure(direction, "نماد چارت فعلی مجاز نیست.");
      return false;
     }

   if(CountOwnOpenPositions() >= MathMax(MaxOpenPositions, 0))
     {
      LogOpenPositionFailure(direction, StringFormat("سقف تعداد پوزیشن‌های باز (%d) پر شده است.", MaxOpenPositions));
      return false;
     }

   price = direction == ORDER_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   sl = BuildStopLoss(direction, price);
   tp = BuildTakeProfit(direction, price);
   return true;
  }

bool SendMarketOrder(const int direction, const double lot, const double price, const double sl, const double tp)
  {
   ResetLastError();
   LogOpenPositionAttempt(direction, price, lot, sl, tp);

   bool ok = false;
   if(direction == ORDER_TYPE_BUY)
      ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, "GTT خرید کراس MA");
   else
      ok = trade.Sell(lot, _Symbol, 0.0, sl, tp, "GTT فروش کراس MA");

   if(!ok)
     {
      string reason = StringFormat("کد معامله=%d توضیح=%s | خطای سیستم=%d",
                                   trade.ResultRetcode(),
                                   trade.ResultRetcodeDescription(),
                                   GetLastError());
      LogOpenPositionFailure(direction, reason);
      return false;
     }

   LogOpenPositionSuccess(direction, lot, sl, tp);
   g_lastEntryDirection = direction;
   g_lastEntryBarTime = iTime(_Symbol, SignalTimeframe, 1);
   g_lastSLBarTime = 0; // ریست برای تریلینگ پوزیشن جدید
   return true;
  }

bool OpenPosition(const int direction)
  {
   double lot, price, sl, tp;
   if(!PrepareOpenPosition(direction, lot, price, sl, tp))
      return false;
   return SendMarketOrder(direction, lot, price, sl, tp);
  }

  
//+------------------------------------------------------------------+
//| بررسی و اعمال Breakeven (انتقال SL به نقطه ورود + بافر)          |
//+------------------------------------------------------------------+
double ApplyBreakevenIfNeeded(const long posType, const double currentSL,
                              const double openPrice, const double atr)
  {
   if(!UseBreakevenProtection) return currentSL;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double breakevenDist = BreakevenATR * atr;
   double bufferPts     = BreakevenBufferPoints * _Point;

   double beSL = 0.0;
   bool   triggered = false;

   if(posType == POSITION_TYPE_BUY)
     {
      if(bid - openPrice >= breakevenDist)
        {
         beSL = NormalizeDouble(openPrice + bufferPts, digits);
         triggered = (currentSL < beSL);
        }
     }
   else
     {
      if(openPrice - ask >= breakevenDist)
        {
         beSL = NormalizeDouble(openPrice - bufferPts, digits);
         triggered = (currentSL == 0 || currentSL > beSL);
        }
     }

   if(triggered)
     {
      if(IsTesterLogEnabled() && TesterLogLevel >= 2)
         TesterLog(StringFormat("Breakeven فعال شد | SL جدید=%s (ورود=%s)", PriceToText(beSL), PriceToText(openPrice)));
      return beSL;
     }
   return currentSL;
  }

//+------------------------------------------------------------------+
//| مدیریت تریلینگ بر اساس ATR                                       |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!UseATRTrailing || g_atrHandle == INVALID_HANDLE) return;
   double atr = GetATR();
   if(atr <= 0) return;

   double slDistance = atr * MathMax(SLTrailATRMult, 0.1);
   double startProfitDist = atr * MathMax(TrailStartATR, 0.05);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   datetime currentBar = iTime(_Symbol, SignalTimeframe, 0);
   bool canUpdateSL = !UpdateSLOnBarCloseOnly || (currentBar != g_lastSLBarTime);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP); // ثابت می‌ماند
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentPrice = (type == POSITION_TYPE_BUY) ? bid : ask;
      double profitDist = (type == POSITION_TYPE_BUY) ? (bid - openPrice) : (openPrice - ask);
      double profitATR = (atr > 0) ? profitDist / atr : 0.0;

      // ** Breakeven **
      if(UseBreakevenProtection && profitDist > 0)
      {
         double beTrigger = BreakevenATR * atr;
         if(profitDist >= beTrigger)
         {
            double beSL = 0.0;
            double buf = BreakevenBufferPoints * _Point;
            if(type == POSITION_TYPE_BUY)
               beSL = NormalizeDouble(openPrice + buf, digits);
            else
               beSL = NormalizeDouble(openPrice - buf, digits);
            // فقط اگر بهتر از SL فعلی باشد اعمال کن
            bool improve = (type == POSITION_TYPE_BUY && (currentSL == 0 || beSL > currentSL)) ||
                           (type == POSITION_TYPE_SELL && (currentSL == 0 || beSL < currentSL));
            if(improve)
            {
               if(trade.PositionModify(ticket, beSL, currentTP))
               {
                  PrintFormat("Breakeven فعال شد: تیکت=%I64u | SL=%s", ticket, PriceToText(beSL));
                  currentSL = beSL; // برای ادامه‌ی منطق
               }
            }
         }
      }

      // ** تریلینگ اصلی **
      if(profitDist >= startProfitDist && canUpdateSL)
      {
         double newSL = 0.0;
         if(type == POSITION_TYPE_BUY)
            newSL = NormalizeDouble(bid - slDistance, digits);
         else
            newSL = NormalizeDouble(ask + slDistance, digits);

         // SL فقط باید در جهت سود حرکت کند
         bool improved = false;
         if(type == POSITION_TYPE_BUY)
            improved = (currentSL == 0 || newSL > currentSL + _Point); // حداقل ۱ پوینت بهبود
         else
            improved = (currentSL == 0 || newSL < currentSL - _Point);

         if(improved)
         {
            // جلوگیری از آپدیت‌های میکروسکوپی (اختیاری، در اینجا ۲ پوینت)
            double step = 2.0 * _Point;
            if(currentSL != 0)
            {
               double diff = (type == POSITION_TYPE_BUY) ? (newSL - currentSL) : (currentSL - newSL);
               if(diff < step) improved = false;
            }

            if(improved)
            {
               if(trade.PositionModify(ticket, newSL, currentTP))
               {
                  PrintFormat("تریلینگ SL | تیکت=%I64u | SL=%s", ticket, PriceToText(newSL));
                  if(UpdateSLOnBarCloseOnly)
                     g_lastSLBarTime = currentBar;
               }
            }
         }
      }
      // TP هرگز تغییر نمی‌کند
   }
}

  //+------------------------------------------------------------------+
//| بررسی شرایط مجاز بودن معامله                                      |
//+------------------------------------------------------------------+
bool IsTradingEnvironmentReady()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      PrintOncePerBar("الگوتریدینگ در ترمینال غیرفعال است.");
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      PrintOncePerBar("معامله زنده برای این اکسپرت غیرفعال است.");
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      PrintOncePerBar("معامله برای این حساب مجاز نیست.");
      return false;
     }
   if(MaxSpreadPoints > 0)
     {
      int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > MaxSpreadPoints)
        {
         PrintOncePerBar(StringFormat("اسپرد بیش از حد مجاز است: %d پوینت > %d.", spread, MaxSpreadPoints));
         return false;
        }
     }
   return true;
  }
bool IsSymbolAllowed()
  {
   if(IsSymbolAllowedSilent()) return true;
   PrintOncePerBar(StringFormat("این اکسپرت برای %s تنظیم شده، اما نماد چارت فعلی %s است.", ExpectedSymbol, _Symbol));
   return false;
  }
bool IsSymbolAllowedSilent()
  {
   if(ExpectedSymbol == "") return true;
   return StringFind(_Symbol, ExpectedSymbol) >= 0;
  }
bool IsTester()
  {
   return (bool)MQLInfoInteger(MQL_TESTER);
  }
bool IsTesterLogEnabled()
  {
   return IsTester() && TesterVerboseLogs;
  }
bool IsTesterLogEnabled(const int level)
  {
   return IsTester() && TesterVerboseLogs && TesterLogLevel >= level;
  }
void TesterLog(const string message)
  {
   TesterLog(2, message);
  }
void TesterLog(const int level, const string message)
  {
   if(IsTesterLogEnabled(level))
      Print("[TESTER] ", message);
  }
//+------------------------------------------------------------------+
//| توابع کمکی پوزیشن                                                |
//+------------------------------------------------------------------+
int CountOwnOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      count++;
     }
   return count;
  }
void CloseOppositePositions(const int direction)
  {
   long oppositeType = direction == ORDER_TYPE_BUY ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(PositionGetInteger(POSITION_TYPE) != oppositeType) continue;
      if(trade.PositionClose(ticket))
         PrintFormat("پوزیشن مخالف قبل از ورود جدید بسته شد. تیکت=%I64u", ticket);
      else
         PrintFormat("بستن پوزیشن مخالف ناموفق بود. تیکت=%I64u | %s",
                     ticket, trade.ResultRetcodeDescription());
     }
  }
//+------------------------------------------------------------------+
//| توابع کمکی قیمت و ریسک                                           |
//+------------------------------------------------------------------+
double BuildStopLoss(const int direction, const double entryPrice)
  {
   if(StopLossPoints <= 0 || UseDisableInitialSL) return 0.0;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = direction == ORDER_TYPE_BUY
               ? entryPrice - StopLossPoints * _Point
               : entryPrice + StopLossPoints * _Point;
   double tp = 0.0;
   EnforceStopsDistance(DirectionToPositionType(direction), sl, tp);
   return NormalizeDouble(sl, digits);
  }
double BuildTakeProfit(const int direction, const double entryPrice)
{
   // اگر تریلینگ فعال و TP استاتیک درخواست شده، TP_ATRFactor را به‌کار ببر
   if(UseATRTrailing && StaticTP_ATRFactor > 0)
   {
      double atr = GetATR();
      if(atr > 0)
      {
         int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
         double tp = direction == ORDER_TYPE_BUY
                     ? entryPrice + atr * StaticTP_ATRFactor
                     : entryPrice - atr * StaticTP_ATRFactor;
         return NormalizeDouble(tp, digits);
      }
   }
   // در غیر این صورت از روش قبلی استفاده می‌کند (اگر پارامتر قدیمی TakeProfitPoints تنظیم شده باشد)
   if(TakeProfitPoints > 0)
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double tp = direction == ORDER_TYPE_BUY
                  ? entryPrice + TakeProfitPoints * _Point
                  : entryPrice - TakeProfitPoints * _Point;
      return NormalizeDouble(tp, digits);
   }
   return 0.0;
}


long DirectionToPositionType(const int direction)
  {
   return direction == ORDER_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
  }
void EnforceStopsDistance(const long positionType, double &sl, double &tp)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDistance = (stopsLevel + freezeLevel + 2) * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(positionType == POSITION_TYPE_BUY)
     {
      if(sl > 0 && bid - sl < minDistance) sl = bid - minDistance;
      if(tp > 0 && tp - bid < minDistance) tp = bid + minDistance;
     }
   else
     {
      if(sl > 0 && sl - ask < minDistance) sl = ask + minDistance;
      if(tp > 0 && ask - tp < minDistance) tp = ask - minDistance;
     }
   if(sl > 0) sl = NormalizeDouble(sl, digits);
   if(tp > 0) tp = NormalizeDouble(tp, digits);
  }
double GetATR()
  {
   if(g_atrHandle == INVALID_HANDLE) return 0.0;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_atrHandle, 0, 1, 2, atr) < 1)
      return 0.0;
   return atr[0];
  }

double NormalizeLot(const double requestedLot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) return 0.0;
   double lot = MathMax(minLot, MathMin(requestedLot, maxLot));
   lot = MathFloor(lot / step) * step;
   lot = MathMax(minLot, MathMin(lot, maxLot));
   int volumeDigits = 0;
   double probe = step;
   while(volumeDigits < 8 && MathAbs(probe - MathRound(probe)) > 0.00000001)
     {
      probe *= 10.0;
      volumeDigits++;
     }
   return NormalizeDouble(lot, volumeDigits);
  }
bool ShouldModifyPosition(const long type, const double currentSL, const double currentTP,
                          const double newSL, const double newTP)
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = _Point;
   bool slChanged = false;
   bool tpChanged = false;
   if(type == POSITION_TYPE_BUY)
     {
      slChanged = (newSL > 0 && (currentSL == 0 || newSL > currentSL + tickSize));
      tpChanged = (newTP > 0 && (currentTP == 0 || newTP > currentTP + tickSize));
     }
   else
     {
      slChanged = (newSL > 0 && (currentSL == 0 || newSL < currentSL - tickSize));
      tpChanged = (newTP > 0 && (currentTP == 0 || newTP < currentTP - tickSize));
     }
   return slChanged || tpChanged;
  }


string PriceToText(const double price)
  {
   if(price <= 0) return "ندارد";
   return DoubleToString(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
  }

string EntrySignalModeText()
  {
   if(EntrySignalMode == ENTRY_SIGNAL_CROSS_ONLY)
      return "فقط کراس";
   if(EntrySignalMode == ENTRY_SIGNAL_MOMENTUM_ONLY)
      return "فقط ایمپالس";
   return "کراس+ایمپالس";
  }

void PrintOncePerBar(const string message)
  {
   datetime currentBar = iTime(_Symbol, SignalTimeframe, 0);
   if(currentBar == g_lastEnvLogTime) return;
   Print(message);
   g_lastEnvLogTime = currentBar;
  }
//+------------------------------------------------------------------+
//| رابط کاربری روی چارت                                             |
//+------------------------------------------------------------------+
void CreateControlButtons()
  {
   CreateStateLabel();
   CreateButton(BTN_MANUAL_SELL, "فروش دستی", ButtonX, ButtonY + 112, clrWhite, clrFireBrick);
   CreateButton(BTN_MANUAL_BUY, "خرید دستی", ButtonX + 116, ButtonY + 112, clrWhite, clrSeaGreen);
   CreateButton(BTN_STOP, "توقف اکسپرت", ButtonX, ButtonY + 146, clrWhite, clrMaroon);
   CreateButton(BTN_START, "شروع معامله", ButtonX + 116, ButtonY + 146, clrWhite, clrDarkGreen);
   UpdateButtonState();
  }
void CreateButton(const string name, const string text, const int x, const int y,
                  const color textColor, const color bgColor)
  {
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 106);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 28);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrSilver);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }
void CreateStateLabel()
  {
   ObjectDelete(0, LBL_STATE);
   ObjectCreate(0, LBL_STATE, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, LBL_STATE, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, LBL_STATE, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, LBL_STATE, OBJPROP_XDISTANCE, ButtonX);
   ObjectSetInteger(0, LBL_STATE, OBJPROP_YDISTANCE, ButtonY);
   ObjectSetInteger(0, LBL_STATE, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, LBL_STATE, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, LBL_STATE, OBJPROP_FONT, "Tahoma");
  }
void UpdateButtonState()
  {
   if(ObjectFind(0, BTN_START) >= 0)
      ObjectSetInteger(0, BTN_START, OBJPROP_STATE, false);
   if(ObjectFind(0, BTN_STOP) >= 0)
      ObjectSetInteger(0, BTN_STOP, OBJPROP_STATE, false);
   if(ObjectFind(0, BTN_MANUAL_BUY) >= 0)
      ObjectSetInteger(0, BTN_MANUAL_BUY, OBJPROP_STATE, false);
   if(ObjectFind(0, BTN_MANUAL_SELL) >= 0)
      ObjectSetInteger(0, BTN_MANUAL_SELL, OBJPROP_STATE, false);
  }
void DrawStatus(const string mode)
  {
   string symbolStatus = IsSymbolAllowedSilent() ? "مجاز" : "غیرمجاز";
   string trailingStatus = UseATRTrailing ? "تریلینگ ATR فعال" : "تریلینگ ATR غیرفعال";
   string reEntryStatus = ReEntryInTrend ? "ورود مجدد فعال" : "ورود مجدد غیرفعال";
   string signalMode = EntrySignalModeText();
   string statusText = StringFormat("GoldenTrendTrailEA v%s\nوضعیت: %s\nنماد: %s (%s)\nسیگنال: %s MA(%d/%d) %s\nپوزیشن‌ها: %d/%d\n%s | %s",
                                    EA_VERSION,
                                    mode,
                                    _Symbol,
                                    symbolStatus,
                                    signalMode,
                                    FastMAPeriod,
                                    SlowMAPeriod,
                                    EnumToString(SignalTimeframe),
                                    CountOwnOpenPositions(),
                                    MathMax(MaxOpenPositions, 0),
                                    trailingStatus,
                                    reEntryStatus);
   Comment("");
   if(ObjectFind(0, LBL_STATE) >= 0)
      ObjectSetString(0, LBL_STATE, OBJPROP_TEXT, statusText);
   UpdateButtonState();
  }
//+------------------------------------------------------------------+
