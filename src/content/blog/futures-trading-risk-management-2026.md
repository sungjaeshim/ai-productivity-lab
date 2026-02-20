---
title: "Risk Management in Futures Trading: 7 Rules I Follow to Protect Capital"
description: "Practical risk management strategies for NQ and ES futures traders. Learn position sizing, stop-loss placement, and psychological techniques to survive volatile markets."
pubDate: 2026-02-21
author: "AI Productivity Lab"
heroImage: "https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&h=630&fit=crop"
category: "Trading"
tags: ["risk management", "futures trading", "NQ", "ES", "position sizing", "trading psychology"]
---

# Risk Management in Futures Trading: 7 Rules I Follow to Protect Capital

After years of trading NQ (Nasdaq) and ES (S&P 500) futures, I've learned one truth: risk management is more important than prediction accuracy. You can be right 70% of the time and still lose money if your losses are bigger than your wins. This guide shares the exact rules I follow every trading day.

## The Hardest Lesson I Learned

In my first year of futures trading, I turned $10,000 into $3,000 in three months. My analysis was decent—I called market direction correctly about 60% of the time. But I was losing $500 on bad trades and making $200 on good ones.

The math is brutal: Win 6 trades at $200 = $1,200. Lose 4 trades at $500 = -$2,000. Net result: -$800 despite being right more often than wrong.

This taught me that **how you manage losses matters more than how often you're right.**

## Rule 1: Never Risk More Than 2% Per Trade

This is the foundation. If you have a $50,000 account, your maximum risk per trade is $1,000.

**Why this matters:**

- 10 consecutive losses at 2% = -18.3% drawdown (survivable)
- 10 consecutive losses at 10% = -65.1% drawdown (devastating)
- 10 consecutive losses at 20% = -89.3% drawdown (recovery nearly impossible)

**How to calculate position size:**

```
Position Size = (Account × Risk %) / (Entry - Stop Loss)

Example:
Account: $50,000
Risk: 2% = $1,000
NQ Entry: 24,500
Stop Loss: 24,400
Risk per contract: 100 points × $20 = $2,000

Max Contracts = $1,000 / $2,000 = 0.5 contracts

Result: Trade 1 mini contract or use options/spreads
```

## Rule 2: Set Stop-Losses Before Entry

I never enter a trade without knowing exactly where I'll exit if wrong.

**Common stop-loss placement methods:**

### ATR-Based Stops
- Average True Range measures volatility
- Stop = Entry - (ATR × multiplier)
- For NQ, I use 1.5× ATR on 15-minute charts

### Structure-Based Stops
- Below recent swing low (for longs)
- Above recent swing high (for shorts)
- Adjust based on market structure

### Percentage Stops
- Simple but less adaptive
- Works for less experienced traders
- Typically 0.5-1% for index futures

**My preference:** ATR-based stops during normal volatility, structure-based stops during high volatility events.

## Rule 3: Risk-Reward Ratio Minimum 1:2

If I'm risking $500, I need at least $1,000 potential profit.

**The math works like this:**

| Win Rate | Risk:Reward | Break-Even Outcome |
|----------|-------------|-------------------|
| 50% | 1:1 | Break even (minus fees) |
| 33% | 1:2 | Break even |
| 40% | 1:2 | Profitable |
| 50% | 1:2 | Solidly profitable |

**Practical example with NQ:**

```
Long at 24,500
Stop at 24,400 (100 points risk = $2,000)
Target at 24,700 (200 points reward = $4,000)

Risk-Reward = 1:2

You only need to be right 33% of the time to break even.
At 45% accuracy, you're making strong profits.
```

## Rule 4: Maximum Daily Loss Limit

I set a hard stop for each trading day. When I hit it, I walk away.

**My current limits:**
- Daily max loss: 3% of account
- Consecutive losing trades: 3 max, then 1-hour break
- Weekly max loss: 6% of account (then stop trading for the week)

**Why this matters:**

Losing streaks trigger emotional trading. You start thinking, "I just need one big win to get it back." That's how small losses become account-ending losses.

The daily limit forces you to stop before tilt trading destroys your account.

## Rule 5: Size Down During Drawdowns

When my account drops 10% from its peak, I reduce position size by 50%.

**The reasoning:**

- Drawdowns often indicate either market conditions don't suit my strategy OR I'm trading poorly
- Either way, reducing size limits damage while I figure out which
- It's psychological protection—smaller positions mean less stress

**My sizing tiers:**

| Account vs. Peak | Position Size |
|------------------|---------------|
| Peak (0% drawdown) | 100% of normal |
| -5% drawdown | 75% of normal |
| -10% drawdown | 50% of normal |
| -15% drawdown | 25% of normal |
| -20% drawdown | Pause trading, review |

## Rule 6: No Trading During Major News Events

I close positions or reduce size before these events:

- FOMC announcements
- CPI/employment reports
- Fed Chair speeches
- Earnings from mega-cap tech (for NQ specifically)

**The problem with news trading:**

