-- Ensure UUID generation functions are available
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
DECLARE 
    r RECORD;
    pk_name TEXT;
BEGIN
    FOR r IN 
        SELECT 
            c.table_schema,
            c.table_name
        FROM information_schema.columns c
        JOIN information_schema.table_constraints t
            ON c.table_name = t.table_name 
            AND c.table_schema = t.table_schema
        JOIN information_schema.key_column_usage k
            ON t.constraint_name = k.constraint_name
        WHERE c.column_name = 'id'
          AND t.constraint_type = 'PRIMARY KEY'
          AND c.table_schema = 'public'
    LOOP
        RAISE NOTICE 'Migrating table: %.%', r.table_schema, r.table_name;
        
        -- Add new UUID column
        EXECUTE format('ALTER TABLE %I.%I ADD COLUMN id_uuid UUID;', r.table_schema, r.table_name);
        
        -- Populate UUIDs
        EXECUTE format('UPDATE %I.%I SET id_uuid = gen_random_uuid();', r.table_schema, r.table_name);
        
        -- Drop the old PK constraint
        SELECT constraint_name INTO pk_name
        FROM information_schema.table_constraints
        WHERE table_schema = r.table_schema 
          AND table_name = r.table_name
          AND constraint_type = 'PRIMARY KEY'
        LIMIT 1;
        
        IF pk_name IS NOT NULL THEN
            EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I;', r.table_schema, r.table_name, pk_name);
        END IF;
        
        -- Drop old column and rename new
        EXECUTE format('ALTER TABLE %I.%I DROP COLUMN id;', r.table_schema, r.table_name);
        EXECUTE format('ALTER TABLE %I.%I RENAME COLUMN id_uuid TO id;', r.table_schema, r.table_name);
        
        -- Add new PK
        EXECUTE format('ALTER TABLE %I.%I ADD PRIMARY KEY (id);', r.table_schema, r.table_name);
        
        RAISE NOTICE 'Migrated table: %.%', r.table_schema, r.table_name;
    END LOOP;
END $$;
