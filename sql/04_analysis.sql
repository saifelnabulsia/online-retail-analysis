-- ============================================================
-- Q1: How did revenue trend over the two years?
-- ============================================================
--
-- Run against retail_clean, so the figures are on the same basis as every
-- other question. December 2011 needs no filter here — the clean table
-- already excludes it.
--
-- Validation: the 24 monthly figures sum to £19,417,504.14, matching the
-- retail_clean total of £19,417,504.15 to within a penny of rounding.

select date_trunc('month', invoice_date) as month,
       round(sum(quantity * price), 2) as revenue
from retail_clean
group by date_trunc('month', invoice_date)
order by date_trunc('month', invoice_date) asc;

-- Finding: revenue is strongly seasonal. Both years peak in November
-- (£1,435,680 in 2010, £1,457,746 in 2011) with the ramp starting in
-- September. Jan–Aug months sit between £509K and £764K, averaging £652K,
-- so the November peak is 2.2x the off-season average and 2.9x the
-- February trough. Consistent with a wholesale gift retailer shipping
-- Christmas stock to retailers.
--
-- Year-on-year: the data contains two complete comparable 12-month periods.
-- Dec 2009–Nov 2010 totalled £9,429,521; Dec 2010–Nov 2011 totalled
-- £9,987,983 — growth of 5.9%.
--
-- Implication: month-on-month comparison is misleading on this data. A
-- January decline is seasonal, not a downturn. Year-on-year comparison of
-- the same month, or of full comparable periods, is the honest read.




-- ============================================================
-- Q2: Which products drive revenue, and does that differ from
--     unit volume?
-- ============================================================
--
-- Run against retail_clean, which excludes postage, fees, adjustments
-- and the phantom order (see 05_cleaning.sql).
--
-- Grouping decision: grouped by stock_code alone, NOT by
-- stock_code + description. Description is a free-text field with
-- inconsistent values for the same product — 21212 is recorded as both
-- "PACK OF 72 RETROSPOT CAKE CASES" and "PACK OF 72 RETRO SPOT CAKE
-- CASES". Grouping by both splits a product into two partial rows.
--
-- Effect of getting this wrong: with description in the GROUP BY, 21212
-- appeared at 9th and 10th by units (49,346 + 46,755) instead of 2nd
-- (96,101), and 85099B's revenue was understated by £34,631. Two other
-- products were incorrectly excluded from the revenue top 10.
--
-- max(description) picks one description per code to display. Which one
-- is arbitrary (alphabetically last) — acceptable because the field is
-- unreliable either way and is not used for grouping.


-- Q2a: Top 10 products by revenue, with units and average unit price
-- alongside.
--
-- Result: Regency Cakestand 3 Tier leads at £338,556 — 30% clear of
-- second place. Top 10 spans £338K down to £72K.

select stock_code, max(description) as description,
       sum(quantity) as units,
       round(sum(quantity * price), 2) as revenue,
       round(sum(quantity * price) / sum(quantity), 2) as avg_price
from retail_clean
group by stock_code
order by revenue desc
limit 10;


-- Q2b: The same measures ranked by units instead.
--
-- Result: WW2 Gliders lead at 108,771 units.
--
-- Only 4 of the 10 products appear in both lists (85123A, 85099B,
-- 84879, 22197).
--
-- The two leaders are opposites. WW2 Gliders top units at 108,771,
-- more than any other product, but generate only £24,881 at £0.23/unit.
-- 150 products earn more revenue than the volume leader, putting it
-- 151st by revenue. The Regency Cakestand earns 13.6x that revenue
-- (£338,556) on a quarter of the volume (27,127 units), at £12.48 each
-- — 54x the price.
--
-- Median unit price in the units top 10 is £0.64; in the revenue top 10
-- it is £2.74. Two distinct product populations.
--
-- Interpretation: revenue is driven by a small number of higher-priced
-- statement items; volume is driven by cheap party and impulse goods.
-- Ranking by either measure alone misrepresents the product mix.
--
-- Note: 22423 (the top revenue product) was also the second most-returned
-- product in Q6 at -£16,646.

select stock_code, max(description) as description,
       sum(quantity) as units,
       round(sum(quantity * price), 2) as revenue,
       round(sum(quantity * price) / sum(quantity), 2) as avg_price
from retail_clean
group by stock_code
order by units desc
limit 10;


