//+------------------------------------------------------------------+
//| Professional Trend Following EA - SMART RISK EDITION            |
//+------------------------------------------------------------------+

#property copyright "Institutional Trader"
#property version   "3.42"
#property description "v3.10 aggressive engine + Equity Floor Ratchet (never drop below initial after +10%) + 5% trailing daily DD"

//=== STRATEGY PARAMETERS ===
input group "=== STRATEGY PARAMETERS ==="
input ENUM_TIMEFRAMES Trend_Timeframe = PERIOD_H4;    // Trend timeframe
input ENUM_TIMEFRAMES Entry_Timeframe = PERIOD_M5;    // Entry timeframe
input int EMA_Period_1 = 20;                          // Fast EMA period
input int EMA_Period_2 = 50;                          // Medium EMA period
input int EMA_Period_3 = 100;                         // Slow EMA period

//=== RISK MANAGEMENT ===
input group "=== RISK MANAGEMENT ==="
input double Risk_Per_Trade = 0.5;                    // Risk per trade (%)
input double Max_Daily_Drawdown_Pct = 5.0;            // Max daily drawdown % (trailing from today's peak)
input bool Use_Equity_Floor = true;                   // Lock-in profit floor (trails below peak)
input double Floor_Step_Pct = 10.0;                   // Floor trails N% below peak equity (arms after +N% gain)
input bool Close_All_On_Floor_Breach = true;          // Close open trades if equity touches the floor
input int Max_Open_Trades = 5;                        // Max concurrent trades
input bool Use_ATR_Stops = true;                      // Use ATR for stops
input double ATR_Multiplier = 2.0;                    // ATR multiplier
input double Risk_Reward_Ratio = 2.0;                 // Min R:R ratio

//=== SMART MONEY MANAGEMENT ===
input group "=== SMART MONEY MANAGEMENT ==="
input bool Use_Smart_Risk = true;                     // Enable smart risk scaling
input double HWM_Drawdown_Step1 = 5.0;               // Drawdown from peak (%) → 75% of lots
input double HWM_Drawdown_Step2 = 10.0;              // Drawdown from peak (%) → 50% of lots
input double HWM_Drawdown_Step3 = 15.0;              // Drawdown from peak (%) → 25% of lots
input double Profit_Protect_Level1 = 30.0;           // Account gain (%) → 80% risk
input double Profit_Protect_Level2 = 75.0;           // Account gain (%) → 60% risk
input double Profit_Protect_Level3 = 150.0;          // Account gain (%) → 40% risk (doubled+)
input int Consec_Loss_Reduce_After = 2;              // Reduce lots after N consecutive losses
input double Consec_Loss_Multiplier = 0.70;          // Lot multiplier per loss streak step
input double Max_Spread_Points = 50.0;               // Max allowed spread in points (0=off)

//=== DYNAMIC LOT SETTINGS ===
input group "=== DYNAMIC LOT SETTINGS ==="
input bool Use_Dynamic_Lots = true;                   // Enable linear equity-based lot sizing
input double Starting_Lot_Size = 0.01;                // Lot size at initial capital
input double Equity_Step_USD = 100.0;                 // Every $N of profit growth...
input double Lot_Increase_Per_Step = 0.03;            // ...adds this many lots
input double Lot_Multiplier = 1.0;                    // Extra scaling on top (1.0 = no change)

//=== TRADE FILTERS ===
input group "=== TRADE FILTERS ==="
input bool Filter_By_Time = false;                    // Time filter OFF — v3.10 style 24h trading
input int Trading_Start_Hour = 7;                     // Start hour (server time) if filter enabled
input int Trading_End_Hour = 20;                      // End hour (server time) if filter enabled
input int ADX_Period = 14;                            // ADX period for trend strength
input double Min_ADX = 0.0;                           // ADX filter OFF by default (v3.10 style; set 20 to enable)
input bool Require_Candle_Close_Confirm = false;      // Use last CLOSED bar's close vs EMA (filters live-tick noise)
input bool Require_EMA_Slope = false;                 // Fast EMA must be rising(buy)/falling(sell), not flat

//=== TRAILING STOP ===
input group "=== TRAILING STOP ==="
input bool Use_Trailing_Stop = true;                  // Enable ATR trailing stop
input bool Use_Breakeven = true;                      // Move SL to breakeven first
input double Breakeven_ATR = 1.0;                     // ATR profit to trigger breakeven (v3.10 value)
input double Trail_Start_ATR = 1.5;                   // ATR profit before trail activates (v3.10 value)
input double Trail_Distance_ATR = 1.0;                // ATR trail distance (v3.10 value)

