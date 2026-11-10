-- =====================================================================
-- 04_product_performance.sql — Which products and categories drive the business?
-- =====================================================================


-- 4.1 Category ranking by order volume (RANK vs DENSE_RANK vs ROW_NUMBER)
SELECT
    category,
    COUNT(*)                                     AS orders,
    RANK()       OVER (ORDER BY COUNT(*) DESC)   AS rank_with_gaps,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC)   AS rank_no_gaps,
    ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)   AS row_num
FROM orders
WHERE order_status = 'Delivered'
GROUP BY category
ORDER BY orders DESC;


-- 4.2 Top 3 products per category by delivered revenue (PARTITION BY)
WITH product_sales AS (
    SELECT category, product_name,
           COUNT(*)              AS orders,
           SUM(total_amount_usd) AS revenue
    FROM orders
    WHERE order_status = 'Delivered'
    GROUP BY category, product_name
),
ranked AS (
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
    FROM product_sales
)
SELECT category, product_name, orders, ROUND(revenue, 2) AS revenue, rank_in_category
FROM ranked
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;


-- 4.3 Category economics (product_summary; averages are unweighted across products)
SELECT
    category,
    COUNT(*)                          AS products,
    SUM(total_orders)                 AS orders,
    ROUND(SUM(total_revenue_usd), 2)  AS revenue,
    ROUND(AVG(avg_price), 2)          AS avg_price,
    ROUND(AVG(avg_rating), 2)         AS avg_rating,
    ROUND(AVG(return_rate), 2)        AS avg_return_rate_pct,
    ROUND(AVG(avg_discount_pct), 2)   AS avg_discount_pct
FROM product_summary
GROUP BY category
ORDER BY revenue DESC;


-- 4.4 Product quadrant: revenue vs rating, split at the medians
-- Boundary rule: values ON the median count as "above" (>=); ties at rating 4.01 affect placement.
-- Finding: above-median-revenue products (Star + Cash cow) = 83% of revenue.
--          Ratings span only 3.60–4.23, so the rating axis barely separates products.
WITH medians AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_revenue_usd) AS median_revenue,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_rating)        AS median_rating
    FROM product_summary
),
quadrants AS (
    SELECT
        p.*,
        CASE
            WHEN p.total_revenue_usd >= m.median_revenue AND p.avg_rating >= m.median_rating THEN 'Star'
            WHEN p.total_revenue_usd >= m.median_revenue                                     THEN 'Cash cow at risk'
            WHEN p.avg_rating >= m.median_rating                                             THEN 'Hidden gem'
            ELSE 'Problem'
        END AS quadrant
    FROM product_summary p
    CROSS JOIN medians m
)
SELECT
    quadrant,
    COUNT(*)                                                         AS products,
    ROUND(SUM(total_revenue_usd), 2)                                 AS revenue,
    ROUND(SUM(total_revenue_usd) * 100.0 / SUM(SUM(total_revenue_usd)) OVER (), 1) AS pct_of_revenue,
    ROUND(AVG(avg_rating), 2)                                        AS avg_rating,
    ROUND(AVG(return_rate), 2)                                       AS avg_return_rate_pct
FROM quadrants
GROUP BY quadrant
ORDER BY revenue DESC;


-- 4.5 Revenue concentration (Pareto)
-- Finding: 63 of 140 products (45%) generate 80% of revenue — flatter than 80/20.
--          The top 10 products are all Electronics (36.6% of revenue): category mix drives revenue.
WITH ranked AS (
    SELECT
        category,
        product_name,
        total_revenue_usd,
        ROW_NUMBER() OVER (ORDER BY total_revenue_usd DESC)                         AS product_rank,
        SUM(total_revenue_usd) OVER (ORDER BY total_revenue_usd DESC
                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
          * 100.0 / SUM(total_revenue_usd) OVER ()                                 AS cumulative_revenue_pct
    FROM product_summary
)
SELECT
    MIN(product_rank)                                       AS products_to_reach_80pct,
    ROUND(MIN(product_rank) * 100.0 / (SELECT COUNT(*) FROM product_summary), 1) AS pct_of_catalogue
FROM ranked
WHERE cumulative_revenue_pct >= 80;
