-- Loads the converted CSV into retail_raw.
-- Run from psql, with the project root as the working directory.
-- \copy is a psql command, not SQL — it will not run in DBeaver.
--
-- Source file produced by convert.py (combines both sheets of the
-- source .xlsx into a single CSV).
\copy retail_raw FROM 'online_retail_II.csv' WITH (FORMAT csv, HEADER true);
