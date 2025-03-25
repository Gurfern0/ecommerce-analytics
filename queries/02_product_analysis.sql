-- Advanced Product Performance Analysis and Inventory Optimization
-- This query demonstrates complex aggregations, window functions, and statistical analysis

WITH product_metrics AS (
    -- Calculate basic product performance metrics
    SELECT 
        p.product_id,
        p.category,
        p.brand,
        COUNT(DISTINCT oi.order_id) as total_orders,
        SUM(oi.quantity) as total_quantity_sold,
        SUM(oi.quantity * oi.unit_price) as total_revenue,
        AVG(oi.unit_price) as avg_price,
        -- Calculate days between orders (for inventory planning)
        AVG(DATE_DIFF(
            LEAD(o.order_date) OVER (PARTITION BY p.product_id ORDER BY o.order_date),
            o.order_date,
            DAY
        )) as avg_days_between_orders
    FROM products p
    JOIN order_items oi USING (product_id)
    JOIN orders o USING (order_id)
    WHERE o.status = 'completed'
    GROUP BY 1, 2, 3
),

category_performance AS (
    -- Analyze category-level performance
    SELECT 
        category,
        COUNT(DISTINCT product_id) as total_products,
        SUM(total_quantity_sold) as category_quantity,
        SUM(total_revenue) as category_revenue,
        -- Calculate category market share
        SUM(total_revenue) / SUM(SUM(total_revenue)) OVER () as market_share,
        -- Calculate category growth rate
        (SUM(total_revenue) - LAG(SUM(total_revenue)) OVER (ORDER BY category)) / 
        LAG(SUM(total_revenue)) OVER (ORDER BY category) as growth_rate
    FROM product_metrics
    GROUP BY 1
),

inventory_optimization AS (
    -- Calculate inventory optimization metrics
    SELECT 
        p.product_id,
        p.category,
        -- Calculate safety stock using statistical analysis
        STDDEV(oi.quantity) * 1.96 as safety_stock,
        -- Calculate reorder point
        AVG(oi.quantity) * AVG(pm.avg_days_between_orders) + 
        (STDDEV(oi.quantity) * 1.96) as reorder_point,
        -- Calculate economic order quantity
        SQRT(
            (2 * SUM(oi.quantity * oi.unit_price) * 100) / 
            (0.2 * AVG(oi.unit_price))
        ) as economic_order_quantity
    FROM products p
    JOIN order_items oi USING (product_id)
    JOIN product_metrics pm USING (product_id)
    GROUP BY 1, 2
),

product_rankings AS (
    -- Rank products within their categories
    SELECT 
        p.product_id,
        p.category,
        pm.total_revenue,
        pm.total_quantity_sold,
        -- Calculate various rankings
        ROW_NUMBER() OVER (
            PARTITION BY p.category 
            ORDER BY pm.total_revenue DESC
        ) as revenue_rank,
        ROW_NUMBER() OVER (
            PARTITION BY p.category 
            ORDER BY pm.total_quantity_sold DESC
        ) as quantity_rank,
        -- Calculate product contribution to category
        pm.total_revenue / SUM(pm.total_revenue) OVER (PARTITION BY p.category) 
        as category_contribution
    FROM products p
    JOIN product_metrics pm USING (product_id)
)

-- Final comprehensive product analysis
SELECT 
    pr.product_id,
    pr.category,
    pm.brand,
    pm.total_orders,
    pm.total_quantity_sold,
    pm.total_revenue,
    pm.avg_price,
    -- Rankings and performance metrics
    pr.revenue_rank,
    pr.quantity_rank,
    pr.category_contribution,
    -- Inventory optimization metrics
    io.safety_stock,
    io.reorder_point,
    io.economic_order_quantity,
    -- Category performance context
    cp.market_share,
    cp.growth_rate,
    -- Calculate product health score
    (
        (pr.category_contribution * 0.3) +
        (1 / pr.revenue_rank * 0.3) +
        (1 / pr.quantity_rank * 0.2) +
        (cp.growth_rate * 0.2)
    ) as product_health_score
FROM product_rankings pr
JOIN product_metrics pm USING (product_id)
JOIN inventory_optimization io USING (product_id)
JOIN category_performance cp USING (category)
ORDER BY pr.category, pr.revenue_rank;

-- Performance Notes:
-- 1. This query uses multiple CTEs for better organization and readability
-- 2. Window functions are used for rankings and calculations
-- 3. Statistical functions (STDDEV) for inventory optimization
-- 4. Consider partitioning tables by category for better performance
-- 5. Materialize frequently accessed metrics in separate tables
-- 6. Indexes on product_id and category will improve JOIN performance 