//=== EXECUTION SETTINGS ===
input group "=== EXECUTION SETTINGS ==="
input int ATR_Period = 14;                            // ATR period
input int Magic_Number = 2024;                        // Magic number
input bool Enable_Trading = true;                     // Enable trading
input bool Show_Debug = true;                         // Show debug messages

//--- Indicator handles
int ema1_trend, ema2_trend, ema3_trend, atr_trend;
int ema1_entry, ema2_entry, ema3_entry, atr_entry;
int adx_trend;   // ADX on trend timeframe — trend strength filter

//--- Daily tracking
datetime last_trade_time = 0;
int tick_count = 0;
int today_trades = 0;
datetime last_day_check = 0;          // Stores midnight of last checked day
double daily_peak_equity = 0.0;       // Highest equity seen TODAY (resets each day)
bool daily_drawdown_hit = false;      // True once today's 10% drawdown limit is breached

//--- Smart risk tracking
double initial_equity = 0.0;          // Equity at EA start
double equity_high_water_mark = 0.0;  // All-time highest equity seen
int consecutive_losses = 0;           // All-time loss streak — used for lot size scaling
int consecutive_wins = 0;             // All-time win streak
int daily_consecutive_losses = 0;     // TODAY's loss streak only — resets each day, controls daily stop
int total_trades_closed = 0;
double last_known_positions_profit = 0.0;

