-- =====================================================================
-- 05_revenue_trends.sql — How is revenue moving over time?
-- Source: monthly_revenue (verified = delivered orders, see 01_data_audit 1.5)
-- =====================================================================


-- 5.1 Month-over-month growth (LAG)
SELECT
    year,
    month,
    revenue_usd,
    LAG(revenue_usd) OVER (ORDER BY year, month)                       AS prev_month_revenue,
    ROUND((revenue_usd - LAG(revenue_usd) OVER (ORDER BY year, month)) * 100.0
          / NULLIF(LAG(revenue_usd) OVER (ORDER BY year, month), 0), 2) AS mom_growth_pct
FROM monthly_revenue
ORDER BY year, month;


-- 5.2 Explaining the steepest drop (Nov 2025, −29.5%): volume vs order value
-- Finding: Electronics orders ROSE 48 → 50 but AOV fell $336 → $230 (cheaper mix);
--          Jewelry fell on both volume (19 → 7) and AOV ($220 → $83) — tiny sample.
--          The 3-month rolling average fell only 5.7% (5.3) → a one-off dip, not a trend.
SELECT
    category,
    DATE_TRUNC('month', order_date)  AS sales_month,
    COUNT(*)                         AS orders,
    ROUND(SUM(total_amount_usd), 2)  AS revenue,
    ROUND(AVG(total_amount_usd), 2)  AS avg_order_value
FROM orders
WHERE order_status = 'Delivered'
  AND category IN ('Electronics', 'Jewelry & Accessories')
  AND order_date >= DATE '2025-10-01'
  AND order_date <  DATE '2025-12-01'
GROUP BY category, DATE_TRUNC('month', order_date)
ORDER BY category, sales_month;


-- 5.3 Running total and 3-month rolling average (window frames)
-- Finding: rolling average sat at ~$31–36K through 2024, then stepped up to $36–41K from mid-2025.
SELECT
    year,
    month,
    revenue_usd,
    SUM(revenue_usd) OVER (ORDER BY year, month)                                   AS cumulative_revenue,
    ROUND(AVG(revenue_usd) OVER (ORDER BY year, month
                                 ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)     AS rolling_3m_avg
FROM monthly_revenue
ORDER BY year, month;


-- 5.4a Year-over-year growth (full years only; 2026 is partial and shown in 5.4b)
-- Finding: ~$400–425K a year, −6% to +3% swings until 2025 (+7.5%).
WITH yearly AS (
    SELECT year, SUM(revenue_usd) AS annual_revenue, COUNT(*) AS months
    FROM monthly_revenue
    GROUP BY year
)
SELECT
    year,
    ROUND(annual_revenue, 2)                                        AS annual_revenue,
    ROUND((annual_revenue - LAG(annual_revenue) OVER (ORDER BY year)) * 100.0
          / NULLIF(LAG(annual_revenue) OVER (ORDER BY year), 0), 2) AS yoy_growth_pct
FROM yearly
WHERE months = 12
ORDER BY year;


-- 5.4b Like-for-like: Q1 2026 vs Q1 2025
-- Finding: $99.3K → $116.2K = +17.0% — revenue is accelerating.
WITH q1 AS (
    SELECT year, SUM(revenue_usd) AS q1_revenue
    FROM monthly_revenue
    WHERE month BETWEEN 1 AND 3 AND year IN (2025, 2026)
    GROUP BY year
)
SELECT
    year,
    ROUND(q1_revenue, 2)                                            AS q1_revenue,
    ROUND((q1_revenue - LAG(q1_revenue) OVER (ORDER BY year)) * 100.0
          / NULLIF(LAG(q1_revenue) OVER (ORDER BY year), 0), 2)     AS growth_pct
FROM q1
ORDER BY year;


-- 5.4c Seasonality: average revenue by calendar month
-- Finding: $32.0K (Feb) to $36.1K (Dec), within ±6% → no meaningful seasonality.
-- Caveat: Jan–Mar include 2026 (7 years vs 6), which lifts their averages slightly.
SELECT
    month,
    TO_CHAR(TO_DATE(month::text, 'MM'), 'Mon')  AS month_name,
    COUNT(*)                                    AS years_observed,
    ROUND(AVG(revenue_usd), 2)                  AS avg_monthly_revenue
FROM monthly_revenue
GROUP BY month
ORDER BY month;
