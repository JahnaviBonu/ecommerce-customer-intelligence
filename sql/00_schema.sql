-- =====================================================================
-- 00_schema.sql — Table definitions
-- Project : E-commerce Customer Intelligence (PostgreSQL)
-- Dataset : E-Commerce Customer Behavior & Sales 2020–2026 (Kaggle)
-- Grain   : customers (1 row / customer) · orders (1 row / order)
--           product_summary (1 row / product) · monthly_revenue (1 row / month)
-- =====================================================================

DROP TABLE IF EXISTS orders, customers, product_summary, monthly_revenue;

CREATE TABLE customers (
    customer_id               VARCHAR(6) PRIMARY KEY,
    country                   VARCHAR(50),
    age                       SMALLINT,
    gender                    VARCHAR(20),
    membership_tier           VARCHAR(20),
    registration_date         DATE,
    total_orders              INTEGER,        -- does NOT reconcile with orders (see 01_data_audit)
    total_spend_usd           NUMERIC(12,2),  -- does NOT reconcile with orders (see 01_data_audit)
    avg_order_value_usd       NUMERIC(10,2),
    days_since_last_purchase  INTEGER,
    preferred_category        VARCHAR(50),
    preferred_device          VARCHAR(20),
    preferred_payment_method  VARCHAR(30),
    acquisition_channel       VARCHAR(30),
    reviews_given             INTEGER,
    avg_review_score          NUMERIC(3,1),
    returns_made              INTEGER,
    wishlist_items            INTEGER,
    newsletter_subscribed     SMALLINT,       -- 0/1
    churned                   SMALLINT        -- 0/1
);

CREATE TABLE orders (
    order_id                      VARCHAR(7) PRIMARY KEY,
    customer_id                   VARCHAR(6) REFERENCES customers(customer_id),
    order_date                    DATE,
    year                          SMALLINT,
    month                         SMALLINT,
    quarter                       VARCHAR(2),
    day_of_week                   VARCHAR(10),
    product_name                  VARCHAR(100),
    category                      VARCHAR(50),
    unit_price_usd                NUMERIC(10,2),
    quantity                      INTEGER,
    subtotal_usd                  NUMERIC(10,2),
    discount_pct                  SMALLINT,
    discount_amount_usd           NUMERIC(10,2),
    shipping_fee_usd              NUMERIC(10,2),
    tax_pct                       SMALLINT,
    tax_amount_usd                NUMERIC(10,2),
    total_amount_usd              NUMERIC(10,2),
    payment_method                VARCHAR(30),
    device_used                   VARCHAR(20),
    delivery_days                 SMALLINT,
    delivery_date                 DATE,
    order_status                  VARCHAR(20),   -- Delivered / Returned / Cancelled / Processing
    returned                      SMALLINT,      -- 0/1, identical to order_status = 'Returned'
    customer_rating               NUMERIC(2,1),  -- NULL when the customer left no rating
    session_duration_minutes      NUMERIC(6,1),
    pages_viewed_before_purchase  INTEGER,
    is_repeat_customer            SMALLINT       -- 0/1
);

CREATE TABLE product_summary (
    category            VARCHAR(50),
    product_name        VARCHAR(100),
    total_orders        INTEGER,
    total_revenue_usd   NUMERIC(12,2),
    avg_price           NUMERIC(10,2),
    avg_rating          NUMERIC(3,2),
    return_rate         NUMERIC(5,2),   -- percent (e.g. 9.5 = 9.5%)
    avg_discount_pct    NUMERIC(5,2),
    avg_delivery_days   NUMERIC(5,2),
    PRIMARY KEY (category, product_name)
);

CREATE TABLE monthly_revenue (
    year              SMALLINT,
    month             SMALLINT,
    quarter           VARCHAR(2),
    orders            INTEGER,
    revenue_usd       NUMERIC(12,2),
    avg_order_value   NUMERIC(10,2),
    avg_discount_pct  NUMERIC(5,2),
    return_rate       NUMERIC(5,2),   -- always 0: table only counts delivered orders
    unique_customers  INTEGER,
    new_customers     INTEGER,
    PRIMARY KEY (year, month)
);

-- Load (psql, run from the folder containing the CSVs):
-- \copy customers       FROM 'customers.csv'       CSV HEADER
-- \copy orders          FROM 'orders.csv'          CSV HEADER
-- \copy product_summary FROM 'product_summary.csv' CSV HEADER
-- \copy monthly_revenue FROM 'monthly_revenue.csv' CSV HEADER
