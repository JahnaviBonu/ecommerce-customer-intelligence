-- =====================================================================
-- 06_reporting_layer.sql — One source of truth for customer metrics + executive KPIs
-- =====================================================================


-- 6.1 customer_360: one row per customer with every agreed definition
-- Orders are aggregated BEFORE the join to avoid fan-out.
-- The recency reference date is derived from the data (not hard-coded), so the
-- segments stay correct when new orders arrive.
CREATE OR REPLACE VIEW customer_360 AS
WITH delivered_order_metrics AS (
    SELECT
        customer_id,
        COUNT(order_id)        AS delivered_orders,
        SUM(total_amount_usd)  AS delivered_revenue,
        MIN(order_date)        AS first_order_date,
        MAX(order_date)        AS last_order_date
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY customer_id
),
reference AS (
    SELECT MAX(order_date) AS ref_date
    FROM orders
    WHERE order_status = 'Delivered'
),
customer_base AS (
    SELECT
        c.customer_id,
        c.membership_tier,
        c.acquisition_channel,
        c.country,
        COALESCE(d.delivered_orders, 0)   AS delivered_orders,
        COALESCE(d.delivered_revenue, 0)  AS delivered_revenue,
        d.first_order_date,
        d.last_order_date,
        r.ref_date - d.last_order_date    AS days_since_last_order
    FROM customers c
    LEFT JOIN delivered_order_metrics d ON c.customer_id = d.customer_id
    CROSS JOIN reference r
)
SELECT
    *,
    CASE
        WHEN delivered_orders = 0 THEN 'Never purchased'
        WHEN delivered_orders = 1 THEN 'One-time'
        ELSE 'Repeat'
    END AS customer_type,
    CASE
        WHEN last_order_date IS NULL      THEN 'Never purchased'
        WHEN days_since_last_order <= 366 THEN 'Active'      -- within one reorder cycle (median gap, 2.5a)
        WHEN days_since_last_order <= 732 THEN 'At risk'     -- missed one cycle
        ELSE 'Lapsed'                                        -- missed two or more
    END AS recency_segment
FROM customer_base;


-- 6.1 check: must match 2.5b (Lapsed 2,932 · Active 2,721 · At risk 1,748 · Never purchased 599)
SELECT recency_segment, COUNT(*) AS customers
FROM customer_360
GROUP BY recency_segment
ORDER BY customers DESC;


-- 6.2 Executive KPI summary — every value reconciles to an earlier module
-- Result: 8,000 customers · 7,401 purchasers · $2,585,126.50 delivered revenue ·
--         $349.29 per purchasing customer · 78.15% repeat · 34.01% active · 21.85% at risk ·
--         $126.12 AOV · 8.08% return rate · 5.41% discount cost
WITH customer_kpis AS (
    SELECT
        COUNT(*)                                                   AS total_customers,
        COUNT(*) FILTER (WHERE delivered_orders >= 1)              AS purchasing_customers,
        SUM(delivered_revenue)                                     AS delivered_revenue,
        ROUND(SUM(delivered_revenue)
              / NULLIF(COUNT(*) FILTER (WHERE delivered_orders >= 1), 0), 2)       AS revenue_per_purchasing_customer,
        ROUND(COUNT(*) FILTER (WHERE customer_type = 'Repeat') * 100.0
              / NULLIF(COUNT(*) FILTER (WHERE delivered_orders >= 1), 0), 2)       AS repeat_rate_pct,
        ROUND(COUNT(*) FILTER (WHERE recency_segment = 'Active')  * 100.0 / COUNT(*), 2) AS active_pct,
        ROUND(COUNT(*) FILTER (WHERE recency_segment = 'At risk') * 100.0 / COUNT(*), 2) AS at_risk_pct
    FROM customer_360
),
order_kpis AS (
    SELECT
        ROUND(AVG(total_amount_usd) FILTER (WHERE order_status = 'Delivered'), 2)  AS avg_order_value,
        ROUND(COUNT(*) FILTER (WHERE returned = 1) * 100.0 / NULLIF(COUNT(*), 0), 2) AS return_rate_pct,
        ROUND(SUM(discount_amount_usd) FILTER (WHERE order_status = 'Delivered') * 100.0
              / NULLIF(SUM(subtotal_usd) FILTER (WHERE order_status = 'Delivered'), 0), 2) AS discount_pct_of_sales
    FROM orders
)
SELECT
    c.total_customers,
    c.purchasing_customers,
    ROUND(c.delivered_revenue, 2) AS delivered_revenue,
    c.revenue_per_purchasing_customer,
    c.repeat_rate_pct,
    c.active_pct,
    c.at_risk_pct,
    o.avg_order_value,
    o.return_rate_pct,
    o.discount_pct_of_sales
FROM customer_kpis c
CROSS JOIN order_kpis o;
