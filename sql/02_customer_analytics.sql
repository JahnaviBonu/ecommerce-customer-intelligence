-- =====================================================================
-- 02_customer_analytics.sql — Who are our customers and what drives value?
-- Source rule (from 01_data_audit): spend & frequency come from `orders`
-- (delivered only); customers.total_* columns are not used.
-- =====================================================================


-- 2.1 Customer mix by membership tier
-- Finding: Free 55.5% · Silver 21.7% · Gold 14.7% · Platinum 8.1%.
SELECT
    membership_tier,
    COUNT(*)                                           AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers
FROM customers
GROUP BY membership_tier
ORDER BY customers DESC;


-- 2.2 Revenue per customer by tier
-- Finding: flat — Free $321 · Silver $329 · Gold $324 · Platinum $320.
--          Paid tiers are not associated with higher spend.
-- Note: the Delivered condition sits in FILTER, not WHERE, so customers
--       with no delivered orders stay in the denominator.
SELECT
    c.membership_tier,
    COUNT(DISTINCT c.customer_id) AS customers,
    ROUND(COALESCE(SUM(o.total_amount_usd) FILTER (WHERE o.order_status = 'Delivered'), 0), 2) AS revenue,
    ROUND(COALESCE(SUM(o.total_amount_usd) FILTER (WHERE o.order_status = 'Delivered'), 0)
          / NULLIF(COUNT(DISTINCT c.customer_id), 0), 2)                                      AS revenue_per_customer
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.membership_tier
ORDER BY revenue DESC;


-- 2.3 Repeat-purchase rate by tier
-- Finding: Gold 74.0% · Silver 72.1% · Free 72.1% · Platinum 71.6% (lowest).
--          Tier does not drive purchase frequency either.
WITH customer_orders AS (
    SELECT c.customer_id, c.membership_tier, COUNT(o.order_id) AS delivered_orders
    FROM customers c
    LEFT JOIN orders o
        ON c.customer_id = o.customer_id
       AND o.order_status = 'Delivered'
    GROUP BY c.customer_id, c.membership_tier
)
SELECT
    membership_tier,
    COUNT(*)                                                   AS customers,
    COUNT(*) FILTER (WHERE delivered_orders > 1)               AS repeat_customers,
    ROUND(COUNT(*) FILTER (WHERE delivered_orders > 1) * 100.0
          / NULLIF(COUNT(*), 0), 2)                            AS repeat_rate_pct
FROM customer_orders
GROUP BY membership_tier
ORDER BY repeat_rate_pct DESC;


-- 2.4 Purchase-frequency distribution
-- Finding: 0 orders 7.5% · 1 order 20.2% · 2–5 orders 67.6% · 6–10 orders 4.7%.
WITH customer_orders AS (
    SELECT c.customer_id, COUNT(o.order_id) AS delivered_orders
    FROM customers c
    LEFT JOIN orders o
        ON c.customer_id = o.customer_id
       AND o.order_status = 'Delivered'
    GROUP BY c.customer_id
)
SELECT
    CASE
        WHEN delivered_orders = 0  THEN '0 orders'
        WHEN delivered_orders = 1  THEN '1 order'
        WHEN delivered_orders <= 5 THEN '2-5 orders'
        ELSE '6-10 orders'
    END                                                AS frequency_band,
    COUNT(*)                                           AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers
FROM customer_orders
GROUP BY frequency_band
ORDER BY frequency_band;


-- 2.5a Typical reorder cycle
-- Finding: median gap between a customer's delivered orders = 366 days (avg 484).
WITH order_gaps AS (
    SELECT
        customer_id,
        order_date - LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date) AS days_since_prev_order
    FROM orders
    WHERE order_status = 'Delivered'
)
SELECT
    COUNT(days_since_prev_order)                                             AS gaps_measured,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_since_prev_order)       AS median_gap_days,
    ROUND(AVG(days_since_prev_order), 0)                                     AS avg_gap_days
FROM order_gaps;


-- 2.5b Recency segmented by reorder cycle (reference date = last order in data)
-- Finding: Active 34.0% · At risk 21.9% · Lapsed 36.7% · Never purchased 7.5%.
--          "At risk" (missed exactly one cycle) is the win-back target.
WITH last_order AS (
    SELECT c.customer_id, MAX(o.order_date) AS last_delivered
    FROM customers c
    LEFT JOIN orders o
        ON c.customer_id = o.customer_id
       AND o.order_status = 'Delivered'
    GROUP BY c.customer_id
),
ref AS (
    SELECT MAX(order_date) AS ref_date FROM orders WHERE order_status = 'Delivered'
)
SELECT
    CASE
        WHEN last_delivered IS NULL               THEN 'Never purchased'
        WHEN ref_date - last_delivered <= 366     THEN 'Active'
        WHEN ref_date - last_delivered <= 732     THEN 'At risk'
        ELSE 'Lapsed'
    END                                                AS recency_segment,
    COUNT(*)                                           AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers
FROM last_order
CROSS JOIN ref
GROUP BY recency_segment
ORDER BY customers DESC;


