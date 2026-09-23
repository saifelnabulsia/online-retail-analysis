# Online Retail Sales Analysis

Analysis of ~1.07M transactions from a UK-based online gift retailer
(Dec 2009 – Dec 2011), using PostgreSQL.

**Status:** in progress — data loaded and verified, analysis underway.

## Source
Chen, D. (2012). Online Retail II [Dataset]. UCI Machine Learning Repository.
https://doi.org/10.24432/C5CG6D — licensed CC BY 4.0.

## Questions
1. How did revenue trend over the two years?
2. Which products drive revenue, and does that differ from unit volume?
3. How concentrated is revenue by country?
4. What is average order value, and how does it vary by market?
5. What share of customers are repeat buyers, and what revenue do they drive?
6. How much revenue is lost to returns?

## Approach
- Source data ships as a two-sheet `.xlsx`. `convert.py` combines both sheets
  into a single CSV — exporting one sheet from Excel silently drops ~half the rows.
- Loaded into PostgreSQL via `\copy` after defining the schema.
- Raw data kept unmodified in `retail_raw`; cleaning will happen in a separate table.

## Data quality
Findings from the verification pass (`sql/03_verification.sql`):

- **Row count:** 1,067,371 rows loaded, matching the source file exactly.
- **Missing customer IDs:** 243,007 rows (22.8%) have no customer ID. These are
  usable for revenue and product analysis but not for customer-level questions,
  so question 5 runs on a smaller population than questions 1–4 and 6.
- **Partial final month:** data ends 2011-12-09, so December 2011 covers 9 days.
  It cannot be compared against full months in a trend without flagging.
- **Country field:** 43 distinct values; some may not be countries.

## Key findings

### 1. Revenue is strongly seasonal, peaking in November.**
Both years peak in November — £1.42M in 2010 and £1.46M in 2011 — with the
ramp beginning in September and revenue roughly doubling off a £500–700K
baseline. This is consistent with a wholesale gift retailer shipping stock
to retailers ahead of Christmas. The practical implication is that
month-on-month comparisons are misleading on this data: a January decline
is seasonal, not a downturn. Year-on-year comparison of the same month is
the honest read.

![Monthly revenue](outputs/q1_revenue_by_month.png)

*Dec 2011 excluded because the data ends 09/12/2011. Daily revenue over those 9 days
was £48.2K against £48.7K in November, so the run rate was flat and the
apparent collapse is an artifact of the cut-off, not a change in the business.*


## Repo
- `sql/` — queries, numbered in execution order
- `convert.py` — xlsx → CSV conversion
- `outputs/` — charts and exported results

Raw data files are not committed. Download from the source above and run
`convert.py` to reproduce.