//--- Equity floor (profit lock-in ratchet)
double equity_floor = 0.0;            // Equity must never drop below this; 0 = not yet armed
bool floor_breached = false;          // True once floor is hit — trading halts until EA restart

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== SMART RISK PROFESSIONAL EA v3.20 INITIALIZED ===");

   initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   equity_high_water_mark = initial_equity;
   daily_peak_equity = initial_equity;   // Today's trailing peak starts at current equity
   daily_drawdown_hit = false;

   // Store midnight of today so we compare DATES not full timestamps (was the "sometimes works" bug)
   last_day_check = (TimeCurrent() / 86400) * 86400;

   // Create trend timeframe indicators
   ema1_trend = iMA(_Symbol, Trend_Timeframe, EMA_Period_1, 0, MODE_EMA, PRICE_CLOSE);
   ema2_trend = iMA(_Symbol, Trend_Timeframe, EMA_Period_2, 0, MODE_EMA, PRICE_CLOSE);
   ema3_trend = iMA(_Symbol, Trend_Timeframe, EMA_Period_3, 0, MODE_EMA, PRICE_CLOSE);
   atr_trend  = iATR(_Symbol, Trend_Timeframe, ATR_Period);

   // Create entry timeframe indicators
   ema1_entry = iMA(_Symbol, Entry_Timeframe, EMA_Period_1, 0, MODE_EMA, PRICE_CLOSE);
   ema2_entry = iMA(_Symbol, Entry_Timeframe, EMA_Period_2, 0, MODE_EMA, PRICE_CLOSE);
   ema3_entry = iMA(_Symbol, Entry_Timeframe, EMA_Period_3, 0, MODE_EMA, PRICE_CLOSE);
   atr_entry  = iATR(_Symbol, Entry_Timeframe, ATR_Period);
   adx_trend  = iADX(_Symbol, Trend_Timeframe, ADX_Period);

   if(ema1_trend == INVALID_HANDLE || ema2_trend == INVALID_HANDLE || ema3_trend == INVALID_HANDLE ||
      ema1_entry == INVALID_HANDLE || ema2_entry == INVALID_HANDLE || ema3_entry == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicators");
      return INIT_FAILED;
   }

   Print("SMART RISK ACTIVE:");
   Print("- Initial Equity: $", initial_equity);
   Print("- HWM Steps: ", HWM_Drawdown_Step1, "% / ", HWM_Drawdown_Step2, "% / ", HWM_Drawdown_Step3, "%");
   Print("- Profit Protection: ", Profit_Protect_Level1, "% / ", Profit_Protect_Level2, "% / ", Profit_Protect_Level3, "%");
   Print("- Spread Filter: ", Max_Spread_Points > 0 ? DoubleToString(Max_Spread_Points, 0) + " pts" : "OFF");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   tick_count++;

   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Update all-time high water mark
   if(current_equity > equity_high_water_mark)
      equity_high_water_mark = current_equity;

   // --- Equity floor: trails 10% below peak equity ---
   // Arms once equity has gained 10% from initial capital. From then on the
   // floor is always (peak equity - 10%), rising with every new peak, and it
   // never sits below the initial capital.
   //   Peak $1,100 -> floor $1,000 (initial protected)
   //   Peak $1,500 -> floor $1,350
   //   Peak $2,400 -> floor $2,160
   if(Use_Equity_Floor && initial_equity > 0 && !floor_breached)
   {
      if(equity_high_water_mark >= initial_equity * (1.0 + Floor_Step_Pct / 100.0))
      {
         double candidate_floor = equity_high_water_mark * (1.0 - Floor_Step_Pct / 100.0);
         candidate_floor = MathMax(candidate_floor, initial_equity); // never below starting capital
         if(candidate_floor > equity_floor)
         {
            equity_floor = candidate_floor;
            Print(">>> EQUITY FLOOR RAISED: $", DoubleToString(equity_floor, 2),
                  " (", DoubleToString(Floor_Step_Pct, 0), "% below peak $",
                  DoubleToString(equity_high_water_mark, 2), ")");
         }
      }

      // Breach check — equity touched the locked floor
      if(equity_floor > 0 && current_equity <= equity_floor)
      {
         floor_breached = true;
         Print("!!! EQUITY FLOOR BREACHED at $", DoubleToString(current_equity, 2),
               " (floor: $", DoubleToString(equity_floor, 2), ") — TRADING HALTED. Restart EA to resume. !!!");
         if(Close_All_On_Floor_Breach)
            CloseAllEAPositions();
      }
   }
   // --- End equity floor ---

   // Update TODAY's trailing peak — drawdown limit rises whenever profit grows
   // e.g. $1000 start → profits to $1200 → drawdown now measured from $1200 (limit = $120 loss)
   if(current_equity > daily_peak_equity)
      daily_peak_equity = current_equity;

   // Check trailing daily drawdown limit every tick
   if(!daily_drawdown_hit && daily_peak_equity > 0)
   {
      double daily_dd_pct = ((daily_peak_equity - current_equity) / daily_peak_equity) * 100.0;
      if(daily_dd_pct >= Max_Daily_Drawdown_Pct)
      {
         daily_drawdown_hit = true;
         Print("!!! DAILY DRAWDOWN LIMIT HIT: -", DoubleToString(daily_dd_pct, 1), "% from today's peak $",
               DoubleToString(daily_peak_equity, 2),
               " | Equity: $", DoubleToString(current_equity, 2),
               " | No more trades until tomorrow !!!");
      }
   }

   // New day — reset daily state
   ResetDailyCounters();

   if(Show_Debug && tick_count % 100 == 0)
   {
      double risk_mult   = GetSmartRiskMultiplier();
      double alltime_dd  = (equity_high_water_mark > 0) ?
                           ((equity_high_water_mark - current_equity) / equity_high_water_mark) * 100.0 : 0.0;
      double daily_dd    = (daily_peak_equity > 0) ?
                           ((daily_peak_equity - current_equity) / daily_peak_equity) * 100.0 : 0.0;
      double gain_pct    = (initial_equity > 0) ?
                           ((current_equity - initial_equity) / initial_equity) * 100.0 : 0.0;

      Print("Heartbeat | Ticks: ", tick_count,
            " | Trades Today: ", today_trades,
            " | Open: ", CountPositions(),
            " | Equity: $", DoubleToString(current_equity, 2),
            " | Gain: ", DoubleToString(gain_pct, 1), "%",
            " | Daily DD: ", DoubleToString(daily_dd, 1), "% (peak $", DoubleToString(daily_peak_equity, 2), ")",
            " | All-time DD: ", DoubleToString(alltime_dd, 1), "%",
            " | Risk Mult: ", DoubleToString(risk_mult, 2),
            " | Daily Losses: ", daily_consecutive_losses, "/3",
            " | Floor: $", DoubleToString(equity_floor, 2),
            daily_drawdown_hit ? " | [DD LIMIT]" : "",
            daily_consecutive_losses >= 3 ? " | [LOSS STOP]" : "",
            floor_breached ? " | [FLOOR BREACHED - HALTED]" : "");
   }

   // Manage trailing stops on every tick (before entry checks)
   if(Use_Trailing_Stop) ManageTrailingStops();

   if(!IsTradingAllowed())
   {
      if(Show_Debug && tick_count % 500 == 0)
         Print("Trading not allowed - Check AutoTrading button");
      return;
   }

   // Check spread filter before doing anything
   if(Max_Spread_Points > 0 && !IsSpreadAcceptable())
   {
      if(Show_Debug && tick_count % 200 == 0)
         Print("Spread too wide - skipping tick");
      return;
   }

   // Only evaluate signals on new M1 bar
   // Evaluate signals on every new M1 bar — v3.10 style frequent trading
   static datetime last_bar = 0;
   datetime current_bar = iTime(_Symbol, PERIOD_M1, 0);
   if(current_bar != last_bar)
   {
      last_bar = current_bar;
      CheckForTrades();
   }
}

