# Data Quality Investigation — `retail_raw`

Pre-analysis investigation of the UCI Online Retail II dataset as loaded into
PostgreSQL (1,067,371 rows). Purpose: identify what in this table is **not a
product sale**, before running any product ranking, revenue, or customer
analysis.

All queries below were run against `retail_raw` — the unmodified raw table.
The decisions recorded here are the input to `sql/05_cleaning.sql`, which
builds `retail_clean`.

---

## Check 1 — Non-product stock codes

**Question:** Does every row represent a product, or are some rows postage,
fees, adjustments, or test entries?

```sql
SELECT DISTINCT stock_code, description
FROM retail_raw
ORDER BY stock_code;
```

**What it does:** Lists every unique stock code with its description.
`stock_code` is `TEXT`, and text sorts digits before letters — so genuine
product codes (`85123A`, `22041`) cluster at the top and word-shaped codes
cluster at the bottom, where they can be read off directly.

**Findings — codes that are not products:**

| Category | Codes |
|---|---|
| Postage / carriage | `POST`, `DOT`, `C2`, `C3` |
| Fees and commission | `BANK CHARGES`, `AMAZONFEE`, `CRUK` |
| Adjustments | `ADJUST`, `ADJUST2`, `M`, `m`, `B` |
| Discounts | `D` |
| Samples | `S` |
| Test entries | `TEST001`, `TEST002` |
| Gift vouchers | `gift_0001_10` … `gift_0001_90` |

**Three secondary findings from the same output:**

1. **`M` and `m` both exist.** Postgres string comparison is case-sensitive,
   so a filter written as `stock_code != 'M'` would silently let the
   lowercase rows through. Any exclusion must handle both cases.
2. **`description` is used as a free-text notes field.** Values observed
   include `Adjustment by john on 26/01/2010`, `ebay`, `update`, and
   `to push order througha s stock was`. Consequence: `description` is not a
   reliable product identifier.
3. **Many descriptions are blank.** Some stock codes appear twice — once with
   a name, once blank — so `SELECT DISTINCT stock_code, description` returns
   them more than once. Not quantified (see Check 3).

**Interpretation and use:** These codes inflate any product-level ranking.
`POST` in particular carries real revenue and would plausibly appear in a
top-10 list. All are excluded from `retail_clean`.

**Feeds:** Q2 (top products by revenue and by units) directly. Q1, Q3 and Q4
indirectly, since postage and fees are not product sales.

**Open decision — gift vouchers.** Selling a £50 voucher is cash in, but the
revenue arguably occurs on redemption. If redemptions also appear in this
table, counting both double-counts. No evidence gathered either way.

---

## Check 2a — Negative prices

**Question:** Are there rows with a price below zero, and what are they?

```sql
SELECT COUNT(*) FROM retail_raw WHERE price < 0;

SELECT * FROM retail_raw WHERE price < 0;
```

**What it does:** Counts them, then — because the count was small enough to
read individually — pulls every matching row in full.

**Findings:** 5 rows, all identical in character:

| invoice | stock_code | description | quantity | price |
|---|---|---|---|---|
| A506401 | B | Adjust bad debt | 1 | −53,594.36 |
| A516228 | B | Adjust bad debt | 1 | −44,031.79 |
| A528059 | B | Adjust bad debt | 1 | −38,925.87 |
| A563186 | B | Adjust bad debt | 1 | −11,062.06 |
| A563187 | B | Adjust bad debt | 1 | −11,062.06 |

Total: **−£158,676.14**. All UK, all with no customer ID.

**Interpretation and use:** Bad debt write-offs, not sales. Two things follow:

1. **A third invoice prefix exists.** These invoices begin with `A` — not a
   digit, not `C`. The build plan only flagged `C` (cancellations). Any
   invoice-prefix logic has to account for three cases, not two.
2. **These rows are currently inside the Q1 revenue figures.** £53,594 was
   deducted from April 2010, reported as £590,580 — roughly 9% understated.
   July 2010, October 2010 and August 2011 are similarly affected. Bad debt is
   a real business event but it is not sales; leaving it in means the monthly
   line is "revenue net of write-offs", a different metric from the one
   labelled.

**Note:** A563186 and A563187 are the same amount one minute apart — possibly
a correction or a double entry. Not investigated.

**Feeds:** Q1 (monthly figures need recomputing on clean data). Q6, as part of
separating genuine returns from accounting adjustments.

---

## Check 2b — Zero prices

**Question:** Are there rows priced at zero, how many, and what causes them?

