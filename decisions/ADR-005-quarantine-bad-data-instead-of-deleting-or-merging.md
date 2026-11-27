# ADR-005: Quarantine bad data instead of deleting or merging it

- **Status:** Accepted
- **Date:** 2026-11-27
- **Decision owner:** Samuel Quaigraine

## Context

Rules such as foreign keys and CHECKs can only be added once no existing row breaks them. The data had 1,022 rows pointing at parents that do not exist, 24 orders dated after the extract ends, 617 repeated order lines, 519 duplicate log rows, 6 absurd quantities and 148 lines with no price (data_findings.md). It also had 533 groups of customers sharing an email, with the same name but different phones, and 15 spellings of 5 statuses. For several of these the true answer cannot be proven from the data.

## Decision

Rows that break a rule are **moved** to a matching `_quarantine` table (`orders_quarantine`, `order_items_quarantine`, `inventory_log_quarantine`) with the reason and the time. Values whose meaning is certain are **fixed in place**: status spellings, stray spaces, email case, city spelling, phone format. Rows whose fix needs a business decision are **left alone and documented**: duplicate-email customers are not merged, zero-price lines are kept.

## Alternatives considered

### Alternative A: Delete the bad rows

- **How it would work:** `DELETE` everything that breaks a rule.
- **Why it is attractive:** Simplest; the tables end up clean.
- **Why rejected:** Not reversible. If the orphans turn out to be real (their source is unconfirmed), the evidence is gone.

### Alternative B: Merge duplicate customers

- **How it would work:** Keep one record per email; move all orders to it.
- **Why it is attractive:** One customer, one total spend.
- **Why rejected:** The phone number never matches, so they may be different people. Merging moves order history between people and cannot be undone cleanly. None of them is in the current top 100, so leaving them changes no reported number.

### Alternative C: Repair values by inference

- **How it would work:** Set absurd quantities to total ÷ price; fill missing prices from the product's list price.
- **Why it is attractive:** Keeps every line.
- **Why rejected:** These are guesses presented as data. The order totals are already correct, and reports use them.

## Consequences

- **What this buys:** Every rule could be added; every removed row can be found, with its reason (234 orders, 1,979 lines, 679 log rows). Nothing disappeared.
- **What this costs:** Three extra tables; 30 orders now have no lines (their only line was quarantined); 150 zero-price lines remain.
- **What it costs the client if I am wrong:** If quarantined rows were real, totals that include them are understated until they are restored.
- **What would make me revisit this:** Kloud Kart confirming the source of the orphan rows or the duplicate customers: then restore or merge them on purpose.

## What this survives

- **Running cleanup twice:** quarantine tables are keyed on the original id, and the one-off rules only touch rows from the extract, so new sales are never quarantined.
- **Needing a row back:** it is in quarantine with its original id and values.
- **New bad data:** refused at the door by the rules in `03_constraints.sql`, so it never needs quarantining.