-- ============================================================
-- Q3: How concentrated is revenue by country?
-- ============================================================
--
-- Run against retail_clean. The percentage column divides each country's
-- revenue by the table total, computed with a scalar subquery rather than
-- a hardcoded figure so it stays correct if retail_clean is rebuilt.
--
-- Result: revenue is extremely concentrated.
--   United Kingdom          £16,584,435   85.41%
--   EIRE (Ireland)             £621,788    3.20%
--   Netherlands                £538,225    2.77%
--   Germany                    £381,806    1.97%
--   France                     £310,410    1.60%
--   ...
--   Top 5 markets combined                94.95%
--   Remaining 38 markets combined          5.05%
--
-- Non-UK revenue totals £2,833,069 (14.59%) across 42 markets.
--
-- Validation: the 43 country rows sum to £19,417,504.15, matching the
-- retail_clean total exactly — no rows lost to grouping.
--
-- Interpretation: this is a UK domestic business with a thin European
-- export tail, not an international one. The practical implication is
-- for Q4: outside the top five markets, per-market samples are small
-- enough that comparing average order value across all 43 would be
-- reading noise. Any market-level comparison should be limited to the
-- five markets that carry 95% of revenue.
--
-- Data quality, noted but not acted on:
--   - "Unspecified" (£10,936) and "European Community" (£1,159) are not
--     countries. Combined they are 0.062% of revenue — excluding them
--     changes no figure above to two decimal places, so they were left in.
--   - The field is not a clean country list: EIRE is the archaic name for
--     Ireland, RSA an abbreviation for South Africa, Channel Islands a
--     crown dependency, West Indies a region. Naming is inconsistent but
--     no entry is duplicated, so totals are unaffected.

select country, 
	round(sum(quantity * price), 2) as revenue, 
	round(100 * sum(quantity * price)
          / (select sum(quantity * price) from retail_clean), 2) as pct_of_revenue 
from retail_clean
group by country
order by revenue desc;


-- ============================================================
-- Q4: What is average order value, and how does it vary by market?
-- ============================================================
--
-- Run against retail_clean.
--
-- Definition: an order is an invoice, not a row. The table holds one row per
-- line item, so an invoice with eight products is eight rows. The denominator
-- is therefore count(distinct invoice), not count(*). Dividing revenue by row
-- count would give the average line-item value, which is not a metric anyone
-- uses.
--
-- Known limitation: retail_clean excludes cancellation rows but keeps the
-- original orders they cancel, so an order that was later cancelled still
-- counts here. Same limitation recorded in the README.


-- Q4a: Overall average order value.
--
-- Result: £19,417,504.15 across 38,699 orders = £501.76 per order.
--
-- Cross-check: 1,011,989 line items / 38,699 orders = 26 distinct products
-- per order. Combined with the November peak in Q1, that is a second
-- independent signal that this is wholesale rather than consumer retail —
-- nobody buys 26 separate product lines for a household.

select round(sum(quantity * price), 2) as total_revenue,
       count(distinct invoice) as order_count,
       round(sum(quantity * price) / count(distinct invoice), 2) as avg_order_value
from retail_clean;


-- Q4b: Order value distribution — is the mean representative?
--
-- A mean is pulled upward by large outliers, so on transaction data it is
-- usually above the typical order. Checked with a median.
--
-- The CTE collapses 1,011,989 line items into 38,699 rows, one per invoice,
-- each carrying that order's total. The outer query then treats each ORDER as
-- a single data point rather than each line item.
--
-- percentile_cont(0.5) within group (order by order_total) sorts the order
-- totals and returns the midpoint. ::numeric casts the result so round() will
-- accept it.
--
-- Result:
--   orders          38,699
--   mean            £501.76
--   median          £303.30
--   smallest order  £0.19
--   largest order   £52,940.94
--
-- The mean is 65% above the median. The typical order is roughly £300; the
-- average is £500 because a minority of very large wholesale orders pull it
-- up. Quoting AOV alone would overstate what a typical customer spends by
-- two thirds.
--
-- Validation: 38,699 x £501.76 reconciles to the £19,417,504.15 total.

with order_totals as (
    select invoice,
           sum(quantity * price) as order_total
    from retail_clean
    group by invoice
)
select count(*)                   as order_count,
       round(avg(order_total), 2) as mean_aov,
       round(percentile_cont(0.5) within group (order by order_total)::numeric, 2)
                                  as median_aov,
       round(min(order_total), 2) as smallest_order,
       round(max(order_total), 2) as largest_order
from order_totals;