```sql
SELECT COUNT(*) FROM retail_raw WHERE price = 0;

SELECT * FROM retail_raw WHERE price = 0 LIMIT 20;

SELECT COUNT(DISTINCT DATE_TRUNC('day', invoice_date))
FROM retail_raw WHERE price = 0;

SELECT DATE_TRUNC('day', invoice_date) AS day, COUNT(*)
FROM retail_raw
WHERE price = 0
GROUP BY DATE_TRUNC('day', invoice_date)
ORDER BY COUNT(*) DESC
LIMIT 10;

SELECT COUNT(*) FROM retail_raw
WHERE price = 0 AND customer_id IS NOT NULL;
```

**What they do:** Count the rows; inspect a sample; then test whether they are
concentrated (a few stocktake events) or routine (spread across the calendar).
`DATE_TRUNC` is wrapped inside `COUNT(DISTINCT ...)` so timestamps on the same
day collapse to one value — counting raw timestamps would count minutes, not
days.

**Findings:**

- **6,202 rows** with `price = 0` (0.58% of the table).
- Spread across **473 distinct days**. Busiest day 137 rows, tenth-busiest 75
  — the top ten account for roughly 15% of the total, the rest averaging ~11
  per day across 463 further days.
- **71 rows have a customer ID. 6,131 do not.**
- Sample rows show sequential invoices one minute apart, quantities in both
  directions (`+598`, `−200`, `−330`), blank descriptions, real product codes.

**Interpretation and use:** The initial hypothesis was a stocktake — one
afternoon of warehouse reconciliation. The date distribution disproves it:
there is no spike. These are **routine back-office entries** (corrections,
damages, write-offs) on most trading days. Three of the ten busiest days fall
in December, consistent with more trading producing more corrections.

The 71 rows with a customer ID are a different population — plausibly genuine
free samples or goodwill items on real orders.

**Why this matters, and for which questions:** Zero price contributes £0 to any
revenue sum, so **Q1 and Q3 are unaffected**. But these rows carry
**quantities**, some large and some negative, so anything that sums quantity or
counts rows is distorted:

- **Q2** (top products by units sold) — a `−330` correction inside a
  `SUM(quantity)` would push a product down the ranking for non-sales reasons.
  This is the main reason to exclude them.
- **Q4** (average order value) — extra rows and invoices inflate the
  denominator.

**Decision:** exclude all zero-price rows. Excluding only the 6,131 without a
customer ID would be more precise, but the 71 contribute £0 revenue and
negligible quantity, so the precision buys nothing and costs a clause that
would need justifying.

---

## Check 3 — Blank descriptions

**Question:** How many rows have no product description?

**Status: observed but not quantified.** Blank descriptions were visible
throughout the Check 1 and Check 2b output, and the results grid confirmed them
as genuine `NULL` rather than empty strings — consistent with how `\copy`
interpreted empty CSV fields (the same behaviour seen with `customer_id`).

No count was run. Outstanding.

**Interpretation and use:** Already actionable without the number — because
`description` is unreliable (Check 1), **Q2 must group by `stock_code`, not by
description.** A count would strengthen the README's data quality section but
does not change any analysis decision.

---

## Check 4 — Cancellations

**Question:** How many rows are cancellations, what are they worth, and is
invoice prefix a reliable way to identify them?

```sql
SELECT COUNT(*) AS rows_with_cancellations
FROM retail_raw WHERE invoice LIKE 'C%';

SELECT SUM(quantity * price) AS sum_of_cancel
FROM retail_raw WHERE invoice LIKE 'C%';

SELECT COUNT(*) FROM retail_raw
WHERE invoice LIKE 'C%' AND quantity < 0;

SELECT * FROM retail_raw
WHERE invoice LIKE 'C%' AND quantity > 0;
```

**What they do:** `LIKE 'C%'` matches any invoice beginning with C — `%` is the
wildcard for "zero or more characters". The third and fourth queries test
whether "invoice starts with C" and "quantity is negative" identify the same
set of rows.

**Findings:**

- **19,494 cancellation rows** (1.83% of the table).
- Total value **−£1,526,667.86**.
- **19,493 have negative quantity. One does not:**

| invoice | stock_code | description | quantity | price | customer_id |
|---|---|---|---|---|---|
| C496350 | M | Manual | 1 | 373.57 | NULL |

**Interpretation and use:** The two filters are *almost* but not exactly
equivalent. Assuming they were interchangeable would put £373.57 on the wrong
side of a returns calculation. This row is a manual adjustment entered against
a cancellation invoice — not a product return.

