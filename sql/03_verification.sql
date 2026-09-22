-- Verification checks on retail_raw after loading.

-- 1. Row count: should match the 1,067,371 rows reported by \copy.
--    Result: 1,067,371. Load is complete.
SELECT COUNT(*) AS total_rows FROM retail_raw;

-- 2. Number of distinct countries.
--    Result: 43. Some entries may not be real countries (to check).
SELECT COUNT(DISTINCT country) AS country_count FROM retail_raw;

-- 3. Rows with no customer ID.
--    Result: 243,007 (22.8% of rows). These can't be used for
--    customer-level analysis, but are fine for revenue/product analysis.
SELECT COUNT(*) AS missing_customer_ids
FROM retail_raw
WHERE customer_id IS NULL;

-- 4. Date range of the data.
--    Result: 2009-12-01 07:45 to 2011-12-09 12:50.
--    December 2011 is only 9 days, so it is a partial month.
SELECT MIN(invoice_date) AS first_order, MAX(invoice_date) AS last_order
FROM retail_raw;
