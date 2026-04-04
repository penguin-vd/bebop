-- UP
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders (customer);
-- DOWN
DROP INDEX IF EXISTS idx_orders_customer;