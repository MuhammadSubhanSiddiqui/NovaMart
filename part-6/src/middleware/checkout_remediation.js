/**
 * REMEDIATION: Phantom Inventory & Deadlock Storm
 * Replaces the broken read-decide-write loop and fixes the lock ordering hierarchy.
 */
async function placeOrderSecurely(dbClient, customerId, storeId, items) {
    try {
        await dbClient.query('BEGIN');

        // DEADLOCK REMEDIATION: Force lock acquisition order to match the 3rd-party cancellation module.
        // Rule: ALWAYS lock OrderItems (or the parent Order) BEFORE Inventory.

        const orderRes = await dbClient.query(
            `INSERT INTO Orders (customer_id, status) VALUES ($1, 'PENDING') RETURNING order_id`,
            [customerId]
        );
        const orderId = orderRes.rows[0].order_id;

        for (const item of items) {
            // Step 1: Insert/Lock OrderItems FIRST
            await dbClient.query(
                `INSERT INTO OrderItems (order_id, product_id, qty) VALUES ($1, $2, $3)`,
                [orderId, item.productId, item.qty]
            );

            // Step 2: Atomic Inventory Decrement SECOND (Phantom Inventory Fix)
            // This replaces the non-isolated SELECT -> UPDATE flow.
            const invRes = await dbClient.query(
                `UPDATE Inventory 
                 SET stock = stock - $1 
                 WHERE store_id = $2 AND product_id = $3 AND stock >= $1 
                 RETURNING stock`,
                [item.qty, storeId, item.productId]
            );

            if (invRes.rowCount === 0) {
                // The DB engine prevented negative stock automatically.
                throw new Error(`Insufficient inventory for product ${item.productId}`);
            }
        }

        await dbClient.query('COMMIT');
        return orderId;
    } catch (error) {
        await dbClient.query('ROLLBACK');
        throw error;
    }
}

/**
 * REMEDIATION: NovaPay Lost Updates (Optimistic Concurrency Control)
 */
async function adjustAvailableCredit(dbClient, customerId, adjustmentAmount, currentVersion) {
    // The query enforces the version check atomically.
    const res = await dbClient.query(
        `UPDATE Customers 
         SET available_credit = available_credit + $1, 
             version = version + 1 
         WHERE customer_id = $2 AND version = $3 
         RETURNING available_credit, version`,
        [adjustmentAmount, customerId, currentVersion]
    );

    if (res.rowCount === 0) {
        // A concurrent transaction beat us to the update.
        // Throw a specific error so the upstream controller can re-fetch and retry.
        throw new Error('CONCURRENCY_CONFLICT_RETRY');
    }

    return res.rows[0];
}

module.exports = {
    placeOrderSecurely,
    adjustAvailableCredit,
};