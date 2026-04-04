-- UP
CREATE INDEX IF NOT EXISTS idx_order_lines_order_id_product_id ON order_lines (order_id, product_id);
-- DOWN
DROP INDEX IF EXISTS idx_order_lines_order_id_product_id;