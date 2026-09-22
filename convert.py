import pandas as pd

# sheet_name=None reads EVERY sheet, returning a dict of {sheet name: table}
sheets = pd.read_excel("online_retail_II.xlsx", sheet_name=None)
print("Sheets found:", list(sheets.keys()))

# stack the sheets on top of each other into one table
combined = pd.concat(sheets.values(), ignore_index=True)

# rename to snake_case so the CSV header matches your Postgres column names
combined.columns = [
    "invoice", "stock_code", "description", "quantity",
    "invoice_date", "price", "customer_id", "country"
]

# customer_id arrives as a float because of the missing values,
# which would write as "17850.0". Force it to a clean integer string,
# and leave truly missing ones empty so Postgres reads them as NULL.
combined["customer_id"] = (
    combined["customer_id"].astype("Int64").astype(str).replace("<NA>", "")
)

print("Total rows:", len(combined))
combined.to_csv("online_retail_II.csv", index=False)
print("Done — written to online_retail_II.csv")
