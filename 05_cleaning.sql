-- Builds retail_clean from retail_raw.
-- retail_raw is never modified; every exclusion below is a decision,
-- with the evidence in notes/data_quality_investigation.md.
--
-- Rows in:  1,067,371
-- Rows out: 1,011,989  (55,382 removed, 5.2%)

drop table if exists retail_clean;

create table retail_clean as select * from retail_raw
where price > 0          -- Removes all prices <=0
and invoice not like 'C%'-- Removes all invoices that start with C (cancellations)
and invoice != '541431' -- Excludes invoice 541431: 74,215 ceramic jars ordered 2011-01-18 10:01
-- and cancelled 16 minutes later (C541433). An order-entry error, not a
-- sale. Left in, it would be the top product by units sold.
and invoice_date < '2011-12-01' -- drops the partial month of December 
and stock_code not in ('POST', 'DOT', 'C2', 'C3', 'BANK CHARGES',
'AMAZONFEE', 'CRUK', 'ADJUST', 'ADJUST2', 'M', 'm', 'B', 'D', 'S',
'TEST001', 'TEST002', 'gift_0001_10', 'gift_0001_20','gift_0001_30','gift_0001_40',
'gift_0001_50','gift_0001_60','gift_0001_70','gift_0001_80','gift_0001_90');

select count(*) from retail_clean;

select round(sum(quantity*price), 2) from retail_clean;