-- 2.6 One-time vs repeat customer value
-- Finding: repeat buyers = 78% of purchasers but 92% of revenue;
--          $411 vs $127 per customer with the same AOV (~$126) → frequency drives value.
WITH customer_value AS (
    SELECT customer_id, COUNT(*) AS delivered_orders, SUM(total_amount_usd) AS revenue
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
)
SELECT
    CASE WHEN delivered_orders > 1 THEN 'Repeat' ELSE 'One-time' END AS customer_type,
    COUNT(*)                                                        AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)              AS pct_customers,
    ROUND(SUM(revenue), 2)                                          AS revenue,
    ROUND(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER (), 2)      AS pct_revenue,
    ROUND(SUM(revenue) / COUNT(*), 2)                               AS revenue_per_customer,
    ROUND(SUM(revenue) / SUM(delivered_orders), 2)                  AS avg_order_value
FROM customer_value
GROUP BY customer_type;


-- 2.7 Cohort retention (cohort = month of first delivered order)
-- Retention in month k = share of the cohort that bought again k months after their first month.
-- Only cohorts with ≥ 12 months of follow-up (first order on/before 2025-03) are averaged.
-- Finding: ~4% of a cohort buys in any later month (month 1: 3.6% · month 6: 3.6% · month 12: 3.8%).
--          Flat, no decay curve — consistent with a ~1-year reorder cycle rather than early drop-off.
WITH first_order AS (
    SELECT customer_id, DATE_TRUNC('month', MIN(order_date)) AS cohort_month
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT
        o.customer_id,
        f.cohort_month,
        (EXTRACT(YEAR FROM o.order_date) * 12 + EXTRACT(MONTH FROM o.order_date))
      - (EXTRACT(YEAR FROM f.cohort_month) * 12 + EXTRACT(MONTH FROM f.cohort_month)) AS months_since_first
    FROM orders o
    JOIN first_order f ON f.customer_id = o.customer_id
    WHERE o.order_status = 'Delivered'
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS customers FROM first_order GROUP BY cohort_month
),
retention AS (
    SELECT a.cohort_month, a.months_since_first,
           COUNT(*) * 100.0 / s.customers AS retention_pct
    FROM activity a
    JOIN cohort_size s ON s.cohort_month = a.cohort_month
    WHERE a.cohort_month <= DATE '2025-03-01'
    GROUP BY a.cohort_month, a.months_since_first, s.customers
)
SELECT
    months_since_first,
    COUNT(*)                      AS cohorts,
    ROUND(AVG(retention_pct), 2)  AS avg_retention_pct
FROM retention
WHERE months_since_first IN (0, 1, 3, 6, 12)
GROUP BY months_since_first
ORDER BY months_since_first;


-- 2.8 Customer value by acquisition channel
-- Finding: $313–$337 per customer, 71–76% repeat; the margins of error overlap
--          (Paid Ad $337 ± 17 vs Social $313 ± 14) → no channel is clearly better.
--          Budget decisions hinge on acquisition cost, which is not in this dataset.
WITH customer_metrics AS (
    SELECT c.customer_id, c.acquisition_channel,
           COUNT(o.order_id)                      AS delivered_orders,
           COALESCE(SUM(o.total_amount_usd), 0)   AS delivered_revenue
    FROM customers c
    LEFT JOIN orders o
        ON c.customer_id = o.customer_id
       AND o.order_status = 'Delivered'
    GROUP BY c.customer_id, c.acquisition_channel
)
SELECT
    acquisition_channel,
    COUNT(*)                                                                         AS customers,
    ROUND(AVG(delivered_revenue), 2)                                                 AS revenue_per_customer,
    ROUND(1.96 * STDDEV(delivered_revenue) / SQRT(COUNT(*)), 2)                      AS margin_of_error_95,
    ROUND(COUNT(*) FILTER (WHERE delivered_orders >= 2) * 100.0 / COUNT(*), 2)       AS repeat_rate_pct,
    ROUND(COUNT(*) FILTER (WHERE delivered_orders = 0) * 100.0 / COUNT(*), 2)        AS never_purchased_pct
FROM customer_metrics
GROUP BY acquisition_channel
ORDER BY revenue_per_customer DESC;


-- 2.9 Does the `churned` label match behaviour?
-- Finding: no. Churned customers order as often (2.54 vs 2.56) and spend slightly MORE
--          ($329 vs $323). The label tracks customers.days_since_last_purchase (95 vs 56 days),
--          an unreliable field. Churn is redefined from orders: "Lapsed" (2.5b).
WITH customer_metrics AS (
    SELECT c.customer_id, c.churned, c.days_since_last_purchase,
           COUNT(o.order_id)                     AS delivered_orders,
           COALESCE(SUM(o.total_amount_usd), 0)  AS delivered_revenue,
           MAX(o.order_date)                     AS last_delivered_order_date
    FROM customers c
    LEFT JOIN orders o
        ON c.customer_id = o.customer_id
       AND o.order_status = 'Delivered'
    GROUP BY c.customer_id, c.churned, c.days_since_last_purchase
)
SELECT
    churned,
    COUNT(*)                                       AS customers,
    ROUND(AVG(delivered_orders), 2)                AS avg_delivered_orders,
    ROUND(AVG(delivered_revenue), 2)               AS revenue_per_customer,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY DATE '2026-03-30' - last_delivered_order_date)::numeric, 2) AS median_days_since_last_order,
    ROUND(AVG(days_since_last_purchase), 2)        AS avg_days_since_last_purchase_col,
    ROUND(COUNT(*) FILTER (WHERE delivered_orders = 0) * 100.0 / COUNT(*), 2) AS never_purchased_pct
FROM customer_metrics
GROUP BY churned
ORDER BY churned;
