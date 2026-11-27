# ADR-002: Route every stock change through the inventory log

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Samuel Quaigraine

## Context

Nana wants an audit trail of every stock movement. Today the log is written by whoever remembers to: 144 products had stock that did not match their log (F-09), 2,911 products had no opening balance, 216 manual corrections say "??", "see WhatsApp msg" or nothing (F-10), and no sale is linked to the order that caused it. `race_test.py` also adds products with stock already set and no log row, and deletes its own log rows afterwards, so the design must allow both.

## Decision

The database writes the log itself. A trigger on `products` adds a log row whenever stock changes, from any source, with the reason, the order and the database user. Log rows cannot be edited (a mistake is fixed with a new correction row); deleted rows are copied to `inventory_log_archive`. Past sales were linked to their orders by product and time.

## Alternatives considered

### Alternative A: Each piece of code writes its own log row

- **How it would work:** `place_order`, restocks and corrections each insert a log row next to their stock change.
- **Why it is attractive:** Simple and explicit.
- **Why rejected:** That is today's design, and it is how the log drifted. Any code that forgets, or any manual `UPDATE`, leaves no trace.

### Alternative B: Calculate stock from the log instead of storing it

- **How it would work:** Drop `stock_quantity`; stock = the sum of the log.
- **Why it is attractive:** Stock and log can never disagree.
- **Why rejected:** Every stock check would add up a product's whole history, which is slow under a flash sale, and `race_test.py` reads and writes `stock_quantity` directly.

### Alternative C: Block all deletes on the log

- **How it would work:** A rule refuses any delete.
- **Why it is attractive:** The strongest possible trail.
- **Why rejected:** `race_test.py` must delete its test rows, and must pass unmodified. Archiving keeps every deleted row instead.

## Consequences

- **What this buys:** Stock equals the sum of its log for all 4,023 products. Every new movement says what, when, why, which order and who. 261,005 past sales are now linked to their order.
- **What this costs:** One extra row written per stock change; callers that want a specific reason set it before changing stock (as `place_order` and `cancel_order` do).
- **What it costs the client if I am wrong:** Stock changes without a trail, and disputes nobody can settle.
- **What would make me revisit this:** Log volume large enough to slow sales, or a need to record who in the business made a change, not just which database user.

## What this survives

- **A direct `UPDATE products SET stock_quantity = …`:** logged as a `correction` with "no reason given", so it is visible.
- **A new product with opening stock:** logged as an opening balance automatically.
- **Someone editing history:** refused. **Someone deleting history:** a copy is kept with who and when.
- **The flash sale:** Test 4 passes; every sale under contention has its log row.
