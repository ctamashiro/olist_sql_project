# Olist E-Commerce Analytics: Snowflake · SQL · Tableau

End-to-end analytics project on **~100K orders from Olist**, a Brazilian e-commerce marketplace (2016–2018). Raw CSVs are loaded into Snowflake, cleaned, modeled into a star schema, analyzed with SQL, and visualized in an interactive Tableau dashboard.

**📊 [View the live dashboard on Tableau Public](https://public.tableau.com/views/OlistE-CommerceAnalytics_17944321377450/Dashboard1)**

[Dashboard](https://public.tableau.com/views/OlistE-CommerceAnalytics_17944321377450/Dashboard1)

---

## Key Findings

1. **Late deliveries cut review scores by more than half.** Orders delivered 7+ days early average **4.31 / 5**, on-time orders **4.17**, 1–7 days late **2.71**, and 7+ days late just **1.70**. Delivery speed is the single biggest lever on customer satisfaction.
2. **Delivery time varies more than 3x by state.** Average delivery ranges from **8.7 days** in the fastest state to **29.3 days** in the slowest, with northern and northeastern states waiting longest.
3. **Olist is almost entirely a one-time-purchase business.** Only **[X]%** of customers ever place a second order, and monthly cohort retention stays below **[X]%** after the first month.
4. **Revenue is concentrated in a few categories.** Health & beauty and watches & gifts lead all 70+ categories; the top 10 categories account for **[X]%** of revenue.
5. **A small share of sellers drives most sales.** **[X]%** of sellers generate 80% of revenue.

### Recommendations
- **Prioritize logistics in slow regions.** Reducing late deliveries is the most direct path to better reviews.
- **Invest in retention.** With a ~[X]% repeat rate, even small gains from post-purchase email or loyalty offers would compound.
- **Support top sellers.** Revenue depends on a small seller base, so seller churn is a material risk.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Data warehouse | Snowflake |
| Transformation & analysis | SQL (CTEs, window functions, QUALIFY, cohort analysis, RFM) |
| Visualization | Tableau Public |
| Version control | Git / GitHub |

## Pipeline

```
Kaggle CSVs (9 files, 1.5M+ rows)
        │
        ▼
  RAW schema        → untouched source data loaded via Snowflake stage + COPY INTO
        │
        ▼
  STAGING schema    → cleaned, deduplicated, standardized tables
        │
        ▼
  ANALYTICS schema  → star schema (2 fact tables, 4 dimensions)
        │
        ▼
  SQL analysis + Tableau dashboard
```

## Data Model

![Schema](dashboard/schema.png)

**Fact tables**
- `fact_order_items`: one row per item sold (price, freight, product, seller)
- `fact_orders`: one row per order (payments, delivery metrics, review score)

**Dimensions:** `dim_customer`, `dim_product`, `dim_seller`, `dim_date` (generated in SQL)

**Why two fact tables?** An order can contain several items *and* several payments. Joining both at once multiplies rows and double-counts revenue, so item-level and order-level metrics each live at their own grain.

## Data Quality Issues Handled

| Issue | Fix |
|---|---|
| `customer_id` is unique per *order*, not per person | Modeled customers on `customer_unique_id` (~96K real customers vs ~99K IDs) |
| Duplicate reviews per order | Kept the most recent review with `QUALIFY ROW_NUMBER()` |
| Geolocation table has ~1M rows for ~19K zip codes | Collapsed to one row per zip, dropped coordinates outside Brazil |
| Category names in Portuguese, 2 with no translation | Joined translation table with fallback to original name |
| Zip codes lose leading zeros if stored as numbers | Stored as strings, padded with `LPAD` |
| Junk `not_defined` payment records | Filtered out in staging |
| Typos in source column names (`product_name_lenght`) | Renamed in staging |

## SQL Highlights

| File | What it does |
|---|---|
| `sql/01_setup.sql` | Warehouse, database, schemas, file format, stage |
| `sql/02_load.sql` | Raw table DDL and `COPY INTO` loads with row-count checks |
| `sql/03_clean.sql` | Data profiling (key uniqueness, orphans, nulls) and staging tables |
| `sql/04_schema.sql` | Star schema build with revenue tie-out and orphan-key validation |
| `sql/05_analysis.sql` | 12 business questions: MoM growth (`LAG`), running totals, top-N per group (`RANK` + `QUALIFY`), cohort retention, RFM segmentation (`NTILE`), Pareto analysis |

## Repository Structure

```
olist_sql_project/
├── sql/          # numbered SQL scripts, run in order
├── dashboard/    # dashboard screenshot and schema diagram
├── data/         # raw CSVs go here (not committed)
└── README.md
```

## How to Reproduce

1. Download the [Olist dataset from Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and place the CSVs in `data/`.
2. In Snowflake, run `sql/01_setup.sql`.
3. Upload the 9 CSVs to the `OLIST.RAW.OLIST_STAGE` stage.
4. Run `02_load.sql` → `03_clean.sql` → `04_schema.sql` → `05_analysis.sql` in order.

## Data Source

Public dataset released by Olist on Kaggle: *Brazilian E-Commerce Public Dataset by Olist*. All monetary values are in Brazilian reais (R$).
