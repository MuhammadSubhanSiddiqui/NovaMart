-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║                                                                            ║
-- ║   NOVAMART — PART 9: THE WAREHOUSE AND WHAT IT REPORTS                     ║
-- ║                                                                            ║
-- ║   Database Engine  : Microsoft SQL Server (T-SQL)                          ║
-- ║   Target           : NovaMart Data Warehouse (OLAP / Star Schema)          ║
-- ║   Execution Order  : Run sections sequentially (9.1 through 9.8)           ║
-- ║                                                                            ║
-- ║   PROBLEM INVENTORY:                                                       ║
-- ║     9.1  Revenue excludes refunds              (~PKR 340M overstatement)   ║
-- ║     9.2  Revenue includes cancelled orders      (1-3 day inflation)        ║
-- ║     9.3  Revenue excludes promotional discounts (unknown % overstatement)  ║
-- ║     9.4  Customer_Dim is Type 1 SCD             (14% Karachi overstate)    ║
-- ║     9.5  Tax filing uses wrong date dimension   (PKR 48M Q3 discrepancy)  ║
-- ║     9.6  Basket size understated 34%            (~PKR 12M commissions)     ║
-- ║     9.7  Inventory turnover understated 40%     (22% storage cost rise)    ║
-- ║     9.8  NovaPay default rate: 7.8% vs 3.2%    (PKR 420M over-reserved)   ║
-- ║                                                                            ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝

USE [NovaMart_DW];   -- Adjust to your warehouse database name
GO


-- ════════════════════════════════════════════════════════════════════════════════
-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  9.1 / 9.2 / 9.3  REVENUE COMPUTATION ERRORS                              │
-- │                                                                            │
-- │  Root Causes:                                                              │
-- │    9.1 — ETL never joined the Refunds table → 8.4% overstatement          │
-- │    9.2 — Cancellation job ran AFTER ETL → stale cancelled orders loaded    │
-- │    9.3 — Promotions table never integrated → discounts ignored             │
-- │                                                                            │
-- │  Solution: Rewrite the Sales_Fact ETL as a single stored procedure.        │
-- └──────────────────────────────────────────────────────────────────────────────┘

CREATE OR ALTER PROCEDURE dbo.ETL_Sales_Fact_Load
AS
BEGIN
    SET NOCOUNT ON;

    -- ── Step 1: Gross revenue with cancellation filter (fixes 9.2) ──
    ;WITH GrossRevenue AS (
        SELECT
            o.order_id,
            o.customer_id,
            o.order_date,
            o.ship_date,
            o.payment_received_date,
            o.store_id,
            o.channel,
            SUM(oi.unit_price * oi.qty) AS gross_amount
        FROM Orders o
        INNER JOIN OrderItems oi ON o.order_id = oi.order_id
        WHERE o.status NOT IN ('cancelled', 'cancelled_inventory', 'cancelled_fraud')
        GROUP BY o.order_id, o.customer_id, o.order_date, o.ship_date,
                 o.payment_received_date, o.store_id, o.channel
    ),

    -- ── Step 2: Refunds per order (fixes 9.1) ──
    RefundAmounts AS (
        SELECT
            order_id,
            SUM(refund_amount) AS total_refunds
        FROM Refunds
        GROUP BY order_id
    ),

    -- ── Step 3: Promotional discounts per order (fixes 9.3) ──
    DiscountAmounts AS (
        SELECT
            op.order_id,
            SUM(p.discount_amount) AS total_discounts
        FROM Order_Promotions op
        INNER JOIN Promotions p ON op.promotion_id = p.promotion_id
        GROUP BY op.order_id
    )

    -- ── Step 4: Net revenue = gross − refunds − discounts ──
    INSERT INTO Sales_Fact (
        order_id, customer_key, time_key, store_key, channel,
        gross_revenue, refund_amount, discount_amount, net_revenue,
        order_date, ship_date, payment_received_date
    )
    SELECT
        gr.order_id,
        cd.customer_key,
        td.time_key,
        sd.store_key,
        gr.channel,
        gr.gross_amount                                                                   AS gross_revenue,
        COALESCE(ra.total_refunds,  0)                                                    AS refund_amount,
        COALESCE(da.total_discounts, 0)                                                   AS discount_amount,
        gr.gross_amount - COALESCE(ra.total_refunds, 0) - COALESCE(da.total_discounts, 0) AS net_revenue,
        gr.order_date,
        gr.ship_date,
        gr.payment_received_date
    FROM GrossRevenue gr
    LEFT JOIN RefundAmounts ra   ON gr.order_id = ra.order_id
    LEFT JOIN DiscountAmounts da ON gr.order_id = da.order_id
    -- Type 2 SCD join: pick the customer record that was current at order time
    INNER JOIN Customer_Dim cd
        ON gr.customer_id = cd.customer_id
        AND CAST(gr.order_date AS DATE) BETWEEN cd.effective_from AND cd.effective_to
    INNER JOIN Time_Dim td  ON CAST(gr.order_date AS DATE) = td.full_date
    INNER JOIN Store_Dim sd ON gr.store_id = sd.store_id
    WHERE gr.order_id NOT IN (SELECT order_id FROM Sales_Fact);  -- incremental load

