-- UP
CREATE INDEX IF NOT EXISTS idx_orders_reference ON orders (reference);
-- DOWN
DROP INDEX IF EXISTS idx_orders_reference;