-- =====================================================================
-- 01_data_audit.sql — Can we trust the data?
-- Purpose: decide which tables/columns are safe to analyse before
--          drawing any business conclusions.
-- Verdict summary (details under each check):
--   ✔ orders            — complete, no duplicates, money math reconciles
--   ✔ monthly_revenue   — exactly = delivered orders
--   ✔ product_summary   — exactly = non-cancelled orders
--   ✘ customers totals  — total_orders / total_spend_usd do NOT match orders
--   ✘ registration_date — 74% of orders predate the customer's registration
--   ⚠ delivery_date     — populated even for cancelled orders
--   ⚠ customer_rating   — 63% missing
-- Rule adopted: all revenue / frequency metrics come from `orders`.
-- =====================================================================


-- 1.1 Row counts and key uniqueness
-- Finding: 8,000 / 25,000 / 140 / 75 rows; no duplicate keys.
SELECT 'customers' AS table_name, COUNT(*) AS row_count, COUNT(DISTINCT customer_id) AS distinct_keys FROM customers
UNION ALL
SELECT 'orders', COUNT(*), COUNT(DISTINCT order_id) FROM orders
UNION ALL
SELECT 'product_summary', COUNT(*), COUNT(DISTINCT category || product_name) FROM product_summary
UNION ALL
SELECT 'monthly_revenue', COUNT(*), COUNT(DISTINCT (year, month)) FROM monthly_revenue;


-- 1.2 Referential integrity: orders ↔ customers
-- Finding: 0 orphan orders; 337 customers have never ordered (7,663 active buyers).
SELECT
    (SELECT COUNT(*) FROM orders o
      WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.customer_id = o.customer_id)) AS orphan_orders,
    (SELECT COUNT(*) FROM customers c
      WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id))  AS customers_without_orders;


-- 1.3 Order status mix and the `returned` flag
-- Finding: Delivered 81.99% · Returned 8.08% · Cancelled 5.82% · Processing 4.11%.
--          returned = 1 matches order_status = 'Returned' on all 2,020 rows → use either.
SELECT
    order_status,
    COUNT(*)                                           AS orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders,
    SUM(returned)                                      AS returned_flag_count
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- 1.4 Money arithmetic inside each order
-- Finding: 0 rows break subtotal = price × qty or
--          total = subtotal − discount + shipping + tax → order amounts are reliable.
SELECT
    COUNT(*) FILTER (WHERE ABS(subtotal_usd - unit_price_usd * quantity) > 0.02) AS bad_subtotals,
    COUNT(*) FILTER (WHERE ABS(total_amount_usd
                       - (subtotal_usd - discount_amount_usd + shipping_fee_usd + tax_amount_usd)) > 0.05) AS bad_totals
FROM orders;


-- 1.5 Do the summary tables agree with orders?
-- Finding: monthly_revenue = delivered orders exactly ($2,585,126.50 · 20,497 orders).
--          product_summary  = all non-cancelled orders (23,544 orders).
SELECT
    'monthly_revenue' AS summary_table,
    (SELECT SUM(revenue_usd) FROM monthly_revenue)                             AS summary_revenue,
    (SELECT SUM(total_amount_usd) FROM orders WHERE order_status = 'Delivered') AS orders_revenue,
    (SELECT SUM(orders) FROM monthly_revenue)                                  AS summary_orders,
    (SELECT COUNT(*) FROM orders WHERE order_status = 'Delivered')             AS orders_count
UNION ALL
SELECT
    'product_summary',
    (SELECT SUM(total_revenue_usd) FROM product_summary),
    (SELECT SUM(total_amount_usd) FROM orders WHERE order_status <> 'Cancelled'),
    (SELECT SUM(total_orders) FROM product_summary),
    (SELECT COUNT(*) FROM orders WHERE order_status <> 'Cancelled');


-- 1.6 Do customer-level totals agree with orders?  (the critical check)
-- Finding: NO. customers.total_spend_usd sums to $12.47M vs $3.14M in orders (≈4×);
--          total_orders averages 16.6 vs 3.1 actual; only ~5% of customers match.
--          → customers.total_orders / total_spend_usd / avg_order_value_usd are excluded
--            from all analysis. Spend and frequency are rebuilt from orders.
WITH actual AS (
    SELECT customer_id, COUNT(*) AS orders_in_data, SUM(total_amount_usd) AS spend_in_data
    FROM orders
    GROUP BY customer_id
)
SELECT
    ROUND(SUM(c.total_spend_usd), 2)                         AS customers_table_spend,
    ROUND(SUM(COALESCE(a.spend_in_data, 0)), 2)              AS orders_table_spend,
    ROUND(AVG(c.total_orders), 1)                            AS customers_table_avg_orders,
    ROUND(AVG(COALESCE(a.orders_in_data, 0)), 1)             AS orders_table_avg_orders,
    ROUND(COUNT(*) FILTER (WHERE c.total_orders = COALESCE(a.orders_in_data, 0)) * 100.0
          / COUNT(*), 1)                                     AS pct_customers_matching
FROM customers c
LEFT JOIN actual a ON a.customer_id = c.customer_id;


-- 1.7 Date logic
-- Finding: 18,592 orders (74%) are dated BEFORE the customer's registration_date
--          → registration_date is unusable for tenure/acquisition timing; use first order date.
--          delivery_date is filled for cancelled/processing orders too
--          → delivery metrics are computed on delivered/returned orders only.
SELECT
    COUNT(*) FILTER (WHERE o.order_date < c.registration_date)                         AS orders_before_registration,
    ROUND(COUNT(*) FILTER (WHERE o.order_date < c.registration_date) * 100.0 / COUNT(*), 1) AS pct_orders_before_registration,
    COUNT(*) FILTER (WHERE o.order_status IN ('Cancelled', 'Processing')
                       AND o.delivery_date IS NOT NULL)                                AS undelivered_with_delivery_date
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id;


-- 1.8 Missing values
-- Finding: customer_rating is NULL on 15,749 orders (63%) → ratings are opt-in;
--          rating analyses use rated orders only and state the sample size.
--          No other analysed column has missing values.
SELECT
    COUNT(*)                                                         AS orders,
    COUNT(*) FILTER (WHERE customer_rating IS NULL)                  AS missing_rating,
    ROUND(COUNT(*) FILTER (WHERE customer_rating IS NULL) * 100.0 / COUNT(*), 1) AS pct_missing_rating
FROM orders;


-- 1.9 Time coverage
-- Finding: orders run 2020-01-01 → 2026-03-30 (75 months; Mar 2026 is a near-full month).
SELECT MIN(order_date) AS first_order, MAX(order_date) AS last_order,
       COUNT(DISTINCT DATE_TRUNC('month', order_date)) AS months_covered
FROM orders;
