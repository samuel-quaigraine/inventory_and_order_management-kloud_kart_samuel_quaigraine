# Memo to Nana

**From:** Samuel Quaigraine
**Date:** 2026-11-27
**Subject:** Overselling is fixed, the Monday report takes one second, and no new server is needed

## What I found

**Overselling comes from how orders are placed, not from missing triggers.** The system reads the stock, checks it, then writes a new number. When two customers buy at the same moment, both read the same number and both are sold the item. I recreated this: 400 customers bought a product with 50 units and **all 400 were told "order placed"**. The stock even ended at 48, so most oversells leave no trace. A rule that blocks negative stock would not have caught it.

**Adwoa's report was slow and also wrong.** It worked customer by customer, month by month, about 7.5 hours of work in total. And because "completed" is written 15 different ways, it saw only 1 in 5 completed orders: **85 of its top-100 customers were the wrong people.**

The records had other problems: orders and stock movements that point at customers or products that don't exist, the same order line saved twice, a few impossible quantities (9,999 units), and stock changes nobody explained ("??", "see WhatsApp msg").

## What I built

| What you asked for | Status | Evidence |
|---|---|---|
| No overselling, instant "out of stock" | Done | 400 buyers on 50 units: exactly 50 sold, 350 told "out of stock" in 5 seconds |
| Monday report in seconds | Done | About 1 second (was about 7.5 hours); now counts every completed order |
| Low-stock rollup through the categories | Done | Under a tenth of a second, at any depth; a looped category no longer hides products |
| A record of every stock movement | Done | Every change is recorded automatically with the reason, the order and who; records can't be edited |
| Extra: cancelling gives stock back | Done | A cancelled order returns exactly what it took, and the return is recorded |

No bad record was deleted. Each one was set aside with a reason, so it can be checked or restored.

## What I recommend

1. **Turn off the old way of placing orders** and use only the new one. The fix only protects orders that go through it.
2. **Confirm three business rules** I had to choose: spend counts completed and shipped orders only; "the last 12 months" ends on the last day of the data; low stock means 5 units or fewer.
3. **Tell us where the stray records came from** (customer numbers starting 999…). They look like test data. If they are real, they can be restored.
4. **Decide what to do with 533 customers who share an email** with someone of the same name. I kept them separate: their phone numbers differ, so they may be different people.
5. **No new server.** The slow report was a design problem, not a hardware problem.

## What I could not stand behind

- **Past oversells can't be counted.** The old stock records have no starting balance, so I treated today's stock figures as correct.
- **Some order totals include discounts or fees that are recorded nowhere** (often exactly 10%, 25% or 50%). I report what the customer paid, but I can't explain the rule behind it.
- **24 orders are dated after the data ends,** some in the future. They could be a clock error. I set them aside rather than guess.
- **The data shows about 1,200 orders a day at its busiest,** not the 4,000 I was told. The results should hold at 4,000, but I could only test what I had.