It is caught by the `stock_code = 'M'` exclusion anyway, so it will not survive
into `retail_clean`. Two independent rules catching the same bad row is a good
sign, not a redundancy.

**Feeds:** Q6 (revenue lost to returns) directly — this is the core input. Also
Q1 and Q3, since gross and net revenue differ by this amount.

**Approximate scale, to be recomputed properly in Q6:** the 24 full months from
Q1 sum to **£18,853,564.56** *net* of cancellations. Adding back £1,526,667.86
implies gross of roughly **£20.38M** and a return rate near **7.5%**. These
figures come from the uncleaned table and should be recomputed on
`retail_clean` before being quoted anywhere.

---

## Check 5 — Duplicate rows

**Question:** Are there rows identical to another row across all eight columns?

```sql
SELECT invoice, stock_code, description, quantity, invoice_date,
       price, customer_id, country, COUNT(*) AS times_repeated
FROM retail_raw
GROUP BY invoice, stock_code, description, quantity, invoice_date,
         price, customer_id, country
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;
```

Then, to quantify the scale:

```sql
WITH duplicate_rows AS (
    SELECT invoice, stock_code, description, quantity, invoice_date,
           price, customer_id, country,
           COUNT(*) AS times_repeated
    FROM retail_raw
    GROUP BY invoice, stock_code, description, quantity, invoice_date,
             price, customer_id, country
    HAVING COUNT(*) > 1
)
SELECT SUM(times_repeated)            AS total_rows_involved,
       COUNT(*)                       AS distinct_patterns,
       SUM(times_repeated) - COUNT(*) AS excess_rows
FROM duplicate_rows;
```

**What they do:** Grouping by all eight columns makes each pile a set of
identical rows; `HAVING COUNT(*) > 1` keeps only piles with more than one
member. `HAVING` rather than `WHERE` because the count does not exist until
after grouping.

The second query treats the first as a table. A `GROUP BY` result cannot be
aggregated again inside the same `SELECT`, so the CTE (`WITH ... AS`) names the
intermediate result and lets a second `SELECT` run over it.

**Findings:**

- **32,907 distinct repeated patterns**
- **67,242 physical rows involved**
- **34,335 excess rows — 3.2% of the table**
- Average repeat: **2.04** — the overwhelming majority are simple pairs
- Extreme case: invoice 555524, pink Regency teacup, quantity 1, 2011-06-05
  11:37, customer 16923 — **repeated 20 times**. The same invoice and minute
  also contains the green teacup repeated 12 times.

**Interpretation:** Genuinely ambiguous, and the data cannot resolve it.

- **Artifact reading:** a double-submit or system glitch wrote one order line
  several times. The 2.04 average supports this — a pair is a very plausible
  double-submit.
- **Legitimate reading:** the order genuinely contains 20 teacups, entered as
  20 lines of 1 rather than one line of 20. Some order-entry systems produce
  this (a barcode scanned repeatedly). The matched pink/green pair on one
  invoice reads more like a wholesale crockery order than a glitch.

**Decision: keep them.** Removing them would understate revenue if they are
genuine, and there is no evidence that they are not. Recorded as a known
ambiguity rather than silently resolved in either direction.

**Feeds:** everything — a 3.2% row-count difference touches all six questions.
The figure belongs in the README so any reader knows the row count could
legitimately have been 3.2% lower.

---

## Summary — exclusion list for `retail_clean`

| # | Exclude | Rows | Reason |
|---|---|---|---|
| 1 | Non-product stock codes (incl. both `M` and `m`) | not yet counted | Not products; would pollute rankings |
| 2 | Negative prices | 5 | Bad debt write-offs, not sales |
| 3 | Zero prices | 6,202 | Back-office corrections, not sales |
| 4 | Cancellations (`invoice LIKE 'C%'`) | 19,494 | Returns — excluded from sales analysis, analysed separately in Q6 |
| 5 | December 2011 | — | Partial month (9 days); verified safe to drop, daily run rate flat (£48.2K/day vs £48.7K in November) |

**Kept deliberately:** duplicate rows (34,335 excess, 3.2%) — ambiguous, and
removal risks understating revenue.

**Note on Q6:** returns must be measured against `retail_raw`, not
`retail_clean`, because `retail_clean` excludes the very rows Q6 is about.

---

## Still outstanding

- Count of NULL descriptions (Check 3)
- Row count removed by the non-product stock code exclusion
- Gift voucher treatment decision
- Whether `retail_clean` should also drop rows with no customer ID (243,007,
  22.8%) — currently **no**: they are usable for Q1–Q4 and Q6, and only Q5
  needs to filter them out