END;
GO

/*
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  ETL SCHEDULING FIX (addresses 9.2)                                        │
 │                                                                            │
 │  OLD (broken):                                                             │
 │    2:00 AM — ETL runs (loads uncancelled orders that are still pending)     │
 │    3:00 AM — Cancellation processing runs                                  │
 │                                                                            │
 │  NEW (remediated):                                                         │
 │    1:30 AM — Cancellation processing (clears all pending cancellations)    │
 │    2:00 AM — ETL runs (cancellations already reflected in source)          │
 │    3:00 AM — Verification job (cross-checks ETL output vs OLTP source)    │
 └──────────────────────────────────────────────────────────────────────────────┘
*/


-- ════════════════════════════════════════════════════════════════════════════════
-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  9.4  CUSTOMER_DIM: TYPE 1 → TYPE 2 SCD CONVERSION                        │
-- │                                                                            │
-- │  Root Cause: Type 1 SCD overwrites city on address change.                │
-- │    • 23% of customers changed cities.                                     │
-- │    • Historical purchases misattributed to current city.                  │
-- │    • Karachi overstated 14%, Peshawar understated 19%.                    │
-- │                                                                            │
-- │  Reference: Kimball & Ross (2013) "The Data Warehouse Toolkit"            │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- ── Step 1: Alter Customer_Dim for Type 2 SCD ──
ALTER TABLE Customer_Dim ADD effective_from  DATE;
ALTER TABLE Customer_Dim ADD effective_to    DATE;
ALTER TABLE Customer_Dim ADD is_current      BIT DEFAULT 1;
GO

-- The surrogate key (customer_key) already exists.
-- A single customer_id can now have multiple rows (one per historical version).

-- ── Step 2: Backfill effective dates for existing records ──
UPDATE Customer_Dim
SET effective_from = COALESCE(
        (SELECT MIN(order_date) FROM Sales_Fact sf WHERE sf.customer_key = Customer_Dim.customer_key),
        '2023-01-01'    -- fallback: system migration date
    ),
    effective_to = '9999-12-31',
    is_current   = 1;
GO

-- ── Step 3: Type 2 SCD ETL procedure ──
CREATE OR ALTER PROCEDURE dbo.ETL_Customer_Dim_SCD2
AS
BEGIN
    SET NOCOUNT ON;

    -- Detect attribute changes from the staging table
    ;WITH SourceChanges AS (
        SELECT
            s.customer_id,
            s.first_name,
            s.last_name,
            s.email,
            s.city,
            s.province
        FROM staging_customers s        -- loaded nightly from OLTP
    )

    -- Close existing records where city or province has changed
    UPDATE cd
    SET cd.effective_to = CAST(GETDATE() AS DATE),
        cd.is_current   = 0
    FROM Customer_Dim cd
    INNER JOIN SourceChanges sc ON cd.customer_id = sc.customer_id
    WHERE cd.is_current = 1
      AND (cd.city <> sc.city OR cd.province <> sc.province);

    -- Insert new versioned records for changed customers
    INSERT INTO Customer_Dim (
        customer_id, first_name, last_name, email, city, province,
        effective_from, effective_to, is_current
    )
    SELECT
        sc.customer_id, sc.first_name, sc.last_name, sc.email,
        sc.city, sc.province,
        CAST(GETDATE() AS DATE),        -- effective_from = today
        '9999-12-31',                    -- effective_to   = far future
        1                                -- is_current     = true
    FROM SourceChanges sc
    INNER JOIN Customer_Dim cd ON sc.customer_id = cd.customer_id
    WHERE cd.is_current = 0
      AND cd.effective_to = CAST(GETDATE() AS DATE)     -- just closed above
      AND NOT EXISTS (
          SELECT 1 FROM Customer_Dim cd2
          WHERE cd2.customer_id = sc.customer_id AND cd2.is_current = 1
      );

    -- Insert brand new customers (first appearance)
    INSERT INTO Customer_Dim (
        customer_id, first_name, last_name, email, city, province,
        effective_from, effective_to, is_current
    )
    SELECT
        sc.customer_id, sc.first_name, sc.last_name, sc.email,
        sc.city, sc.province,
        CAST(GETDATE() AS DATE), '9999-12-31', 1
    FROM SourceChanges sc
    WHERE NOT EXISTS (
        SELECT 1 FROM Customer_Dim cd WHERE cd.customer_id = sc.customer_id
    );