-- Q4c: Average order value by market.
--
-- order_count is kept visible deliberately. Per Q3, only five markets carry
-- meaningful volume; 11 markets have three orders or fewer, where the "average"
-- is one or two transactions and means nothing. Bermuda's £1,253.14 is a single
-- order, not an average.
--
-- Result, markets with meaningful volume:
--   United Kingdom   £16,584,435   35,439 orders   AOV   £467.97
--   Germany             £381,806      736 orders   AOV   £518.76
--   France              £310,410      581 orders   AOV   £534.27
--   EIRE (Ireland)      £621,788      571 orders   AOV £1,088.95
--   Netherlands         £538,225      213 orders   AOV £2,526.88
--   Spain                £98,325      142 orders   AOV   £692.43
--   Belgium              £56,034      139 orders   AOV   £403.12
--   Australia           £168,485       89 orders   AOV £1,893.09
--
-- The headline split:
--   UK       £467.97 per order over 35,439 orders
--   Export   £869.04 per order over  3,260 orders  (1.86x the UK)
--
-- Note the UK accounts for 85.4% of revenue but 91.6% of orders — a larger
-- share of orders than of revenue, which is why its AOV sits BELOW the
-- overall £501.76 despite dominating the business.
--
-- The Netherlands is the standout at 5.4x the UK's order size on only 213
-- orders. Australia (£1,893), Denmark (£1,669) and Japan (£1,428) follow the
-- same pattern.
--
-- Interpretation: export orders are nearly twice the size of domestic ones.
-- A plausible explanation is that cross-border shipping makes small
-- international orders uneconomic, so only larger wholesale consignments
-- travel — but that is a hypothesis this data cannot confirm, since it holds
-- no shipping cost or customer-type information.

select country,
       round(sum(quantity * price), 2) as total_revenue,
       count(distinct invoice) as order_count,
       round(sum(quantity * price) / count(distinct invoice), 2) as avg_order_value
from retail_clean
group by country
order by total_revenue desc;


-- ============================================================
-- Q5: What share of customers are repeat buyers, and what
--     revenue do they drive?
-- ============================================================
--
-- POPULATION NOTE — this is the only question that runs on a different
-- population from the rest. 243,007 rows have no customer_id. A transaction
-- with no customer attached cannot be assigned to a person, so those rows
-- cannot enter a customer-level count at all: there is no way to tell
-- whether they came from one buyer or twenty thousand. This query therefore
-- filters to customer_id IS NOT NULL, and every figure below describes
-- identified customers only.
--
-- How much of the business that covers: identified customers account for
-- £16,844,051 of revenue — 86.7% of the £19,417,504.15 total. So although
-- 22.8% of ROWS lack a customer ID, those rows represent only 13.3% of
-- REVENUE. Unidentified transactions are smaller on average, which means
-- this population covers more of the business than the row-count figure
-- suggests.
--
-- Known bias, in the other direction: customers with IDs are account
-- holders, who are more likely to be returning wholesale buyers than
-- walk-up purchasers. The repeat rate below is therefore probably higher
-- than the true rate across all buyers. Both points are true and both are
-- stated in the README.
--
-- Structure: the CTE produces one row per customer carrying their order
-- count and total spend — an aggregate. The outer query then aggregates
-- THAT result, splitting customers into two groups. A single SELECT only
-- allows one level of grouping, so the CTE is required, not stylistic.
--
-- "order_count > 1" is an expression evaluating to true or false per row,
-- so it can be grouped on directly. This avoids a CASE statement and keeps
-- the split explicit: false = one-time buyer, true = repeat buyer.
--
-- Result (5,824 identified customers):
--
--   is_repeat   customers        revenue      % customers   % revenue
--   false           1,647       £573,723          28.3%         3.4%
--   true            4,177    £16,270,327          71.7%        96.6%
--
--   Revenue per customer: one-time £348.34, repeat £3,895.22 — 11.2x.
--
-- Interpretation: the business runs almost entirely on repeat
-- relationships. 96.6% of identified revenue comes from customers who
-- ordered more than once, while the 28% who never returned contributed 3%.
-- For a wholesaler this is the expected shape, but the magnitude is the
-- finding: a repeat customer is worth eleven times a one-time one, which
-- means retention is worth more than acquisition at almost any plausible
-- cost ratio.


with customer_orders as (
	select customer_id, count(distinct invoice) as order_count,
		sum(quantity * price) as customer_revenue
	from retail_clean
	where customer_id is not null
	group by customer_id)
select order_count > 1 as is_repeat, 
count(*) as number_of_customers,
round(sum(customer_revenue), 2) as total_revenue
from customer_orders
group by order_count > 1;

