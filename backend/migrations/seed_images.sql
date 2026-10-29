UPDATE businesses SET cover_photo_url = 'http://172.18.160.150/media/businesses/shree_hardware.jpg' WHERE slug = 'shree-hardware-electricals';
UPDATE businesses SET cover_photo_url = 'http://172.18.160.150/media/businesses/city_medical.jpg' WHERE slug = 'city-medical-store';
UPDATE businesses SET cover_photo_url = 'http://172.18.160.150/media/businesses/ramesh_electrician.jpg' WHERE slug = 'ramesh-electrical-services';
UPDATE businesses SET cover_photo_url = 'http://172.18.160.150/media/businesses/green_valley_grocery.jpg' WHERE slug = 'green-valley-grocery';
UPDATE businesses SET cover_photo_url = 'http://172.18.160.150/media/businesses/techpulse_mobiles.jpg' WHERE slug = 'techpulse-mobiles-gadgets';

UPDATE products SET image_url = 'http://172.18.160.150/media/products/copper_wire.jpg' WHERE name ILIKE '%copper wire%';
UPDATE products SET image_url = 'http://172.18.160.150/media/products/pvc_pipe.jpg' WHERE name ILIKE '%pvc pipe%';
