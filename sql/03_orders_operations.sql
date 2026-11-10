-- =====================================================================
-- 03_orders_operations.sql — Where is value created or lost in the order flow?
-- =====================================================================


-- 3.1 Order status mix
-- Finding: Delivered 82.0% · Returned 8.1% · Cancelled 5.8% · Processing 4.1%.
SELECT
    order_status,
    COUNT(*)                                           AS orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;


-- 3.2 Returns by category: rate vs share of all returns
-- Finding: highest rate = Pet Supplies (9.3%, small base);
--          most returns = Electronics (18% of all returns) → different problems, different fixes.
SELECT
    category,
    COUNT(*)                                                                   AS orders,
    COUNT(*) FILTER (WHERE returned = 1)                                       AS returned_orders,
    ROUND(COUNT(*) FILTER (WHERE returned = 1) * 100.0 / COUNT(*), 2)          AS return_rate_pct,
    ROUND(COUNT(*) FILTER (WHERE returned = 1) * 100.0
          / SUM(COUNT(*) FILTER (WHERE returned = 1)) OVER (), 2)              AS pct_of_all_returns
FROM orders
GROUP BY category
ORDER BY returned_orders DESC;


-- 3.3a Discount depth vs basket size
-- Finding: quantity flat (~1.7 items); pre-discount basket FALLS $117 → $106 from 0% to 50%.
--          Discounts do not buy bigger baskets. (Association only — causality needs an A/B test.)
SELECT
    discount_pct,
    COUNT(*)                                                   AS orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)         AS pct_of_orders,
    ROUND(AVG(subtotal_usd), 2)                                AS avg_subtotal,
    ROUND(AVG(total_amount_usd), 2)                            AS avg_order_value,
    ROUND(AVG(quantity), 2)                                    AS avg_quantity,
    ROUND(COUNT(*) FILTER (WHERE returned = 1) * 100.0 / NULLIF(COUNT(*), 0), 2) AS return_rate_pct
FROM orders
GROUP BY discount_pct
ORDER BY discount_pct;


-- 3.3b Cost of discounting (delivered orders)
-- Finding: 35.0% of orders discounted · $129,478 given away · 5.4% of pre-discount sales.
SELECT
    ROUND(COUNT(*) FILTER (WHERE discount_pct > 0) * 100.0 / NULLIF(COUNT(*), 0), 2) AS pct_orders_discounted,
    ROUND(SUM(discount_amount_usd), 2)                                               AS total_discount_usd,
    ROUND(SUM(discount_amount_usd) * 100.0 / NULLIF(SUM(subtotal_usd), 0), 2)        AS discount_pct_of_sales
FROM orders
WHERE order_status = 'Delivered';


-- 3.4 Delivery speed vs ratings and returns (delivered + returned only; ratings are opt-in)
-- Finding: ratings 3.98–4.02 and returns 8.6–9.5% whether delivery takes 1 or 14 days
--          → delivery speed is not a satisfaction lever in this data.
SELECT
    delivery_days,
    COUNT(*)                                                   AS orders,
    ROUND(AVG(customer_rating), 2)                             AS avg_rating,
    COUNT(customer_rating)                                     AS rated_orders,
    ROUND(COUNT(*) FILTER (WHERE returned = 1) * 100.0 / NULLIF(COUNT(*), 0), 2) AS return_rate_pct
FROM orders
WHERE order_status IN ('Delivered', 'Returned')
GROUP BY delivery_days
ORDER BY delivery_days;


-- 3.5a Cancellations by payment method
-- Finding: 4.1% (Crypto, only 20 cancellations) to 6.2% (BNPL). Ranges overlap and the
--          impact is ~6 orders out of 25,000 → not a priority lever.
SELECT
    payment_method,
    COUNT(*)                                                                   AS orders,
    COUNT(*) FILTER (WHERE order_status = 'Cancelled')                         AS cancelled_orders,
    ROUND(COUNT(*) FILTER (WHERE order_status = 'Cancelled') * 100.0
          / NULLIF(COUNT(*), 0), 2)                                            AS cancellation_rate_pct
FROM orders
GROUP BY payment_method
ORDER BY cancellation_rate_pct DESC;


-- 3.5b Cancellations by device
-- Finding: Tablet 6.1% · Desktop 5.9% · Mobile 5.7% → no meaningful difference.
SELECT
    device_used,
    COUNT(*)                                                                   AS orders,
    COUNT(*) FILTER (WHERE order_status = 'Cancelled')                         AS cancelled_orders,
    ROUND(COUNT(*) FILTER (WHERE order_status = 'Cancelled') * 100.0
          / NULLIF(COUNT(*), 0), 2)                                            AS cancellation_rate_pct
FROM orders
GROUP BY device_used
ORDER BY cancellation_rate_pct DESC;


-- 3.6 Browsing depth vs order value (delivered orders)
-- Finding: AOV $122–$133 and session time ~16–17 min across all browsing levels → no clear link.
-- Limitation: orders only contain completed purchases, so conversion (browsed but didn't buy)
--             cannot be measured from this data.
SELECT
    CASE
        WHEN pages_viewed_before_purchase BETWEEN 1  AND 4  THEN '1-4: Very low'
        WHEN pages_viewed_before_purchase BETWEEN 5  AND 8  THEN '5-8: Low'
        WHEN pages_viewed_before_purchase BETWEEN 9  AND 12 THEN '9-12: Moderate'
        WHEN pages_viewed_before_purchase BETWEEN 13 AND 16 THEN '13-16: High'
        WHEN pages_viewed_before_purchase BETWEEN 17 AND 20 THEN '17-20: Very high'
        WHEN pages_viewed_before_purchase BETWEEN 21 AND 24 THEN '21-24: Extensive'
        ELSE 'Other'
    END                                        AS browsing_bucket,
    COUNT(*)                                   AS orders,
    ROUND(AVG(total_amount_usd), 2)            AS avg_order_value,
    ROUND(AVG(session_duration_minutes), 2)    AS avg_session_minutes
FROM orders
WHERE order_status = 'Delivered'
GROUP BY browsing_bucket
ORDER BY MIN(pages_viewed_before_purchase);