-- ============================================================
-- Q6: How much revenue is lost to returns?
-- ============================================================
-- Returns are measured against retail_raw, not retail_clean - the clean
-- table excludes cancellation rows, which are exactly what this question
-- is about.
--
-- Step 1: denominator - gross product sales (retail_clean).
-- 
-- Result: £19,417,504.15.

select round(sum(quantity * price), 2)  as revenue from retail_clean;

-- Step 2: numerator - returns (retail_raw), with the same exclusions as
-- the denominator so the two are comparable: non-product stock codes,
-- December 2011, and the phantom order. The only inversion is the invoice
-- filter — LIKE 'C%' instead of NOT LIKE.
--
-- Result: −£475,245.63.

select round(sum(quantity * price), 2) as returned_value from retail_raw
where invoice like 'C%' and price > 0
and invoice_date < '2011-12-01'
and invoice != 'C541433'
and stock_code not in ('POST', 'DOT', 'C2', 'C3', 'BANK CHARGES',
'AMAZONFEE', 'CRUK', 'ADJUST', 'ADJUST2', 'M', 'm', 'B', 'D', 'S',
'TEST001', 'TEST002', 'gift_0001_10', 'gift_0001_20','gift_0001_30','gift_0001_40',
'gift_0001_50','gift_0001_60','gift_0001_70','gift_0001_80','gift_0001_90');

-- Diagnostic: before the phantom order was identified, the like-for-like
-- numerator came to £552,429 — far below the £1,526,668 of total
-- cancellation value found during the data quality investigation.
-- Grouping by stock_code — with the stock-code exclusion deliberately
-- OMITTED — shows which codes carry the missing value.
--
-- Result: M (manual) −£423,107 and AMAZONFEE −£265,350 dominate, with
-- BANK CHARGES, POST, D, CRUK and S making up most of the rest. Two thirds
-- of "cancellation" value is accounting reversal, not goods returned.

select stock_code, sum(quantity * price) as returned_value from retail_raw
where invoice like 'C%' and price > 0
and invoice_date < '2011-12-01'
group by stock_code
order by returned_value asc
limit 15;

-- Diagnostic: stock code 23166 appeared in the breakdown at −£77,480,
-- 4.4x the next product. Investigating whether that is a pattern or a
-- single event.
--
-- Result: one row. Invoice C541433, 74,215 units, 2011-01-18 10:17 —
-- cancelling invoice 541431 placed 16 minutes earlier at 10:01. An
-- order-entry error, not a customer return. Both excluded.

select distinct stock_code, description from retail_raw
where stock_code = '23166';


select * from retail_raw 
where stock_code = '23166'
and invoice like 'C%'
order by quantity asc 
limit 10;

-- Diagnostic: checking whether the cancelled order had a matching purchase.
-- It did (541431). The customer's wider history — TEST001 bought nine
-- times, TEST002, ADJUST, Manual, Discount — suggests an internal or test
-- account. Only the phantom order was excluded; their other purchases
-- (doormats, parasols) look genuine.

SELECT * FROM retail_raw WHERE customer_id = '12346';

-- Step 3: the return rate.
--
-- Computed from the tables rather than hardcoded, so it stays correct if
-- retail_clean is ever rebuilt.
--
-- Numerator and denominator are on the same basis: both exclude non-product
-- stock codes, December 2011, and the phantom order (541431 / C541433).
-- ABS() is used because returns carry negative quantities, so the rate
-- reads as a positive percentage.
--
-- Result: £475,245.63 returned against £19,417,504.15 of product revenue
-- = 2.45%.

with gross_sales as (
    select sum(quantity * price) as revenue
    from retail_clean
),
product_returns as (
    select sum(quantity * price) as returned_value
    from retail_raw
    where invoice like 'C%'
      and price > 0
      and invoice_date < '2011-12-01'
      and invoice != 'C541433'
      and stock_code not in ('POST', 'DOT', 'C2', 'C3', 'BANK CHARGES',
          'AMAZONFEE', 'CRUK', 'ADJUST', 'ADJUST2', 'M', 'm', 'B', 'D', 'S',
          'TEST001', 'TEST002', 'gift_0001_10', 'gift_0001_20', 'gift_0001_30',
          'gift_0001_40', 'gift_0001_50', 'gift_0001_60', 'gift_0001_70',
          'gift_0001_80', 'gift_0001_90')
)
select round(gross_sales.revenue, 2)        as gross_product_revenue,
       round(product_returns.returned_value, 2) as returns_value,
       round(100 * abs(product_returns.returned_value)
                 / gross_sales.revenue, 2)  as return_rate_pct
from gross_sales, product_returns;
