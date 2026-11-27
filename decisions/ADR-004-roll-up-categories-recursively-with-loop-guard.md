# ADR-004: Roll up categories recursively, with a guard against loops

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Samuel Quaigraine

## Context

Nana wants low-stock counts rolled up through the category tree in a couple of seconds, without hard-coding how deep the tree goes. The tree is 4 levels today, stored in one table where each category points to its parent. The data contained a loop (Seasonal Promotions ⇄ Promotions) and a category pointing at a parent that does not exist (Clearance → 8999), which together hid 6 products from any tree walk (F-07). A foreign key can catch a missing parent but not a loop.

## Decision

`low_stock_rollup()` uses a recursive query: start from each category and keep stepping down to its children until there are none, whatever the depth. Each step remembers the route it took and refuses to visit a category twice (the loop guard). Each category counts the low-stock products in its whole branch. Products with no category get their own row. Cleanup made every unreachable category top-level, so nothing is hidden today.

## Alternatives considered

### Alternative A: One join per level (fixed depth)

- **How it would work:** Join categories to themselves 4 times.
- **Why it is attractive:** Easy to read.
- **Why rejected:** The brief forbids hard-coding depth; a fifth level would silently be ignored.

### Alternative B: Store the full path on each category

- **How it would work:** Save "Electronics > Phones > Cases" on every row and match on it.
- **Why it is attractive:** Very fast lookups.
- **Why rejected:** The path must be rebuilt whenever a category moves, a new place for errors. With 94 categories the recursive query already takes about 20 ms.

### Alternative C: Trust the data and skip the loop guard

- **How it would work:** Plain recursion.
- **Why it is attractive:** Slightly shorter.
- **Why rejected:** One bad parent link and the query runs forever; the data already had one.

## Consequences

- **What this buys:** The rollup runs in about **20 ms** for any depth, any threshold (`low_stock_rollup(10)`).
- **What this costs:** A recursive query is harder to read than a join; it is commented step by step.
- **What it costs the client if I am wrong:** Low-stock items hidden in a looped or orphaned branch, and stock-outs nobody saw coming.
- **What would make me revisit this:** Tens of thousands of categories (then Alternative B).

## What this survives

- **A new level of categories:** handled with no code change.
- **A future loop:** the guard stops it repeating; each category is counted once per branch.
- **A parent that does not exist:** now refused by a foreign key.
- **Products with no category:** shown in their own row, not dropped.
