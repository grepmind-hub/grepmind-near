-- Rider mode stays unavailable until a root-superadmin assigns the rider role.
-- This is an authorization capability only; it does not create rider profiles,
-- onboarding, dispatch, earnings, or location-tracking records.
ALTER TABLE user_roles
    DROP CONSTRAINT IF EXISTS user_roles_role_check;

ALTER TABLE user_roles
    ADD CONSTRAINT user_roles_role_check
    CHECK (role IN ('customer', 'merchant', 'professional', 'admin', 'rider'));