END;
GO


-- ════════════════════════════════════════════════════════════════════════════════
-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  9.5  TAX FILING DATE FIX (order_date vs payment_received_date)            │
-- │                                                                            │
-- │  Root Cause: Tax filing joined on order_date (accrual) instead of          │
-- │              payment_received_date (cash basis) → PKR 48M Q3 discrepancy. │
-- │                                                                            │
-- │  Solution: Add a second time dimension key (payment_time_key) to           │
-- │            Sales_Fact so both perspectives are available.                  │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- ── Step 1: Schema change ──
ALTER TABLE Sales_Fact ADD payment_time_key INT;
GO

-- ── Step 2: Populate payment_time_key from existing data ──
UPDATE sf
SET sf.payment_time_key = td.time_key
FROM Sales_Fact sf
INNER JOIN Time_Dim td ON CAST(sf.payment_received_date AS DATE) = td.full_date;
GO

-- ── Step 3: Tax reporting query (cash basis — uses payment_received_date) ──
SELECT
    td.fiscal_quarter,
    td.fiscal_year,
    SUM(sf.net_revenue) AS revenue_for_tax
FROM Sales_Fact sf
INNER JOIN Time_Dim td ON sf.payment_time_key = td.time_key
GROUP BY td.fiscal_quarter, td.fiscal_year
ORDER BY td.fiscal_year, td.fiscal_quarter;

-- ── Step 4: Management reporting query (accrual basis — uses order_date) ──
SELECT
    td.fiscal_quarter,
    td.fiscal_year,
    SUM(sf.net_revenue) AS revenue_for_reporting
FROM Sales_Fact sf
INNER JOIN Time_Dim td ON sf.time_key = td.time_key
GROUP BY td.fiscal_quarter, td.fiscal_year
ORDER BY td.fiscal_year, td.fiscal_quarter;


-- ════════════════════════════════════════════════════════════════════════════════
-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  9.6  BASKET SIZE — POS TRANSACTION FRAGMENTATION                          │
-- │                                                                            │
-- │  Root Cause: POS systems split single visits into multiple transactions    │
-- │              (terminal timeouts, split payments, network recovery).        │
-- │    • order_count inflated ~34% → basket_size understated 34%.             │
-- │    • Store manager commissions underpaid by ~PKR 12M.                     │
-- │                                                                            │
-- │  Solution: Group transactions into logical "visits" using a 15-minute     │
-- │            session window per customer + store.                            │
-- └──────────────────────────────────────────────────────────────────────────────┘

GO
CREATE OR ALTER VIEW dbo.vw_Retail_Visits
AS
WITH OrdersWithGaps AS (
    SELECT
        order_id,
        customer_id,
        store_id,
        order_date,
        total_amount,
        CASE
            WHEN DATEDIFF(MINUTE,
                     LAG(order_date) OVER (PARTITION BY customer_id, store_id ORDER BY order_date),
                     order_date
                 ) > 15
              OR LAG(order_date) OVER (PARTITION BY customer_id, store_id ORDER BY order_date) IS NULL
            THEN 1
            ELSE 0
        END AS new_visit_flag
    FROM Orders
    WHERE channel = 'retail'
),
VisitGrouped AS (
    SELECT
        *,
        SUM(new_visit_flag) OVER (
            PARTITION BY customer_id, store_id
            ORDER BY order_date
            ROWS UNBOUNDED PRECEDING
        ) AS visit_group
    FROM OrdersWithGaps
)
SELECT
    customer_id,
    store_id,
    visit_group,
    MIN(order_date)      AS visit_start,
    MAX(order_date)      AS visit_end,
    COUNT(order_id)      AS transaction_count,
    SUM(total_amount)    AS visit_total,
    SUM(total_amount)    AS corrected_basket_size
FROM VisitGrouped
GROUP BY customer_id, store_id, visit_group;
GO

