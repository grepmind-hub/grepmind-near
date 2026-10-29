-- 002_add_cover_photo_url.sql
-- Adds cover_photo_url column to businesses table for storefront and professional imagery.

ALTER TABLE businesses ADD COLUMN IF NOT EXISTS cover_photo_url TEXT;