//+------------------------------------------------------------------+
//| Called on every trade transaction (tracks wins/losses)          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Only care about closing deals on this symbol from this EA
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.symbol != _Symbol) return;

   ulong deal_ticket = trans.deal;
   if(!HistoryDealSelect(deal_ticket)) return;

   // Only closing deals (EXIT or CLOSE_BY)
   ENUM_DEAL_ENTRY deal_entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   if(deal_entry != DEAL_ENTRY_OUT && deal_entry != DEAL_ENTRY_INOUT) return;

   // Verify it belongs to this EA
   long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   if(deal_magic != Magic_Number) return;

   double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
   total_trades_closed++;

   if(deal_profit > 0)
   {
      consecutive_losses = 0;           // All-time streak resets on win
      daily_consecutive_losses = 0;     // Daily streak also resets on win
      consecutive_wins++;
      if(Show_Debug) Print("CLOSED WIN | Profit: $", DoubleToString(deal_profit, 2),
                           " | Win Streak: ", consecutive_wins,
                           " | Daily losses reset to 0");
   }
   else
   {
      consecutive_wins = 0;
      consecutive_losses++;             // All-time streak — used for lot scaling
      daily_consecutive_losses++;       // Daily streak — used for daily stop rule
      if(Show_Debug) Print("CLOSED LOSS | Loss: $", DoubleToString(deal_profit, 2),
                           " | All-time streak: ", consecutive_losses,
                           " | Daily losses today: ", daily_consecutive_losses,
                           daily_consecutive_losses >= 3 ? " — DAILY STOP TRIGGERED" : "");
   }
}

//+------------------------------------------------------------------+
//| Calculate the smart risk multiplier (0.0 – 1.0)                |
//| Combines: HWM drawdown + profit protection + loss streak        |
//+------------------------------------------------------------------+
double GetSmartRiskMultiplier()
{
   if(!Use_Smart_Risk) return 1.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double mult = 1.0;

   // --- 1. High-Water-Mark drawdown reduction ---
   // When equity drops from its peak, we scale down aggressively
   if(equity_high_water_mark > 0)
   {
      double dd_pct = ((equity_high_water_mark - equity) / equity_high_water_mark) * 100.0;

      if(dd_pct >= HWM_Drawdown_Step3)
         mult = MathMin(mult, 0.25);   // 25% of normal lots at 15%+ drawdown
      else if(dd_pct >= HWM_Drawdown_Step2)
         mult = MathMin(mult, 0.50);   // 50% of normal lots at 10%+ drawdown
      else if(dd_pct >= HWM_Drawdown_Step1)
         mult = MathMin(mult, 0.75);   // 75% of normal lots at 5%+ drawdown
   }

   // --- 2. Profit protection reduction ---
   // When account has grown significantly, protect those gains by trading smaller
   if(initial_equity > 0)
   {
      double gain_pct = ((equity - initial_equity) / initial_equity) * 100.0;

      if(gain_pct >= Profit_Protect_Level3)
         mult = MathMin(mult, 0.40);   // 40% of lots after 150%+ gain (doubled+)
      else if(gain_pct >= Profit_Protect_Level2)
         mult = MathMin(mult, 0.60);   // 60% of lots after 75%+ gain
      else if(gain_pct >= Profit_Protect_Level1)
         mult = MathMin(mult, 0.80);   // 80% of lots after 30%+ gain
   }

   // --- 3. Consecutive loss streak reduction ---
   // Each step of N losses reduces lots further (compounds with above)
   if(consecutive_losses >= Consec_Loss_Reduce_After)
   {
      int steps = (consecutive_losses / Consec_Loss_Reduce_After);
      double loss_mult = MathPow(Consec_Loss_Multiplier, steps);
      loss_mult = MathMax(loss_mult, 0.25); // Floor at 25% — never go below this
      mult = MathMin(mult, loss_mult);
   }

   // Hard floor: never less than 20% of intended lot
   // --- 4. Equity floor proximity reduction ---
   // The closer equity sits to the locked floor, the smaller the trades —
   // so a losing trade can't smash through the floor
   if(Use_Equity_Floor && equity_floor > 0 && equity > equity_floor)
   {
      double room_pct = ((equity - equity_floor) / equity) * 100.0;
      if(room_pct < 3.0)
         mult = MathMin(mult, 0.25);   // Very close to floor — minimum size
      else if(room_pct < 6.0)
         mult = MathMin(mult, 0.50);
      else if(room_pct < 10.0)
         mult = MathMin(mult, 0.75);
   }

   mult = MathMax(mult, 0.20);

   return mult;
}