-- ── Corrected basket size metric ──
-- OLD formula: SUM(revenue) / COUNT(orders)          → understated by 34%
-- NEW formula: SUM(revenue) / COUNT(DISTINCT visits)
SELECT
    sd.store_name,
    td.month_name,
    SUM(sf.net_revenue)                                                       AS total_revenue,
    COUNT(DISTINCT rv.visit_group)                                            AS visit_count,
    SUM(sf.net_revenue) / NULLIF(COUNT(DISTINCT rv.visit_group), 0)           AS corrected_basket_size
FROM Sales_Fact sf
INNER JOIN Store_Dim sd ON sf.store_key = sd.store_key
INNER JOIN Time_Dim td  ON sf.time_key  = td.time_key
LEFT JOIN  dbo.vw_Retail_Visits rv
    ON sf.customer_key = rv.customer_id
    AND sf.store_key   = rv.store_id
WHERE sf.channel = 'retail'
GROUP BY sd.store_name, td.month_name
ORDER BY sd.store_name, td.month_name;

-- ── Commission recalculation (back-pay for 11 months of underpayment) ──
SELECT
    sd.store_name,
    sd.manager_name,
    SUM(sf.net_revenue) / NULLIF(COUNT(DISTINCT rv.visit_group), 0)            AS corrected_basket,
    MIN(oc.reported_basket_size)                                                AS reported_basket,
    (SUM(sf.net_revenue) / NULLIF(COUNT(DISTINCT rv.visit_group), 0)
     - MIN(oc.reported_basket_size)) * MIN(oc.commission_rate)                  AS underpayment
FROM Sales_Fact sf
INNER JOIN Store_Dim sd ON sf.store_key = sd.store_key
INNER JOIN Time_Dim td  ON sf.time_key  = td.time_key
LEFT JOIN  dbo.vw_Retail_Visits rv
    ON sf.customer_key = rv.customer_id
    AND sf.store_key   = rv.store_id
INNER JOIN dbo.Old_Commission_Reports oc
    ON sd.store_id   = oc.store_id
    AND td.month_name = oc.month_name
WHERE sf.channel = 'retail'
GROUP BY sd.store_name, sd.manager_name;


-- ════════════════════════════════════════════════════════════════════════════════
-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  9.7  INVENTORY TURNOVER — 2AM SNAPSHOT PROBLEM                            │
-- │                                                                            │
-- │  Root Cause: ETL takes a single snapshot at 2 AM (post-restock peak).     │
-- │    • Inventory appears perpetually high → turnover understated 40%.        │
-- │    • Procurement over-orders → 22% increase in storage costs.             │
-- │                                                                            │
-- │  Solution: Capture 5 snapshots daily and use the daily average.            │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- ── Step 1: Snapshot table ──
CREATE TABLE Inventory_Snapshots (
    snapshot_id       INT IDENTITY  PRIMARY KEY,
    product_id        INT           NOT NULL,
    store_id          INT           NOT NULL,
    quantity_on_hand  INT           NOT NULL,
    snapshot_time     DATETIME      NOT NULL,
    snapshot_date     DATE          NOT NULL
);
GO

-- ── Step 2: Snapshot capture procedure (schedule at 10AM, 2PM, 6PM, 10PM, 2AM) ──
CREATE OR ALTER PROCEDURE dbo.ETL_Inventory_Snapshot
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Inventory_Snapshots (product_id, store_id, quantity_on_hand, snapshot_time, snapshot_date)
    SELECT
        product_id,
        store_id,
        quantity_available,
        GETDATE(),
        CAST(GETDATE() AS DATE)
    FROM Inventory;         -- pulled from OLTP via linked server or staging
END;
GO

-- ── Step 3: Corrected inventory turnover calculation ──
-- Turnover = COGS / Average Inventory Value (across multiple daily snapshots)
SELECT
    p.product_id,
    p.product_name,
    SUM(sf.net_revenue)                                                                  AS cogs_proxy,
    AVG(isnap.quantity_on_hand * p.unit_cost)                                            AS avg_inventory_value,
    SUM(sf.net_revenue) / NULLIF(AVG(isnap.quantity_on_hand * p.unit_cost), 0)           AS corrected_turnover
FROM Sales_Fact sf
INNER JOIN Product_Dim p ON sf.product_key = p.product_key
INNER JOIN Inventory_Snapshots isnap
    ON p.product_id = isnap.product_id
    AND sf.order_date BETWEEN isnap.snapshot_date AND DATEADD(DAY, 1, isnap.snapshot_date)
