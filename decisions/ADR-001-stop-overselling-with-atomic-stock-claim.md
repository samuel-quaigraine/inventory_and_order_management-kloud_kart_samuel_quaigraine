# ADR-001: Stop overselling by claiming stock atomically inside place_order

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Samuel Quaigraine

## Context

When two customers try to buy the last unit at the same moment, both are sold it. The data shows 14 products below zero stock (F-02), and a copy of today's ordering logic sold **400 units of a product that had 50** under the race test (`sql/benchmarks/results/race_test_naive.txt`). The stock even ended at 48, not negative, so most oversells leave no trace. The cause is that the app *reads* the stock, *checks* it, then *writes* a new number: between the read and the write, other buyers read the same old number. Nana was told triggers would fix this. Flash sales of ~400 orders in 10 seconds on one product are coming.

## Decision

Orders are placed through one database function, `place_order`, which checks and takes stock in a single statement (`UPDATE … SET stock = stock - qty WHERE stock >= qty`). If no row changes, the buyer gets an instant "Out of stock". A `stock >= 0` rule sits underneath as a safety net.

## Alternatives considered

### Alternative A: A trigger or a `stock >= 0` rule alone

- **How it would work:** Keep the app's read-check-write, and let the database refuse a negative stock value.
- **Why it is attractive:** It is what Nana was sold; no change to how orders are placed.
- **Why rejected:** The app writes "what I read minus one", so 400 buyers all write 49: the number never goes negative and the rule never fires. Where it does fire, the buyer gets an error, not a clear "out of stock".

### Alternative B: Lock the product row first (`SELECT … FOR UPDATE`), then check and write

- **How it would work:** Each buyer locks the product, reads, checks, writes, and unlocks.
- **Why it is attractive:** Correct, and a common pattern.
- **Why rejected:** Two statements where one does the same job; more code and more chances to get it wrong. The single `UPDATE` takes the same lock automatically.

### Alternative C: Strictest isolation level (SERIALIZABLE)

- **How it would work:** The database detects conflicting buyers and cancels all but one.
- **Why it is attractive:** No manual locking.
- **Why rejected:** Cancelled buyers get an error and must retry. With 400 buyers that means many retries, and the test forbids errors reaching the customer.

## Consequences

- **What this buys:** Exactly one buyer gets the last unit, every time. `race_test.py` passes all four tests: 400 buyers on 50 units → exactly 50 sold, 350 told "out of stock", no errors, about 5 seconds.
- **What this costs:** The shop must place orders through `place_order`, not write to the tables directly. Buyers of the same product wait in line for a few milliseconds each.
- **What it costs the client if I am wrong:** Overselling continues: refunds, angry customers and a stock count nobody trusts.
- **What would make me revisit this:** One product needing thousands of orders per second, or one order needing several products at once (the function handles one product per call).

## What this survives

- **The flash sale:** 400 simultaneous buyers on one product, tested. Buyers queue on that one product's row only; other products are unaffected.
- **A buyer asking for more than exists:** refused cleanly, stock untouched (Test 3).
- **A crash halfway through:** the stock change, order and log row are one transaction, so all of them happen or none do.
- **Someone bypassing the function:** the `stock >= 0` rule still blocks negative stock, and the audit trail (ADR-002) records the change.
