-- UP
CREATE INDEX IF NOT EXISTS idx_categories_name ON categories (name);
-- DOWN
DROP INDEX IF EXISTS idx_categories_name;