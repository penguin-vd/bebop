-- UP
CREATE INDEX IF NOT EXISTS idx_products_name ON products (name);
-- DOWN
DROP INDEX IF EXISTS idx_products_name;