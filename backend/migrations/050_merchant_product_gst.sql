ALTER TABLE products
    ADD COLUMN gst_rate_bps INTEGER CHECK (gst_rate_bps BETWEEN 0 AND 10000);
