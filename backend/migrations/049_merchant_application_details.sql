CREATE TABLE merchant_application_details (
    business_id UUID PRIMARY KEY REFERENCES businesses(id) ON DELETE CASCADE,
    details JSONB NOT NULL CHECK (jsonb_typeof(details) = 'object')
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'abashyaka_api') THEN
        GRANT SELECT, INSERT ON merchant_application_details TO abashyaka_api;
    END IF;
END;
$$;
