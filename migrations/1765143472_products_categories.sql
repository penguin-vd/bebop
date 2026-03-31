CREATE TABLE IF NOT EXISTS products_categories (
  products_id INTEGER REFERENCES products(id) NOT NULL,
  categories_id INTEGER REFERENCES categories(id) NOT NULL,
  PRIMARY KEY (products_id, categories_id)
);