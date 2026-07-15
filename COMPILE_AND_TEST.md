# Compile + Backtest v3.45 — Exact Steps

This is the one remaining step. Nothing further can be verified without it —
I have no MT5 installed in my environment, so this has to happen on your machine.

## 1. Compile (confirms zero syntax errors) — ~30 seconds

1. Copy `Professional_Trend_EA_SmartRisk.mq5` into your MT5 data folder:
   `File → Open Data Folder → MQL5 → Experts`
2. In MT5, open **Navigator** (Ctrl+N), find the EA under *Expert Advisors*,
   double-click to open it in MetaEditor.
3. Press **F7** (or the Compile button).
4. Look at the bottom **Toolbox** panel — you want to see:
   ```
   0 errors, 0 warnings
   ```
   If you see errors, **copy the exact error text and send it to me** — that's
   a real compile bug I need to fix, and I can't see it without your paste.

## 2. Run one backtest — ~2 minutes

1. Open **Strategy Tester** (Ctrl+R).
2. Symbol: **XAUUSD**. Period: **M5** (or your preference).
3. Date range: any 1-2 week window is enough for this check — doesn't need
   to be long.
4. Model: **Every tick based on real ticks** if available (most accurate),
   otherwise **Every tick**.
5. In the **Inputs** tab, leave everything at default — this tests the exact
   rules we just validated (3-loss daily stop, 20% margin cap, unlimited
   win streak, equity floor).
6. Click **Start**.

## 3. What to send back

After it finishes, I need **one of these two things** (whichever applies):

**If it traded normally:** open the **Journal** tab in the Strategy Tester
results, and copy/screenshot a chunk of the log — ideally including a few
`REJECTED (reason):` lines and a `=== TRADE EXECUTED ===` line. This
confirms the rules are firing as coded and tells us the real signal frequency.

**If it went flat/quiet at some point:** scroll the Journal to that exact
time period and copy/screenshot the log lines right around when it stopped.
With v3.44's logging, it will say in plain words why — `no-signal`,
`daily-drawdown`, `3-loss-daily-stop`, `margin-cap`, etc. That single log
excerpt answers the open question definitively.

## Why this specific step can't be skipped

Everything up to this point — the code, the design, and the
`tests/validate_ea_rules.py` logic proof — establishes that the rules are
*written correctly*. It cannot establish that they *behave correctly inside
MetaTrader's execution engine* (order fills, indicator warm-up, real tick
timing). Those two things are different, and only a real compile + backtest
closes the gap. This isn't a formality — it's the actual test.
