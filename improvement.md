# Improvement beyond the brief: cancelling an order gives its stock back

## The problem it solves

The new `place_order` takes stock off the shelf the moment an order is placed. That fixes overselling, but it creates a new problem the brief did not mention: **when a customer cancels, nothing puts the stock back.** Each cancellation would leave units "sold" that are still in the warehouse. Over time the shop would show items as out of stock that it actually has, and lose sales because of it. Cancellations are common: 12,697 orders in the extract were cancelled.

There is a trap in the old data too. Before the fix, cancelled, pending and refunded orders never took stock (data_findings.md, Reconciliation). A careless "add the quantity back" would hand back stock those old orders never took.

## What I built

`cancel_order(order_id)` in `sql/09_improvement.sql`:

1. Locks the order, so two cancellations of the same order can't both return stock.
2. Refuses anything that isn't `completed` or `pending`, with a clear message (for example "Order cannot be cancelled: it is cancelled").
3. Returns **exactly what the stock log says this order took**, no more. Old orders that never took stock get nothing back by mistake. This works because the audit trail now links every sale to its order (ADR-002).
4. Writes the returned stock to the log as a `return`, linked to the order, then marks the order `cancelled`. All in one step: stock and status change together or not at all.

Tested: place an order for 2 units (stock 90 → 88), cancel it (88 → 90, log shows `sale −2` and `return +2` for the same order), cancel again (refused: already cancelled).

## What it is worth to Nana

- Stock figures stay true after cancellations, so the shop does not hide items it has.
- Every return is in the audit trail with the order it belongs to, so a customer dispute about a cancelled order can be checked in one place.
- It closes a gap that the overselling fix itself would have opened, which matters more during flash sales, when many orders are placed and some are cancelled quickly.

## What it cost

- About 40 lines of SQL and one test session.
- The shop's cancel button must call `cancel_order` instead of only changing the order's status.
- Not covered: refunds of shipped orders (the goods have left the building; stock should only come back when they are physically returned). That is a separate, deliberate step.
