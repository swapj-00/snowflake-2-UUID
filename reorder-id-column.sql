-- Ensure UUID generation functions are available
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
DECLARE
    r RECORD;
    col RECORD;
    v_columns TEXT;
    v_schema TEXT := 'public';
BEGIN
    -- Loop through all tables that have an "id" column
    FOR r IN
        SELECT DISTINCT table_name
        FROM information_schema.columns
        WHERE table_schema = v_schema
          AND column_name = 'id'
    LOOP
        RAISE NOTICE 'Processing table: %', r.table_name;

        -- Get all columns except id in correct order
        SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
        INTO v_columns
        FROM information_schema.columns
        WHERE table_schema = v_schema
          AND table_name = r.table_name
          AND column_name <> 'id';

        -- Rename old table
        EXECUTE format('ALTER TABLE %I.%I RENAME TO %I_old;', v_schema, r.table_name, r.table_name);

        -- Create new table with UUID id first
        EXECUTE format('CREATE TABLE %I.%I (id UUID PRIMARY KEY DEFAULT gen_random_uuid());',
                       v_schema, r.table_name);

        -- Add back all other columns
        FOR col IN
            SELECT column_name, data_type, is_nullable, column_default, udt_name
            FROM information_schema.columns
            WHERE table_schema = v_schema
              AND table_name = r.table_name || '_old'
              AND column_name <> 'id'
            ORDER BY ordinal_position
        LOOP
            EXECUTE format('ALTER TABLE %I.%I ADD COLUMN %I %s %s %s;',
                v_schema,
                r.table_name,
                col.column_name,
                -- Use udt_name for user-defined types (PostGIS geometry, enums, etc.)
                CASE 
                    WHEN col.data_type = 'USER-DEFINED' THEN col.udt_name
                    ELSE col.data_type
                END,
                CASE WHEN col.column_default IS NOT NULL THEN 'DEFAULT ' || col.column_default ELSE '' END,
                CASE WHEN col.is_nullable = 'NO' THEN 'NOT NULL' ELSE '' END
            );
        END LOOP;

        -- Copy data over (generate new UUIDs)
        IF v_columns IS NOT NULL AND v_columns <> '' THEN
            EXECUTE format('INSERT INTO %I.%I (id, %s) SELECT gen_random_uuid(), %s FROM %I.%I_old;',
                v_schema, r.table_name, v_columns, v_columns, v_schema, r.table_name);
        ELSE
            -- Table had only id column
            EXECUTE format('INSERT INTO %I.%I (id) SELECT gen_random_uuid() FROM %I.%I_old;',
                v_schema, r.table_name, v_schema, r.table_name);
        END IF;

        -- Drop old table
        EXECUTE format('DROP TABLE %I.%I_old;', v_schema, r.table_name);

        RAISE NOTICE ' Migrated table: %', r.table_name;
    END LOOP;
END $$;
