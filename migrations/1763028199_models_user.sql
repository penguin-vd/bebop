ALTER TABLE models_user ADD COLUMN role_id INTEGER REFERENCES models_role(id);