//+------------------------------------------------------------------+
//| Close all positions belonging to this EA on this symbol          |
//+------------------------------------------------------------------+
void CloseAllEAPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!ticket) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long   pos_type = PositionGetInteger(POSITION_TYPE);
      double volume   = PositionGetDouble(POSITION_VOLUME);

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = _Symbol;
      req.position     = ticket;
      req.volume       = volume;
      req.deviation    = 20;
      req.magic        = Magic_Number;
      req.comment      = "FloorBreach_Close";
      req.type_filling = ORDER_FILLING_FOK;

      if(pos_type == POSITION_TYPE_BUY)
      {
         req.type  = ORDER_TYPE_SELL;
         req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      }
      else
      {
         req.type  = ORDER_TYPE_BUY;
         req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      }

      if(OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
         Print("Floor breach: closed position #", ticket);
      else
         Print("Floor breach: FAILED to close #", ticket, " retcode: ", res.retcode);
   }
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable for this instrument               |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable()
{
   if(Max_Spread_Points <= 0) return true;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > (long)Max_Spread_Points)
   {
      if(Show_Debug && tick_count % 100 == 0)
         Print("Spread rejected: ", spread, " pts (max: ", Max_Spread_Points, ")");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| ATR Trailing Stop Manager — runs every tick                     |
//| Sequence: Breakeven first → then trail once profit > trail_start|
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   // Get current ATR value for trail calculations
   double atr_buf[1];
   if(CopyBuffer(atr_entry, 0, 0, 1, atr_buf) < 1) return;
   double atr = atr_buf[0];
   if(atr <= 0) return;

   double breakeven_dist = atr * Breakeven_ATR;
   double trail_start    = atr * Trail_Start_ATR;
   double trail_gap      = atr * Trail_Distance_ATR;
   int    digits         = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point          = _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!ticket) continue;
      if(PositionGetInteger(POSITION_MAGIC) != Magic_Number) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double open_price  = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl  = PositionGetDouble(POSITION_SL);
      double current_tp  = PositionGetDouble(POSITION_TP);
      long   pos_type    = PositionGetInteger(POSITION_TYPE);
      double bid         = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask         = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double new_sl = current_sl;

      if(pos_type == POSITION_TYPE_BUY)
      {
         double profit_dist = bid - open_price;

         // Step 1: Breakeven — move SL to open price once profit >= breakeven_dist
         if(Use_Breakeven && profit_dist >= breakeven_dist)
         {
            double be_sl = NormalizeDouble(open_price, digits);
            if(be_sl > current_sl + point)
               new_sl = be_sl;
         }

         // Step 2: Trail — once profit >= trail_start, trail SL behind bid
         if(profit_dist >= trail_start)
         {
            double trail_sl = NormalizeDouble(bid - trail_gap, digits);
            if(trail_sl > new_sl + point)
               new_sl = trail_sl;
         }
      }
      else if(pos_type == POSITION_TYPE_SELL)
      {
         double profit_dist = open_price - ask;

         // Step 1: Breakeven
         if(Use_Breakeven && profit_dist >= breakeven_dist)
         {
            double be_sl = NormalizeDouble(open_price, digits);
            if(be_sl < current_sl - point || current_sl == 0)
               new_sl = be_sl;
         }

         // Step 2: Trail
         if(profit_dist >= trail_start)
         {
            double trail_sl = NormalizeDouble(ask + trail_gap, digits);
            if(trail_sl < new_sl - point || new_sl == 0)
               new_sl = trail_sl;
         }
      }

      // Only send a modify request if SL actually improved
      if(new_sl == current_sl) continue;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);
      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = _Symbol;
      req.position = ticket;
      req.sl       = new_sl;
      req.tp       = current_tp;

      bool ok = OrderSend(req, res);
      if(ok && res.retcode == TRADE_RETCODE_DONE)
      {
         if(Show_Debug)
            Print("Trail SL moved | Ticket: ", ticket,
                  " | Old SL: ", current_sl,
                  " | New SL: ", new_sl,
                  " | ATR: ", NormalizeDouble(atr, digits));
      }
      else if(Show_Debug)
      {
         Print("Trail SL modify failed | Ticket: ", ticket,
               " | Code: ", res.retcode);
      }
   }
}

