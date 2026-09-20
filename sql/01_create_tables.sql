-- Creates the raw landing table for the UCI Online Retail II dataset.
-- Data is loaded as-is; no cleaning applied at this stage.

CREATE TABLE retail_raw (
    invoice      TEXT,
    stock_code   TEXT,
    description  TEXT,
    quantity     INTEGER,
    invoice_date TIMESTAMP,
    price        NUMERIC,
    customer_id  TEXT,
    country      TEXT
);