- Spreads widen dramatically
- Slippage can triple your expected loss
- Moves are often counterintuitive
- Your stop-loss might as well not exist

**My approach:**

I'd rather miss the move than get stopped out in the chaos. There's always another trade.

## Rule 7: Track Every Trade and Review Weekly

I maintain a trading journal with specific metrics:

**What I track:**

| Metric | Why It Matters |
|--------|---------------|
| Entry/Exit prices | Calculate actual P&L |
| Position size | Verify risk management |
| Stop-loss placement | Check if stops were appropriate |
| Win/Loss | Calculate win rate |
| Risk-Reward actual | Compare to plan |
| Market conditions | Identify favorable environments |
| Emotional state | Catch tilt early |

**Weekly review questions:**

1. Did I follow my risk rules? (Yes/No for each)
2. Which setups worked best?
3. What patterns am I seeing in losses?
4. Is my win rate and risk-reward sustainable?
5. Any changes needed to my approach?

**Tools I use:**
- Spreadsheets for detailed tracking
- Charts with entry/exit annotations
- Weekly P&L curves to spot drawdowns early

## Common Risk Management Mistakes

### Mistake 1: Moving Stop-Losses
"I'll just give it a bit more room." No. Your stop is your stop. If it keeps getting hit, your entries are wrong, not your stops.

### Mistake 2: Averaging Down
Adding to losing positions feels smart when it works. But when it doesn't, small losses become catastrophic. I never add to a losing trade.

### Mistake 3: Overtrading After Losses
Trying to "make back" losses quickly. This leads to forced trades, ignored rules, and deeper holes. My daily loss limit prevents this.

### Mistake 4: Ignoring Correlations
If you're long NQ, ES, and QQQ, you're not diversified. When tech sells off, everything drops. I limit correlated exposure.

## Position Sizing Calculator

Use this simple formula:

```
Step 1: Account Balance × 2% = Max Risk in Dollars
Step 2: Entry Price - Stop Price = Risk per Contract (in points)
Step 3: Risk per Contract × Point Value = Dollar Risk per Contract
Step 4: Max Risk / Dollar Risk per Contract = Number of Contracts

Example for NQ:
Account: $100,000
Max Risk: $2,000
Entry: 24,600, Stop: 24,450
Risk: 150 points
Point Value: $20
Risk per Contract: $3,000

Contracts = $2,000 / $3,000 = 0.67

Answer: 0 contracts (risk exceeds 2%). Either widen stop or skip trade.
```

## Psychological Techniques

Risk management is psychological as much as mathematical.

### Pre-Trade Checklist
Before every trade, I verify:
- [ ] Position size is within 2% risk
- [ ] Stop-loss is set
- [ ] Target meets 1:2 risk-reward
- [ ] Not within 30 minutes of major news
- [ ] Not already at daily loss limit

If any box unchecked, no trade.

### The "Sleep Test"
If I can't sleep comfortably with this position, it's too big. Reduce size until you can.

### Post-Trade Journaling
Write down emotions immediately after closing:
- Did I follow my rules?
- Was I calm or anxious?
- What would I do differently?

This builds self-awareness over time.

## When to Break the Rules

I follow these rules 95% of the time. Exceptions:

1. **Prop firm evaluation** - Different risk parameters required
2. **Systematic strategy** - Rules built into the system
3. **Account growth** - May increase risk % as account grows and proves strategy works

But these are deliberate decisions, not emotional reactions.

## Summary: The 7 Rules

| # | Rule | Quick Check |
|---|------|-------------|
| 1 | Max 2% risk per trade | Calculate before every entry |
| 2 | Set stop before entry | No stop, no trade |
| 3 | Minimum 1:2 risk-reward | Target must be 2× stop distance |
| 4 | Daily loss limit | Hit it, walk away |
| 5 | Size down in drawdowns | 10% down = 50% size |
| 6 | Avoid major news | Close or reduce before events |
| 7 | Track and review | Journal every trade |

## Getting Started

If you're new to futures or struggling with consistency:

1. **Paper trade first** - Test your risk management with fake money
2. **Start small** - 1 contract, 1% risk until profitable for 3 months
3. **Focus on rules** - Profitability comes from following rules, not prediction
4. **Review weekly** - Patterns emerge over time

**The goal isn't to be right. The goal is to survive long enough to be profitable.**

---

*These rules come from personal experience trading NQ and ES futures. They may not suit all trading styles or risk tolerances. Futures trading involves substantial risk of loss. This is not financial advice.*

## FAQ

**Q: What if 2% risk means I can't trade 1 contract?**
A: Trade micro futures (MNQ, MES) or paper trade until your account grows. Never exceed risk limits to trade.

**Q: Should I use mental stops or hard stops?**
A: Hard stops always. Mental stops get moved when emotions kick in.

**Q: What about trailing stops?**
A: Use them to lock in profits, but only after price moves in your favor. Never trail a stop to give a trade "more room."

**Q: How do I handle gap openings against my position?**
A: This is why position sizing matters. If a gap exceeds your stop, your 2% risk becomes maybe 3-4%. Survivable if you sized correctly.