//+------------------------------------------------------------------+
//| Reset daily counters at new day                                 |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   // Compare midnight-of-today against midnight-of-last-checked-day
   // Dividing by 86400 (seconds per day) strips the time component — fixes the "sometimes works" bug
   // where StructToTime kept the full timestamp and caused near-constant resets
   datetime midnight_today = (TimeCurrent() / 86400) * 86400;

   if(midnight_today != last_day_check)
   {
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      today_trades = 0;
      daily_drawdown_hit = false;
      daily_peak_equity = current_equity;      // New day: trailing peak resets to current equity
      daily_consecutive_losses = 0;            // Daily loss counter resets — all-time streak preserved
      last_day_check = midnight_today;

      if(Show_Debug)
      {
         Print("=== NEW TRADING DAY ===");
         Print("Daily peak reset to: $", DoubleToString(daily_peak_equity, 2),
               " | Drawdown limit: $", DoubleToString(daily_peak_equity * (1.0 - Max_Daily_Drawdown_Pct / 100.0), 2),
               " (", Max_Daily_Drawdown_Pct, "% = $", DoubleToString(daily_peak_equity * Max_Daily_Drawdown_Pct / 100.0, 2), ")");
         Print("Risk Mult: ", DoubleToString(GetSmartRiskMultiplier(), 2),
               " | Loss Streak: ", consecutive_losses,
               " | All-time HWM: $", DoubleToString(equity_high_water_mark, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| Check for trade signals                                         |
//+------------------------------------------------------------------+
void CheckForTrades()
{
   if(!Enable_Trading) return;

   if(CountPositions() >= Max_Open_Trades)
   {
      if(Show_Debug && tick_count % 300 == 0)
         Print("Max trades reached: ", CountPositions(), "/", Max_Open_Trades);
      return;
   }

   // Hard block — equity floor was breached, trading halted until EA restart
   if(floor_breached)
   {
      if(Show_Debug && tick_count % 500 == 0)
         Print("Equity floor breached — trading halted. Floor: $", DoubleToString(equity_floor, 2));
      return;
   }

   // Hard block — no new trades if today's trailing drawdown limit is breached
   if(daily_drawdown_hit)
   {
      if(Show_Debug && tick_count % 300 == 0)
         Print("Daily drawdown limit hit — no new trades today. Daily peak: $",
               DoubleToString(daily_peak_equity, 2));
      return;
   }

   // Hard block — stop trading for the day after 3 consecutive losses TODAY
   // Uses daily_consecutive_losses (resets each morning), not the all-time streak
   if(daily_consecutive_losses >= 3)
   {
      if(Show_Debug && tick_count % 300 == 0)
         Print("3 consecutive losses today — no more trades until tomorrow. Daily losses: ",
               daily_consecutive_losses, " | All-time streak: ", consecutive_losses);
      return;
   }

   if(TimeCurrent() - last_trade_time < 300)
   {
      if(Show_Debug && tick_count % 300 == 0) Print("Cooldown: waiting 5 min between trades...");
      return;
   }

   int signal = GetTradingSignal();
   if(signal != 0)
   {
      double smart_mult = GetSmartRiskMultiplier();
      if(Show_Debug)
         Print("Signal: ", signal > 0 ? "BUY" : "SELL",
               " | Smart Risk Mult: ", DoubleToString(smart_mult, 2),
               " (HWM DD + Profit Protect + Loss Streak combined)");
      EnterTrade(signal);
   }
}

//+------------------------------------------------------------------+
//| Get Trading Signal                                              |
//+------------------------------------------------------------------+
int GetTradingSignal()
{
   double ema1_t[3], ema2_t[3], ema3_t[3];
   double ema1_e[3], ema2_e[3], ema3_e[3];

   if(CopyBuffer(ema1_trend, 0, 0, 3, ema1_t) < 3) return 0;
   if(CopyBuffer(ema2_trend, 0, 0, 3, ema2_t) < 3) return 0;
   if(CopyBuffer(ema3_trend, 0, 0, 3, ema3_t) < 3) return 0;
   if(CopyBuffer(ema1_entry, 0, 0, 3, ema1_e) < 3) return 0;
   if(CopyBuffer(ema2_entry, 0, 0, 3, ema2_e) < 3) return 0;
   if(CopyBuffer(ema3_entry, 0, 0, 3, ema3_e) < 3) return 0;

   // Trend strength filter — skip ranging markets where EMA stacks whipsaw back and forth
   if(Min_ADX > 0)
   {
      double adx_buf[1];
      if(CopyBuffer(adx_trend, 0, 0, 1, adx_buf) < 1) return 0;
      if(adx_buf[0] < Min_ADX)
      {
         if(Show_Debug && tick_count % 300 == 0)
            Print("ADX ", DoubleToString(adx_buf[0], 1), " < ", Min_ADX, " — ranging market, no trades");
         return 0;
      }
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = (ask + bid) / 2.0;

   // Optional: use the last CLOSED candle's close instead of the live mid-tick price.
   // Live price flickers around the EMA constantly; a closed-bar confirmation
   // filters out signals that only existed for a single noisy tick.
   double confirm_price = mid;
   if(Require_Candle_Close_Confirm)
      confirm_price = iClose(_Symbol, Entry_Timeframe, 1);

   // BUY: Trend aligned up + entry fast EMA > medium EMA + price above fast EMA
   bool trend_bull = (ema1_t[2] > ema2_t[2] && ema2_t[2] > ema3_t[2]);
   bool entry_bull = (ema1_e[2] > ema2_e[2]) && (confirm_price > ema1_e[2]);
   if(Require_EMA_Slope) entry_bull = entry_bull && (ema1_e[2] > ema1_e[1]);

   if(trend_bull && entry_bull)
   {
      if(Show_Debug) Print("BUY SIGNAL: H4 trend up + M5 price above fast EMA");
      return 1;
   }

   // SELL: Trend aligned down + entry fast EMA < medium EMA + price below fast EMA
   bool trend_bear = (ema1_t[2] < ema2_t[2] && ema2_t[2] < ema3_t[2]);
   bool entry_bear = (ema1_e[2] < ema2_e[2]) && (confirm_price < ema1_e[2]);
   if(Require_EMA_Slope) entry_bear = entry_bear && (ema1_e[2] < ema1_e[1]);

   if(trend_bear && entry_bear)
   {
      if(Show_Debug) Print("SELL SIGNAL: H4 trend down + M5 price below fast EMA");
      return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Enter Trade with Smart Risk-Adjusted Lot Size                   |
//+------------------------------------------------------------------+
void EnterTrade(int direction)
{
   if(Show_Debug) Print("=== ATTEMPTING TRADE ENTRY ===");

   double atr_value = GetATRValue();
   if(atr_value <= 0)
   {
      if(Show_Debug) Print("Invalid ATR: ", atr_value);
      return;
   }

   ENUM_ORDER_TYPE order_type = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entry_price = (order_type == ORDER_TYPE_BUY) ?
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                        SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp;
   CalculateStopLossTakeProfit(order_type, entry_price, atr_value, sl, tp);

   // Get base lot size (equity-tiered or risk-based)
   double base_lot = CalculateBaseLotSize(entry_price, sl, order_type);
   if(base_lot <= 0)
   {
      if(Show_Debug) Print("Invalid base lot: ", base_lot);
      return;
   }

   // Apply smart risk multiplier
   double smart_mult = GetSmartRiskMultiplier();
   double adjusted_lot = base_lot * smart_mult;

   // Normalize to broker requirements
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   adjusted_lot = MathMax(min_lot, MathMin(max_lot, adjusted_lot));
   adjusted_lot = NormalizeDouble(adjusted_lot / step_lot, 0) * step_lot;

   if(adjusted_lot < min_lot)
   {
      if(Show_Debug) Print("Lot below minimum after smart scaling — skipping trade");
      return;
   }

   if(Show_Debug)
   {
      Print("--- Trade Plan ---");
      Print("Direction: ", EnumToString(order_type));
      Print("Entry: ", entry_price, " | SL: ", sl, " | TP: ", tp);
      Print("Base Lot: ", base_lot, " | Smart Mult: ", DoubleToString(smart_mult, 2),
            " | Final Lot: ", adjusted_lot);
      Print("Equity: $", AccountInfoDouble(ACCOUNT_EQUITY),
            " | HWM: $", DoubleToString(equity_high_water_mark, 2),
            " | Loss Streak: ", consecutive_losses);
   }

   if(SendOrder(order_type, adjusted_lot, entry_price, sl, tp))
   {
      last_trade_time = TimeCurrent();
      today_trades++;

      double dd_limit_usd = daily_peak_equity * Max_Daily_Drawdown_Pct / 100.0;
      Print("=== TRADE EXECUTED ===");
      Print(EnumToString(order_type), " | Lots: ", adjusted_lot,
            " (", DoubleToString(smart_mult * 100.0, 0), "% of base)");
      Print("Entry: ", entry_price, " | SL: ", sl, " | TP: ", tp);
      Print("Today: ", today_trades, " trades | Daily peak: $", DoubleToString(daily_peak_equity, 2),
            " | Max loss today: $", DoubleToString(dd_limit_usd, 2));
   }
   else
   {
      Print("=== TRADE EXECUTION FAILED ===");
   }
}

//+------------------------------------------------------------------+
//| Calculate base lot size (before smart multiplier)               |
//+------------------------------------------------------------------+
double CalculateBaseLotSize(double entry_price, double sl_price, ENUM_ORDER_TYPE order_type)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double base_lot = 0.01;

   if(Use_Dynamic_Lots)
   {
      // Linear equity-growth lot sizing: for every $Equity_Step_USD gained
      // above initial capital, add Lot_Increase_Per_Step lots.
      // e.g. start $1000 @ 0.01 lot -> equity $1300 (+$300) -> 0.01 + 3*0.03 = 0.10 lot
      double profit_growth = MathMax(0.0, equity - initial_equity);
      int steps = (Equity_Step_USD > 0) ? (int)MathFloor(profit_growth / Equity_Step_USD) : 0;
      base_lot = Starting_Lot_Size + (steps * Lot_Increase_Per_Step);

      base_lot *= Lot_Multiplier;
   }
   else if(Risk_Per_Trade > 0)
   {
      // Risk-based position sizing
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_amt  = balance * Risk_Per_Trade / 100.0;

      double sl_points = 0;
      if(order_type == ORDER_TYPE_BUY)
         sl_points = (entry_price - sl_price) / _Point;
      else
         sl_points = (sl_price - entry_price) / _Point;

      double tick_val  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tick_val > 0 && tick_size > 0 && sl_points > 0)
      {
         double point_value = tick_val / (tick_size / _Point);
         base_lot = risk_amt / (sl_points * point_value);
      }
   }

   return base_lot;
}

//+------------------------------------------------------------------+
//| Calculate Stop Loss and Take Profit                             |
//+------------------------------------------------------------------+
void CalculateStopLossTakeProfit(ENUM_ORDER_TYPE order_type, double entry_price,
                                  double atr_value, double &sl, double &tp)
{
   double stop_dist = atr_value * ATR_Multiplier;

   if(order_type == ORDER_TYPE_BUY)
   {
      sl = entry_price - stop_dist;
      tp = entry_price + (stop_dist * Risk_Reward_Ratio);
   }
   else
   {
      sl = entry_price + stop_dist;
      tp = entry_price - (stop_dist * Risk_Reward_Ratio);
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                   |
//+------------------------------------------------------------------+
double GetATRValue()
{
   double buf[1];
   if(CopyBuffer(atr_entry, 0, 0, 1, buf) < 1) return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Send Order                                                      |
//+------------------------------------------------------------------+
bool SendOrder(ENUM_ORDER_TYPE order_type, double volume, double price, double sl, double tp)
{
   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = volume;
   request.type         = order_type;
   request.price        = price;
   request.sl           = sl;
   request.tp           = tp;
   request.deviation    = 10;
   request.magic        = Magic_Number;
   request.comment      = "SmartRisk_Pro_v3";
   request.type_filling = ORDER_FILLING_FOK;

   bool ok = OrderSend(request, result);

   if(ok && result.retcode == TRADE_RETCODE_DONE) return true;

   if(ok)
      Print("Order rejected - Code: ", result.retcode, " | ", GetRetcodeDescription(result.retcode));
   else
      Print("OrderSend error: ", GetLastError());

   return false;
}

//+------------------------------------------------------------------+
//| Retcode descriptions                                            |
//+------------------------------------------------------------------+
string GetRetcodeDescription(int retcode)
{
   switch(retcode)
   {
      case 10004: return "Requote";
      case 10006: return "Request rejected";
      case 10007: return "Order canceled";
      case 10008: return "Invalid volume";
      case 10009: return "Order executed";
      case 10010: return "Price changed";
      case 10011: return "Invalid stops";
      case 10012: return "Invalid trade volume";
      case 10013: return "Market closed";
      case 10014: return "Trade disabled";
      case 10015: return "Not enough money";
      case 10016: return "Price changed";
      default:    return "Unknown: " + IntegerToString(retcode);
   }
}

//+------------------------------------------------------------------+
//| Count open positions for this EA + symbol                      |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetTicket(i))
         if(PositionGetInteger(POSITION_MAGIC) == Magic_Number &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if trading is permitted                                   |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      if(Show_Debug && tick_count % 500 == 0)
         Print("AutoTrading disabled — click the AutoTrading button");
      return false;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      if(Show_Debug) Print("EA trading not allowed in properties");
      return false;
   }
   if(Filter_By_Time && !IsWithinTradingHours())
   {
      if(Show_Debug && tick_count % 500 == 0) Print("Outside trading hours");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Trading hours check                                             |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime now;
   TimeCurrent(now);
   // Simple hour window in server time — e.g. 7 to 20 skips the Asian session
   // (backtest showed most losing entries clustered at 0:00-2:00 server time)
   if(Trading_Start_Hour <= Trading_End_Hour)
      return (now.hour >= Trading_Start_Hour && now.hour < Trading_End_Hour);
   // Overnight window support (e.g. start 22, end 6)
   return (now.hour >= Trading_Start_Hour || now.hour < Trading_End_Hour);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   int handles[] = {ema1_trend, ema2_trend, ema3_trend, atr_trend,
                    ema1_entry, ema2_entry, ema3_entry, atr_entry, adx_trend};
   for(int i = 0; i < ArraySize(handles); i++)
      if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);

   double final_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double total_pnl    = final_equity - initial_equity;
   double total_pct    = (initial_equity > 0) ? (total_pnl / initial_equity) * 100.0 : 0.0;

   Print("=== SMART RISK EA SHUTDOWN ===");
   Print("Ticks processed: ", tick_count);
   Print("Trades closed: ", total_trades_closed);
   Print("Final P&L: $", DoubleToString(total_pnl, 2), " (", DoubleToString(total_pct, 1), "%)");
   Print("Peak equity (HWM): $", DoubleToString(equity_high_water_mark, 2));
}