GROUP BY p.product_id, p.product_name;


-- ════════════════════════════════════════════════════════════════════════════════
-- ┌──────────────────────────────────────────────────────────────────────────────┐
-- │  9.8  NOVAPAY DEFAULT RATE MISCLASSIFICATION                               │
-- │                                                                            │
-- │  Root Cause: No distinction between genuine defaults, restructured plans,  │
-- │              reversed transactions, and orphan records.                    │
-- │    • Reported default rate: 7.8%                                          │
-- │    • Actual default rate:   3.2%                                          │
-- │    • Over-provisioned reserves: ~PKR 420M                                 │
-- │                                                                            │
-- │  Solution: Proper plan status taxonomy + reclassification.                │
-- └──────────────────────────────────────────────────────────────────────────────┘

-- ── Step 1: Plan status taxonomy dimension ──
CREATE TABLE NovaPay_Plan_Status_Dim (
    status_code                  VARCHAR(20) PRIMARY KEY,
    status_category              VARCHAR(20) NOT NULL,
    include_in_default_numerator   BIT        NOT NULL,
    include_in_default_denominator BIT        NOT NULL
);

INSERT INTO NovaPay_Plan_Status_Dim
    (status_code,          status_category,  include_in_default_numerator, include_in_default_denominator)
VALUES
    ('active',             'active',         0, 1),
    ('completed',          'completed',      0, 1),
    ('defaulted',          'defaulted',      1, 1),   -- genuinely missed payments
    ('restructured',       'restructured',   0, 1),   -- terms modified, still paying
    ('restructured_default','defaulted',     1, 1),   -- restructured AND THEN defaulted
    ('reversed',           'reversed',       0, 0),   -- disputed & refunded — excluded
    ('frozen',             'frozen',         0, 0),   -- fraud-related — excluded
    ('orphan',             'orphan',         0, 0);   -- no matching customer — excluded
GO

-- ── Step 2: Reclassify existing NovaPay plans ──
UPDATE np
SET np.status_category = CASE
    WHEN np.missed_payment_count >= np.default_threshold
         AND np.restructure_date IS NULL
        THEN 'defaulted'

    WHEN np.restructure_date IS NOT NULL
         AND np.last_payment_date >= DATEADD(MONTH, -2, GETDATE())
        THEN 'restructured'

    WHEN np.restructure_date IS NOT NULL
         AND np.missed_payment_count >= np.default_threshold
        THEN 'restructured_default'

    WHEN np.reversal_date IS NOT NULL
        THEN 'reversed'

    WHEN NOT EXISTS (SELECT 1 FROM Customers c WHERE c.customer_id = np.customer_id)
        THEN 'orphan'

    ELSE np.current_status
END
FROM NovaPay_Plans np;
GO

-- ── Step 3: Corrected default rate calculation ──
SELECT
    SUM(CASE WHEN psd.include_in_default_numerator   = 1 THEN 1 ELSE 0 END) AS defaults,
    SUM(CASE WHEN psd.include_in_default_denominator = 1 THEN 1 ELSE 0 END) AS total_plans,
    CAST(SUM(CASE WHEN psd.include_in_default_numerator = 1 THEN 1 ELSE 0 END) AS FLOAT)
    / NULLIF(SUM(CASE WHEN psd.include_in_default_denominator = 1 THEN 1 ELSE 0 END), 0)
                                                                              AS corrected_default_rate
FROM NovaPay_Plans np
INNER JOIN NovaPay_Plan_Status_Dim psd ON np.status_category = psd.status_code;

-- Expected result: ~3.2% (down from the erroneous 7.8%)

/*
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  FINANCIAL IMPACT — RESERVE ADJUSTMENT                                      │
 │                                                                            │
 │  • Overstated default rate: 7.8% (reported) vs 3.2% (actual)              │
 │  • Variance: 4.6% of the NovaPay portfolio (PKR 18 Billion)               │
 │  • Maximum over-provisioned reserves: 4.6% × PKR 18B = PKR 828M           │
 │  • Auditor-estimated overstatement: PKR 420M                               │
 │  • Remediation: freed capital (PKR 420M–828M) can be redeployed into       │
 │    lending or standard cash-flow operations, alleviating liquidity strain.  │
 └──────────────────────────────────────────────────────────────────────────────┘
*/


-- ╔══════════════════════════════════════════════════════════════════════════════╗
-- ║  END OF PART 9 — The Warehouse and What It Reports                         ║
-- ╚══════════════════════════════════════════════════════════════════════════════╝
