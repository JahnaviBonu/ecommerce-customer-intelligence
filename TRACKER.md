# Project Tracker

Single source of truth for what's done, what's wrong, and what's left. Every result below was re-run against the raw CSVs on 10 Nov 2026. No analysis gets added unless it answers a new business question.

**Legend:** ✅ Verified · ⚠️ Redo / reframe · 🔲 To do

**Progress:** 41 items · 17 ✅ · 5 ⚠️ · 19 🔲

---

## Module 0 — Setup
| # | Item | Status | Notes |
|---|---|---|---|
| 0.1 | PostgreSQL 18 + pgAdmin, DB loaded via `\copy` | ✅ | 4 tables, row counts match CSVs |
| 0.2 | `00_schema.sql` (CREATE TABLE + keys) in repo | 🔲 | |

## Module 1 — Data audit
| # | Check | Status | Result |
|---|---|---|---|
| 1.1 | Row counts | ✅ | customers 8,000 · orders 25,000 · product_summary 140 · monthly_revenue 75 |
| 1.2 | Orders without a customer | ✅ | 0 |
| 1.3 | Customers with no orders | ✅ | 337 never ordered; 599 have no *delivered* order |
| 1.4 | `returned` flag vs `order_status = 'Returned'` | ✅ | 2,020 both, 0 mismatches |
| 1.5 | `monthly_revenue` vs orders | ✅ | Equals delivered orders exactly ($2,585,126.50 · 20,497 orders) |
| 1.6 | `product_summary` vs orders | ✅ | Equals non-cancelled orders (23,544) · $2.96M |
| 1.7 | `customers` aggregate columns vs orders | ⚠️ | **Don't reconcile.** `total_spend_usd` sums to $12.47M vs $3.14M in orders (4×); `total_orders` averages 16.6 vs 3.1 actual; only 5% of customers match. Rule: use orders for all spend/frequency metrics |
| 1.8 | Audit write-up + `01_data_audit.sql` | 🔲 | |

## Module 2 — Customer analytics
| # | Business question | Status | Result / fix |
|---|---|---|---|
| 2.1 | Customer mix by membership tier | ✅ | Free 55.5% · Silver 21.7% · Gold 14.7% · Platinum 8.1% |
| 2.2 | Revenue share by tier | ⚠️ | ChatGPT used `customers.total_spend_usd` (unreliable). From orders: revenue share ≈ customer share; **~$320 per customer in every tier**. "Platinum spends 87% more" is false |
| 2.3 | Repeat rate by tier | ⚠️ | 94–95% came from `customers.total_orders`. From delivered orders: **72–74%, flat across tiers** |
| 2.4 | Purchase frequency distribution | ✅ | 0: 599 · 1: 1,617 · 2–5: 5,407 · 6–10: 377 |
| 2.5 | Recency segmentation | ⚠️ | Counts correct (181+ days = 5,918). Reframe: median gap between orders is **366 days**, so 181+ is normal, not "inactive". Re-bucket using the purchase cycle |
| 2.6 | One-time vs repeat value | ✅ | Repeat: 78% of buyers, 92% of revenue, $411 vs $127 per customer; same AOV (~$126) → frequency drives value |
| 2.7 | Cohort retention (first-purchase month) | ✅ | Query ran (2,737 rows); headline numbers to re-check at packaging |
| 2.8 | Acquisition channel → customer value | 🔲 | Using orders, not customer-table spend |
| 2.9 | `churned` label: what does it actually mean? | 🔲 | 715 churned; test vs recency/frequency |

## Module 3 — Orders & operations
| # | Business question | Status | Result |
|---|---|---|---|
| 3.1 | Order status mix | ✅ | Delivered 82.0% · Returned 8.1% · Cancelled 5.8% · Processing 4.1% |
| 3.2 | Returns by category (rate vs share) | ✅ | Highest rate Pet Supplies 9.3%; most returns Electronics (18% of all) |
| 3.3 | Discount effectiveness (revenue, AOV, returns by discount band) | 🔲 | Only min/max checked (0–50%, 9 levels) |
| 3.4 | Delivery days → rating & returns | 🔲 | |
| 3.5 | Cancellations: by payment method / device | 🔲 | |
| 3.6 | Funnel signals: pages viewed, session time → order value | 🔲 | |

## Module 4 — Product performance
| # | Business question | Status | Result |
|---|---|---|---|
| 4.1 | Category ranking by volume (RANK / DENSE_RANK / ROW_NUMBER) | ✅ | |
| 4.2 | Top 3 products per category (PARTITION BY) | ✅ | |
| 4.3 | Category economics (`product_summary`) | ✅ | Ran; uses unweighted averages — note in README |
| 4.4 | Product quadrant: revenue vs rating vs return rate | 🔲 | |
| 4.5 | Revenue concentration (Pareto: % revenue from top 20% products) | 🔲 | |

## Module 5 — Revenue trends
| # | Business question | Status | Result |
|---|---|---|---|
| 5.1 | Monthly revenue + MoM growth (LAG) | ✅ | |
| 5.2 | Steepest decline: Nov 2025 | ⚠️ | −29.5% is right, but it's −1.8 SD (within normal swings). Jewelry fell on 19 → 7 orders; Electronics orders *rose* 48 → 50 (cheaper mix). Reframe as price/mix, not demand |
| 5.3 | Running total + 3-month rolling average | 🔲 | Started, never finished |
| 5.4 | Seasonality (month-of-year, quarter) + YoY growth | 🔲 | |

## Module 6 — Integrated reporting
| # | Item | Status |
|---|---|---|
| 6.1 | `customer_360` view (orders + customers) | 🔲 |
| 6.2 | Executive KPI summary query (one row of headline metrics) | 🔲 |

## Module 7 — Packaging
| # | Item | Status |
|---|---|---|
| 7.1 | Numbered `.sql` files per module | 🔲 |
| 7.2 | README: problem, findings, recommendations, limitations | 🔲 |
| 7.3 | 3–4 charts in `results/` | 🔲 |
| 7.4 | Resume bullets with real numbers | 🔲 |
| 7.5 | Case-study page for portfolio site | 🔲 |
