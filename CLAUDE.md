# Project: Smart Risk Trading EA (MetaTrader 5)

## What this is
An MQL5 Expert Advisor for the user (srithesigan@gmail.com) — a multi-timeframe
trend-following EA for **XAUUSD (Gold) and major indices** on a **standard
(non-ECN) account**. Main file: `Professional_Trend_EA_SmartRisk.mq5`.

The user's original problem: the EA was profitable but would double the account
and then give all the gains back by over-risking. All work since has been about
money management, not the entry strategy.

## Current version: v3.44 (HEAD)
**v3.44 additions (per user's /goal + council decision):**
- 20% margin cap per trade: `Max_Margin_Pct_Per_Trade` input, checked via
  `OrderCalcMargin()` in `EnterTrade()`. If required margin exceeds 20% of
  current equity, lot is scaled down proportionally (re-normalized to lot
  step); trade skipped only if even min lot still exceeds the cap.
- Full rejection-reason logging: every skip path now prints a consistent
  `"REJECTED (reason):"` line (max-trades, daily-drawdown, 3-loss-stop,
  cooldown, no-signal, spread, lot-too-small, margin-cap). This was the
  council's call — diagnose the "still same, low frequency" complaint from
  real log evidence before writing another speculative fix. User confirmed
  they re-tested v3.43 and the flatline persisted mid-period (not
  end-of-test), so a real cause remains to be pinned down from this logging
  — waiting on user to send a log excerpt from the flat period.
- /goal active this session: "trade continues indefinitely on wins, only
  3-loss daily stop pauses trading (already implemented), 20% margin cap
  per trade (implemented this version)." Session has a Stop-hook goal — do
  not end turns without progressing this until satisfied/cleared.

## Previous version: v3.43
**v3.43 fix — critical:** v3.40's equity floor breach set `floor_breached=true`
permanently, and `CheckForTrades()` hard-blocked all new entries while that flag
was set, requiring a manual EA restart to clear. User reported a backtest chart
that spiked then went dead flat for the rest of the run — this was the cause
(one floor touch = trading dead forever). Fixed: floor breach still closes all
EA positions to lock the gain, but `floor_breached` is now log-only; trading
resumes immediately, protected by the existing floor-proximity risk shrink.
User's explicit rule confirmed: the ONLY thing that should ever pause trading
is 3 consecutive losses in a day, which already auto-resets at midnight. Win
streaks are and always were uncapped (no stop logic was ever tied to wins).

## Previous version: v3.42
**v3.42 additions (on top of v3.41):**
- Lot sizing rule replaced per explicit user spec: for every $100 (`Equity_Step_USD`)
  of profit growth above initial capital, add 0.03 lots (`Lot_Increase_Per_Step`).
  Starts at `Starting_Lot_Size` (0.01). Formula: `base_lot = Starting_Lot_Size +
  floor((equity - initial_equity)/Equity_Step_USD) * Lot_Increase_Per_Step`.
  Replaces the old fixed equity-tier table. Naturally shrinks back down in
  drawdown since it reads live equity every trade.
- Two OPTIONAL entry-accuracy filters added, both default **false** (v3.10
  behaviour unchanged unless user opts in): `Require_Candle_Close_Confirm`
  (use last closed bar's close vs EMA instead of live mid-tick price) and
  `Require_EMA_Slope` (fast EMA must be actively rising/falling, not flat).
- Equity floor logic itself is UNCHANGED from v3.41 — user re-confirmed the
  continuous 10%-below-peak trail is correct, no edit was needed there.


**Engine:** v3.10 aggressive defaults (the user's preferred trading behaviour):
24h trading (time filter OFF), ADX filter OFF (input exists, default 0),
M1-bar signal checks, 5-min cooldown, trailing stop BE=1.0 ATR /
start=1.5 ATR / distance=1.0 ATR.

**Protection layers (all active by default):**
1. **Equity floor (v3.41 rule — user was very specific):** floor trails
   **10% below peak equity, continuously** (NOT stepped). Arms once equity
   gains 10% from initial capital; never sits below initial capital; ratchets
   up only. On breach: close all EA positions + halt until EA restart.
2. **5% trailing daily drawdown:** measured from TODAY's peak equity (rises
   with intraday profit). Blocks new trades for the day when hit.
3. **3 consecutive losses in one day** = stop trading until tomorrow
   (daily counter `daily_consecutive_losses`, separate from the all-time
   streak used for lot scaling — mixing these caused the v3.21 single-trade bug).
4. Smart risk multiplier (min of): HWM drawdown steps (75/50/25% at 5/10/15% DD),
   profit-protection steps (80/60/40% at +30/75/150%), loss-streak decay
   (0.70^steps after every 2 losses), floor-proximity (75/50/25% when equity
   is within 10/6/3% of the floor). Hard floor 0.20.
5. Spread filter: max 50 points (Gold on standard account).

## Version history (git log, oldest first)
- v3.0  `6f0c352` Smart risk layers (HWM, profit protect, loss streak, spread filter)
- v3.10 `0a26401` ATR trailing stop + breakeven — **user's favourite engine**
- v3.20 `abb9cbf` Trailing daily DD; fixed daily-reset bug (StructToTime kept
  full timestamp → counters reset nearly every tick = "sometimes works" bug;
  fix: compare `(TimeCurrent()/86400)*86400` midnights)
- v3.21/22/23 daily limits tuning + separate daily/all-time loss counters
- v3.30 `20e57ff` session filter + ADX + wider trail (defaults later reverted)
- v3.40 `c2bb102` equity floor (stepped — WRONG interpretation)
- v3.41 `f60ead2` floor corrected to continuous 10%-below-peak trail

## Backtest evidence (user-run, MT5, XAUUSD, $1000 start)
- v3.10 engine, Apr–Jun 2026: **−29%**, PF 0.83, 46.6% max DD, 391 trades,
  47.6% win, avg win $7.66 < avg loss $8.38 (75% history quality)
- v3.10 engine, Jan 2026: **+140%** ($1000→$2400) with an early dip to ~$700 —
  this curve is why the user prefers the v3.10 engine
- v3.30, May–Jun 2026: **+21%**, PF 1.18, 57% win, 17.1% max DD, 295 trades,
  100% history quality (shorts 282 @ 57.8% win; longs only 13 @ 38.5%)
- Interpretation given to user: v3.10 engine has big upside AND big downside;
  floor + daily DD are meant to cap the downside. v3.41 itself is UNTESTED —
  told user (CEO-mode answer) not to go live until it's backtested on both
  the Jan and Apr–Jun windows, then 12 months, then 2–4 weeks demo.

## Known issues / environment
- **Push to GitHub is blocked**: git push → 403 via local proxy; GitHub MCP
  write calls → "Resource not accessible by integration" (read works; the
  Claude GitHub App has read-only Contents permission). Repo was empty until
  the user created a README on `main`. All work exists only as local commits
  on branch `claude/ea-risk-money-management-02it87` + files sent in chat.
- Broker uses ORDER_FILLING_FOK; some brokers need IOC/RETURN (documented in guide).
- User's broker server timezone unknown — the 00:00–02:00 entry cluster in
  backtests suggests server midnight ≠ session assumptions; ask before tuning
  time filters.

## Other deliverables
- User guide published as Claude artifact ("Professional Trend EA — Smart Risk
  Edition Guide", favicon 📈, scratchpad file `ea_guide.html`) — covers v3.10
  parameters; NOT yet updated for floor/daily-DD features (PDF was requested;
  user prints artifact to PDF).

## User preferences
- Don't change the entry strategy/settings much — money management only.
- Wants aggressive growth with locked-in profits (floor), not conservative filters.
- Likes tables and concrete $ examples when explaining risk rules.
