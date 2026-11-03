// validate-cities exercises real local API flows with generated, owned fixtures.
// It never uses existing accounts, fixed OTPs, business IDs, or category lists.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
	"image/png"
)

type owner struct {
	ID    string
	Phone string
}
type ledger struct {
	Run           string
	CustomerPhone string
	Users         []owner
	Cases         []uiCase `json:"Cases,omitempty"`
	ImageKeys     []string `json:"ImageKeys,omitempty"`
}
type uiCase struct {
	City, CategorySlug, CategoryName, BusinessID, Phone, BusinessName           string
	Address, Locality, PostalCode, Description, ProductName, ProductDescription string
	ImageURL, OfferTitle                                                        string
	Price, Latitude, Longitude                                                  float64
}
type runner struct {
	db               *database.DB
	base, manifest   string
	ledger           ledger
	client           *http.Client
	storage          *minio.Client
	mediaBaseURL     string
	imageURLs        map[string]string
	previousMerchant string
}
type category struct {
	Slug        string `json:"slug"`
	Name        string `json:"name"`
	Description string `json:"description"`
}
type business struct {
	ID       string `json:"id"`
	City     string `json:"city"`
	Category string `json:"category_slug"`
}

func main() {
	base := flag.String("api", "http://127.0.0.1:8080/api/v1", "Local API URL")
	cities := flag.String("cities", "", "Required comma-separated target cities")
	manifest := flag.String("manifest", "city-validation-run.json", "Recovery manifest; contains fixture IDs, never tokens")
	cleanup := flag.Bool("cleanup", false, "Clean only fixture users recorded in the manifest")
	allow := flag.Bool("allow-local-fixtures", false, "Explicitly permit generated fixtures in the local database")
	prepareUI := flag.Bool("prepare-ui", false, "Prepare generated stores for UI injection; keep manifest for subsequent cleanup")
	prepareHomePreview := flag.Bool("prepare-home-preview", false, "Create local-only, reversible Home preview data for Cuttack and Jajpur")
	mediaBaseURL := flag.String("media-base-url", "", "Emulator-reachable local Nginx media base URL (prepare-ui only)")
	flag.Parse()
	if err := run(*base, *cities, *manifest, *cleanup, *allow, *prepareUI, *prepareHomePreview, *mediaBaseURL); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(base, cities, path string, cleanup, allow, prepareUI, prepareHomePreview bool, mediaBaseURL string) (result error) {
	cfg := config.Load()
	if cfg.DBHost != "localhost" && cfg.DBHost != "127.0.0.1" {
		return errors.New("fixture runner requires a loopback database host")
	}
	endpoint, err := url.Parse(base)
	if err != nil || (endpoint.Hostname() != "127.0.0.1" && endpoint.Hostname() != "localhost") || !cfg.IsLocal() || !allow {
		return errors.New("requires loopback API, APP_ENV=local, and --allow-local-fixtures")
	}
	db, err := database.Open(cfg.DBDSN(), 5, 2, time.Minute)
	if err != nil {
		return err
	}
	defer db.Close()
	r := &runner{db: db, base: strings.TrimRight(base, "/"), manifest: path, client: &http.Client{Timeout: 20 * time.Second}}
	if cleanup {
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if err = json.Unmarshal(data, &r.ledger); err != nil {
			return err
		}
		if err = r.initStorage(cfg); err != nil {
			return err
		}
		return r.clean()
	}
	if strings.TrimSpace(cities) == "" {
		return errors.New("--cities is required")
	}
	if _, err = os.Stat(path); err == nil {
		return errors.New("manifest already exists; use --cleanup before another run")
	}
	r.ledger.Run = "validation-" + uuid.NewString()
	r.mediaBaseURL = strings.TrimRight(mediaBaseURL, "/")
	if err = r.save(); err != nil {
		return err
	}
	defer func() {
		if (!prepareUI && !prepareHomePreview) || result != nil {
			result = errors.Join(result, r.clean())
		}
	}()
	var categories []category
	if err = r.api("GET", "/categories", "", nil, 200, &categories); err != nil {
		return err
	}
	if len(categories) == 0 {
		return errors.New("API has no active categories")
	}
	if prepareHomePreview {
		return r.prepareHomePreview(strings.Split(cities, ","), categories, cfg)
	}
	if prepareUI {
		if err = r.initStorage(cfg); err != nil {
			return err
		}
		if r.mediaBaseURL == "" {
			return errors.New("--media-base-url is required for emulator image URLs")
		}
		r.imageURLs = make(map[string]string)
		customer, err := r.newUser("customer")
		if err != nil {
			return err
		}
		r.ledger.CustomerPhone = customer.Phone
		if err := r.save(); err != nil {
			return err
		}
		for _, city := range strings.Split(cities, ",") {
			city = strings.TrimSpace(city)
			var lat, lng float64
			if err = r.db.QueryRow(`SELECT avg(ST_Y(location::geometry)),avg(ST_X(location::geometry)) FROM businesses WHERE lower(city)=lower($1) AND status='approved'`, city).Scan(&lat, &lng); err != nil {
				return err
			}
			var address, locality, postal string
			if err = r.db.QueryRow(`SELECT address_text,COALESCE(locality,''),COALESCE(postal_code,'') FROM businesses WHERE lower(city)=lower($1) AND status='approved' LIMIT 1`, city).Scan(&address, &locality, &postal); err != nil {
				return fmt.Errorf("%s has no usable merchant address: %w", city, err)
			}
			for _, cat := range categories {
				user, err := r.newUser("merchant")
				if err != nil {
					return err
				}
				bid := uuid.NewString()
				name := fmt.Sprintf("QA Fixture %s - %s %s", r.ledger.Run[:12], cat.Name, city)
				productName, description, price, imageSource := sampleCatalogItem(cat)
				image, err := r.uploadFixtureImage(cat.Slug, imageSource)
				if err != nil {
					return fmt.Errorf("%s image: %w", cat.Slug, err)
				}
				offerTitle := fmt.Sprintf("QA Fixture %s - %s seasonal offer", r.ledger.Run[:12], cat.Name)
				if err = r.db.Transaction(context.Background(), func(tx *sqlx.Tx) error {
					if _, err := tx.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,whatsapp_e164,address_text,locality,city,postal_code,location,status,cover_photo_url) VALUES($1,$2,$3,$4,$5,$6,$7,$7,$8,$9,$10,$11,ST_SetSRID(ST_MakePoint($12,$13),4326)::geography,'approved',$14)`, bid, user.ID, name, uuid.NewString(), cat.Description, cat.Slug, user.Phone, address, locality, city, postal, lng, lat, image); err != nil {
						return err
					}
					for weekday := 0; weekday < 7; weekday++ {
						closed := weekday == 0
						var opens, closes interface{}
						if !closed {
							opens, closes = "09:00", "18:30"
						}
						if _, err := tx.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,$3,$4,$5)`, bid, weekday, opens, closes, closed); err != nil {
							return err
						}
					}
					if _, err := tx.Exec(`INSERT INTO professional_profiles(business_id,accepts_requests) VALUES($1,true) ON CONFLICT(business_id) DO UPDATE SET accepts_requests=true`, bid); err != nil {
						return err
					}
					_, err := tx.Exec(`INSERT INTO business_members(business_id,user_id,role) VALUES($1,$2,'owner')`, bid, user.ID)
					return err
				}); err != nil {
					return err
				}
				r.ledger.Cases = append(r.ledger.Cases, uiCase{City: city, CategorySlug: cat.Slug, CategoryName: cat.Name, BusinessID: bid, Phone: user.Phone, BusinessName: name, Address: address, Locality: locality, PostalCode: postal, Description: cat.Description, ProductName: productName, ProductDescription: description, ImageURL: image, OfferTitle: offerTitle, Price: price, Latitude: lat, Longitude: lng})
				if err = r.save(); err != nil {
					return err
				}
			}
		}
		fmt.Printf("PREPARED %d UI cases. No products created; run the Flutter UI injector, then --cleanup with this manifest.\n", len(r.ledger.Cases))
		return nil
	}
	customer, err := r.newUser("customer")
	if err != nil {
		return err
	}
	customerToken, err := r.login(customer.Phone, "customer")
	if err != nil {
		return err
	}
	checks := 0
	for _, city := range strings.Split(cities, ",") {
		city = strings.TrimSpace(city)
		if city == "" {
			return errors.New("empty city")
		}
		var lat, lng float64
		// Derive fixture coordinates from existing approved city data, never fixed coordinates.
		if err = r.db.QueryRow(`SELECT avg(ST_Y(location::geometry)),avg(ST_X(location::geometry)) FROM businesses WHERE lower(city)=lower($1) AND status='approved'`, city).Scan(&lat, &lng); err != nil {
			return fmt.Errorf("%s has no approved location data: %w", city, err)
		}
		for _, cat := range categories {
			var baseline int
			if err = r.db.Get(&baseline, `SELECT count(*) FROM businesses WHERE lower(city)=lower($1) AND category_slug=$2 AND status='approved'`, city, cat.Slug); err != nil {
				return err
			}
			if err = r.check(city, lat, lng, cat, customerToken); err != nil {
				return fmt.Errorf("%s/%s: %w", city, cat.Slug, err)
			}
			checks++
			fmt.Printf("PASS %s / %s: existing approved listings=%d; generated merchant CRUD, customer discovery and request, role isolation\n", city, cat.Slug, baseline)
		}
	}
	fmt.Printf("PASS %d city/category combinations; cleanup follows\n", checks)
	return nil
}

// prepareHomePreview creates visibly labelled QA merchants and a local published
// offer so the Home screen can be reviewed without changing retained listings.
// Every merchant account, business, offer and object key belongs to this manifest.
func (r *runner) prepareHomePreview(cities []string, categories []category, cfg *config.Config) error {
	if len(cities) != 2 || strings.TrimSpace(cities[0]) != "Cuttack" || strings.TrimSpace(cities[1]) != "Jajpur" {
		return errors.New("Home preview fixtures require exactly Cuttack,Jajpur")
	}
	if r.mediaBaseURL == "" {
		return errors.New("--media-base-url is required for emulator image URLs")
	}
	if err := r.initStorage(cfg); err != nil {
		return err
	}
	bySlug := make(map[string]category, len(categories))
	for _, item := range categories {
		bySlug[item.Slug] = item
	}
	type sample struct {
		slug, label, purpose string
		imageIndex           int
		liveOffer            bool
		service              bool
		openNow              bool
	}
	samples := []sample{
		{slug: "grocery", label: "Fresh Market", purpose: "offer", imageIndex: 0, liveOffer: true},
		{slug: "restaurant", label: "Neighborhood Kitchen", purpose: "open", imageIndex: 3, openNow: true},
		{slug: "plumber", label: "Home Service Professional", purpose: "service", imageIndex: 5, service: true},
		{slug: "tailor", label: "Local Loom & Style", purpose: "recent", imageIndex: 11},
	}
	for _, city := range cities {
		var lat, lng float64
		if err := r.db.QueryRow(`SELECT avg(ST_Y(location::geometry)),avg(ST_X(location::geometry)) FROM businesses WHERE lower(city)=lower($1) AND status='approved'`, city).Scan(&lat, &lng); err != nil {
			return fmt.Errorf("%s coordinates: %w", city, err)
		}
		var address, locality, postal string
		if err := r.db.QueryRow(`SELECT address_text,COALESCE(locality,''),COALESCE(postal_code,'') FROM businesses WHERE lower(city)=lower($1) AND status='approved' LIMIT 1`, city).Scan(&address, &locality, &postal); err != nil {
			return fmt.Errorf("%s sample address: %w", city, err)
		}
		for _, item := range samples {
			cat, ok := bySlug[item.slug]
			if !ok {
				return fmt.Errorf("required category %q is not active", item.slug)
			}
			user, err := r.newUser("merchant")
			if err != nil {
				return err
			}
			businessID := uuid.NewString()
			name := fmt.Sprintf("QA PREVIEW · %s · %s", item.label, city)
			imageURL, err := r.uploadAtlasSample(item.imageIndex)
			if err != nil {
				return err
			}
			if err = r.db.Transaction(context.Background(), func(tx *sqlx.Tx) error {
				if _, err := tx.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,description,category_slug,phone_e164,whatsapp_e164,address_text,locality,city,postal_code,location,status,verification_status,cover_photo_url) VALUES($1,$2,$3,$4,$5,$6,$7,$7,$8,$9,$10,$11,ST_SetSRID(ST_MakePoint($12,$13),4326)::geography,'approved','unverified',$14)`, businessID, user.ID, name, uuid.NewString(), "Local QA preview listing. This temporary data is created only for Home screen validation.", cat.Slug, user.Phone, address, locality, city, postal, lng, lat, imageURL); err != nil {
					return err
				}
				for weekday := 0; weekday < 7; weekday++ {
					if item.openNow {
						if _, err := tx.Exec(`INSERT INTO business_hours(business_id,weekday,opens_at,closes_at,is_closed) VALUES($1,$2,'00:00','23:59:59',false)`, businessID, weekday); err != nil {
							return err
						}
					} else if _, err := tx.Exec(`INSERT INTO business_hours(business_id,weekday,is_closed) VALUES($1,$2,true)`, businessID, weekday); err != nil {
						return err
					}
				}
				if item.service {
					if _, err := tx.Exec(`INSERT INTO professional_profiles(business_id,accepts_requests) VALUES($1,true)`, businessID); err != nil {
						return err
					}
				}
				if item.liveOffer {
					_, err := tx.Exec(`INSERT INTO offers(business_id,title,description,starts_at,ends_at,status,image_url,terms,discount_percent) VALUES($1,'QA preview: Fresh produce picks','A temporary offer used to validate the live offer card. Confirm final pricing with the merchant.',$2,$3,'published',$4,'Local preview fixture; no purchase is being made.',10)`, businessID, time.Now().UTC().Add(-time.Hour), time.Now().UTC().AddDate(0, 0, 6), imageURL)
					if err != nil {
						return err
					}
				}
				return nil
			}); err != nil {
				return fmt.Errorf("create %s %s preview: %w", city, item.purpose, err)
			}
			r.ledger.Cases = append(r.ledger.Cases, uiCase{City: city, CategorySlug: cat.Slug, CategoryName: cat.Name, BusinessID: businessID, Phone: user.Phone, BusinessName: name, Address: address, Locality: locality, PostalCode: postal, ImageURL: imageURL})
			if err := r.save(); err != nil {
				return err
			}
		}
	}
	fmt.Printf("PREPARED %d labelled Home preview merchants in Cuttack and Jajpur; one active QA offer per city. Manifest: %s\n", len(cities)*len(samples), r.manifest)
	return nil
}

func (r *runner) uploadAtlasSample(index int) (string, error) {
	if index < 0 || index >= 20 {
		return "", errors.New("sample image index is out of range")
	}
	key := fmt.Sprintf("ui-fixtures/%s/home-sample-%02d.jpg", strings.TrimPrefix(r.ledger.Run, "validation-"), index)
	for _, existing := range r.ledger.ImageKeys {
		if existing == key {
			return r.mediaBaseURL + "/media/" + key, nil
		}
	}
	asset, err := os.Open(filepath.Join("..", "apps", "mobile", "assets", "images", "category_sample_atlas.png"))
	if err != nil {
		return "", fmt.Errorf("open bundled category sample atlas: %w", err)
	}
	defer asset.Close()
	source, err := png.Decode(asset)
	if err != nil {
		return "", fmt.Errorf("decode bundled category sample atlas: %w", err)
	}
	bounds := source.Bounds()
	cell := image.Rect(bounds.Min.X+(index%4)*bounds.Dx()/4, bounds.Min.Y+(index/4)*bounds.Dy()/5, bounds.Min.X+(index%4+1)*bounds.Dx()/4, bounds.Min.Y+(index/4+1)*bounds.Dy()/5)
	region, ok := source.(interface {
		SubImage(image.Rectangle) image.Image
	})
	if !ok {
		return "", errors.New("category sample atlas does not support cropping")
	}
	var encoded bytes.Buffer
	if err := jpeg.Encode(&encoded, region.SubImage(cell), &jpeg.Options{Quality: 84}); err != nil {
		return "", fmt.Errorf("encode sample photo: %w", err)
	}
	r.ledger.ImageKeys = append(r.ledger.ImageKeys, key)
	if err := r.save(); err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if _, err := r.storage.PutObject(ctx, config.Load().S3Bucket, key, bytes.NewReader(encoded.Bytes()), int64(encoded.Len()), minio.PutObjectOptions{ContentType: "image/jpeg"}); err != nil {
		return "", fmt.Errorf("upload sample photo to local storage: %w", err)
	}
	return r.mediaBaseURL + "/media/" + key, nil
}

// Sample names are isolated test catalog fixtures; production catalog data is never changed.
func sampleCatalogItem(cat category) (string, string, float64, string) {
	items := map[string]struct {
		name, description, imageID string
		price                      float64
	}{
		"grocery":          {"Gobindobhog Rice, 5 kg", "Aromatic short-grain rice suitable for everyday meals and festive cooking.", "photo-1542838132-92c53300491e", 549},
		"hardware":         {"Anchor Roma 6A Modular Switch", "ISI-marked modular switch for residential electrical fittings.", "photo-1621905251918-48416bd8575a", 115},
		"medical":          {"Digital Thermometer", "Clinical digital thermometer with quick temperature reading and storage case.", "photo-1584308666744-24d5c474f2ae", 199},
		"restaurant":       {"Odia Chhena Poda Slice", "Freshly baked cottage-cheese dessert prepared in the Odia style.", "photo-1604382355076-af4b0eb60143", 95},
		"salon":            {"Classic Haircut and Grooming", "Consultation, haircut, wash and finish by a trained stylist.", "photo-1560066984-138dadb4c035", 299},
		"plumber":          {"Tap and Mixer Repair Visit", "Inspection and repair of one leaking tap or mixer; parts quoted separately.", "photo-1607472586893-edb57bdc0e39", 350},
		"electrician":      {"Home Electrical Safety Check", "Inspection of switches, sockets and visible wiring with a written estimate.", "photo-1621905251918-48416bd8575a", 499},
		"carpenter":        {"Door Hinge Repair Service", "Adjustment and repair of one interior door hinge; replacement hardware quoted separately.", "photo-1601049541289-9b1b7bbbfe19", 399},
		"tailor":           {"Blouse Stitching, Standard Fit", "Made-to-measure blouse stitching with one fitting adjustment.", "photo-1598033129183-c4f50c736f10", 650},
		"general":          {"Household Essentials Pack", "A practical assortment of everyday household consumables.", "photo-1607082349566-187342175e2f", 399},
		"hotel":            {"Standard AC Room, One Night", "Private air-conditioned room with attached bathroom; availability confirmed by the property.", "photo-1566073771259-6a8506099945", 2200},
		"fashion":          {"Sambalpuri Cotton Saree", "Woven cotton saree with traditional Sambalpuri-inspired motifs.", "photo-1539109136881-3be0616acf4b", 1499},
		"books_stationery": {"Classmate Long Notebook, 6 Pack", "Ruled long notebooks for school and office use.", "photo-1453738773917-9c3eff1db985", 240},
		"cleaning":         {"Two-Bedroom Home Deep Cleaning", "Scheduled cleaning of floors, kitchen surfaces and bathrooms; scope confirmed before service.", "photo-1581578731548-c64695cc6952", 2499},
		"home_kitchen":     {"Stainless Steel Pressure Cooker, 3 L", "Three-litre pressure cooker for everyday home cooking.", "photo-1556911220-e15b29be8c8f", 1899},
		"health_wellness":  {"Wellness Consultation, 30 Minutes", "One-to-one wellness consultation; not a substitute for medical diagnosis.", "photo-1540555700478-4be289fbecef", 499},
		"electronics":      {"USB-C 20 W Fast Charger", "USB-C wall charger with over-current and over-temperature protection.", "photo-1598327105666-5b89351aff97", 799},
		"sports_fitness":   {"Non-Slip Yoga Mat, 6 mm", "Textured exercise mat for yoga and floor workouts.", "photo-1544367567-0f2fcb009e0b", 699},
		"automotive":       {"Two-Wheeler General Service", "Routine inspection and labour for a two-wheeler; parts and fluids billed separately.", "photo-1486262715619-67b85e0b08d3", 899},
	}
	if item, ok := items[cat.Slug]; ok {
		return item.name, item.description, item.price, fmt.Sprintf("https://images.unsplash.com/%s?auto=format&fit=crop&w=900&q=80", item.imageID)
	}
	return cat.Name + " Consultation", "Locally delivered " + strings.ToLower(cat.Name) + " product or service. Scope and final price confirmed with the merchant.", 499, "https://images.unsplash.com/photo-1607082349566-187342175e2f?auto=format&fit=crop&w=900&q=80"
}

func (r *runner) save() error {
	data, err := json.MarshalIndent(r.ledger, "", "  ")
	if err != nil {
		return err
	}
	// Save allocated IDs before inserting so interrupted runs can be recovered.
	if err := os.WriteFile(r.manifest+".tmp", data, 0600); err != nil {
		return err
	}
	return os.Rename(r.manifest+".tmp", r.manifest)
}

func (r *runner) newUser(role string) (owner, error) {
	number, err := rand.Int(rand.Reader, big.NewInt(1000000000))
	if err != nil {
		return owner{}, err
	}
	u := owner{uuid.NewString(), fmt.Sprintf("+919%09d", number.Int64())}
	r.ledger.Users = append(r.ledger.Users, u)
	if err = r.save(); err != nil {
		return u, err
	}
	err = r.db.Transaction(context.Background(), func(tx *sqlx.Tx) error {
		if _, err := tx.Exec(`INSERT INTO users(id,phone_e164,display_name) VALUES($1,$2,$3)`, u.ID, u.Phone, r.ledger.Run); err != nil {
			return err
		}
		_, err := tx.Exec(`INSERT INTO user_roles(user_id,role) VALUES($1,$2)`, u.ID, role)
		return err
	})
	return u, err
}

func (r *runner) login(phone, expectedRole string) (string, error) {
	var otp struct {
		Code string `json:"otp_code"`
	}
	if err := r.api("POST", "/auth/otp/request", "", map[string]string{"phone_e164": phone}, 202, &otp); err != nil {
		return "", err
	}
	if otp.Code == "" {
		return "", errors.New("local OTP stub unavailable")
	}
	var session struct {
		Token string `json:"access_token"`
		User  struct {
			Roles []string `json:"roles"`
		} `json:"user"`
	}
	err := r.api("POST", "/auth/otp/verify", "", map[string]string{"phone_e164": phone, "otp_code": otp.Code}, 200, &session)
	if err == nil && session.Token == "" {
		err = errors.New("missing access token")
	}
	if err == nil {
		found := false
		for _, role := range session.User.Roles {
			if role == expectedRole {
				found = true
			}
		}
		if !found {
			err = fmt.Errorf("login missing expected %s role", expectedRole)
		}
	}
	return session.Token, err
}

func (r *runner) check(city string, lat, lng float64, cat category, customer string) error {
	user, err := r.newUser("merchant")
	if err != nil {
		return err
	}
	bid := uuid.NewString()
	name := r.ledger.Run[:20] + "-" + uuid.NewString()
	err = r.db.Transaction(context.Background(), func(tx *sqlx.Tx) error {
		if _, err := tx.Exec(`INSERT INTO businesses(id,owner_user_id,name,slug,category_slug,address_text,city,location,status) VALUES($1,$2,$3,$3,$4,$5,$5,ST_SetSRID(ST_MakePoint($6,$7),4326)::geography,'approved')`, bid, user.ID, name, cat.Slug, city, lng, lat); err != nil {
			return err
		}
		_, err := tx.Exec(`INSERT INTO business_members(business_id,user_id,role) VALUES($1,$2,'owner')`, bid, user.ID)
		return err
	})
	if err != nil {
		return err
	}
	merchant, err := r.login(user.Phone, "merchant")
	if err != nil {
		return err
	}
	var profile struct {
		Roles []string `json:"roles"`
	}
	if err = r.api("GET", "/me", merchant, nil, 200, &profile); err != nil {
		return err
	}
	merchantRole := false
	for _, role := range profile.Roles {
		if role == "merchant" {
			merchantRole = true
		}
	}
	if !merchantRole {
		return errors.New("merchant login did not return merchant role")
	}
	if err = r.api("PATCH", "/merchant/profile", merchant, map[string]string{"city": r.ledger.Run}, 400, nil); err != nil {
		return err
	}
	var created struct {
		ID string `json:"id"`
	}
	path := "/merchant/catalog-categories?business_id=" + bid
	if err = r.api("POST", path, merchant, map[string]string{"name": name}, 201, &created); err != nil {
		return err
	}
	cid := created.ID
	if cid == "" {
		return errors.New("missing category id")
	}
	renamed := name + "-updated"
	if err = r.api("PATCH", "/merchant/catalog-categories/"+cid+"?business_id="+bid, merchant, map[string]string{"name": renamed}, 200, nil); err != nil {
		return err
	}
	var groups []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err = r.api("GET", path, merchant, nil, 200, &groups); err != nil {
		return err
	}
	if len(groups) != 1 || groups[0].ID != cid || groups[0].Name != renamed {
		return errors.New("category update not persisted")
	}
	if err = r.api("DELETE", "/merchant/catalog-categories/"+cid+"?business_id="+bid, customer, nil, 403, nil); err != nil {
		return err
	}
	if err = r.api("GET", path, "", nil, 401, nil); err != nil {
		return err
	}
	if r.previousMerchant != "" {
		if err = r.api("DELETE", "/merchant/catalog-categories/"+cid+"?business_id="+bid, r.previousMerchant, nil, 403, nil); err != nil {
			return err
		}
	}
	// Validate real discovery independently for every active taxonomy category.
	query := url.Values{"city": {city}, "category_slug": {cat.Slug}, "q": {name}, "limit": {"50"}}
	var listings []business
	if err = r.api("GET", "/businesses?"+query.Encode(), customer, nil, 200, &listings); err != nil {
		return err
	}
	if len(listings) != 1 || listings[0].ID != bid || !strings.EqualFold(listings[0].City, city) || listings[0].Category != cat.Slug {
		return errors.New("city/category discovery mismatch")
	}
	query.Set("city", r.ledger.Run)
	if err = r.api("GET", "/businesses?"+query.Encode(), customer, nil, 200, &listings); err != nil {
		return err
	}
	if len(listings) != 0 {
		return errors.New("city filter leaked another city's listings")
	}
	for _, kind := range []string{"products", "services"} {
		payload := map[string]interface{}{"name": name, "price": float64(len(name)), "is_published": true, "is_active": true}
		if err = r.api("POST", "/merchant/"+kind, merchant, payload, 201, &created); err != nil {
			return err
		}
		id := created.ID
		if err = r.api("PATCH", "/merchant/"+kind+"/"+id, merchant, map[string]string{"name": renamed}, 200, nil); err != nil {
			return err
		}
		var items []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		}
		if err = r.api("GET", "/businesses/"+bid+"/"+kind, customer, nil, 200, &items); err != nil {
			return err
		}
		if len(items) != 1 || items[0].ID != id || items[0].Name != renamed {
			return fmt.Errorf("%s update not visible to customer", kind)
		}
		if err = r.api("DELETE", "/merchant/"+kind+"/"+id, merchant, nil, 200, nil); err != nil {
			return err
		}
		if err = r.api("GET", "/businesses/"+bid+"/"+kind, customer, nil, 200, &items); err != nil {
			return err
		}
		if len(items) != 0 {
			return fmt.Errorf("%s delete not persisted", kind)
		}
	}
	if err = r.api("POST", "/businesses/"+bid+"/requests", customer, map[string]string{"description": name}, 201, &created); err != nil {
		return err
	}
	rid := created.ID
	if err = r.api("GET", "/requests/"+rid, customer, nil, 200, nil); err != nil {
		return err
	}
	if err = r.api("PATCH", "/merchant/requests/"+rid+"/status?business_id="+bid, merchant, map[string]string{"status": "accepted"}, 200, nil); err != nil {
		return err
	}
	var request struct {
		Status string `json:"status"`
	}
	if err = r.api("GET", "/requests/"+rid, customer, nil, 200, &request); err != nil {
		return err
	}
	if request.Status != "accepted" {
		return errors.New("customer did not receive merchant status update")
	}
	if r.previousMerchant != "" {
		if err = r.api("GET", "/requests/"+rid, r.previousMerchant, nil, 403, nil); err != nil {
			return err
		}
	}
	r.previousMerchant = merchant
	if err = r.api("DELETE", "/merchant/catalog-categories/"+cid+"?business_id="+bid, merchant, nil, 204, nil); err != nil {
		return err
	}
	if err = r.api("GET", path, merchant, nil, 200, &groups); err != nil {
		return err
	}
	if len(groups) != 0 {
		return errors.New("category delete not persisted")
	}
	return nil
}

func (r *runner) api(method, path, token string, body interface{}, status int, dest interface{}) error {
	data, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(method, r.base+path, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := r.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != status {
		var failure struct {
			Error struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.NewDecoder(io.LimitReader(res.Body, 4096)).Decode(&failure)
		return fmt.Errorf("%s %s expected %d, received %d (%s: %s)", method, path, status, res.StatusCode, failure.Error.Code, failure.Error.Message)
	}
	if dest == nil {
		io.Copy(io.Discard, res.Body)
		return nil
	}
	var envelope struct {
		Data json.RawMessage `json:"data"`
	}
	if err = json.NewDecoder(io.LimitReader(res.Body, 2<<20)).Decode(&envelope); err != nil {
		return err
	}
	return json.Unmarshal(envelope.Data, dest)
}

func (r *runner) initStorage(cfg *config.Config) error {
	endpoint := strings.TrimPrefix(strings.TrimPrefix(cfg.S3Endpoint, "http://"), "https://")
	secure := cfg.S3UseSSL || strings.HasPrefix(cfg.S3Endpoint, "https://")
	// The validator runs in WSL while Compose services are reachable by their
	// published localhost ports. The API itself continues to use the Compose DNS name.
	if host, port, err := net.SplitHostPort(endpoint); err == nil && host == "minio" {
		endpoint = net.JoinHostPort("127.0.0.1", port)
	} else if strings.HasPrefix(endpoint, "minio:") {
		endpoint = "127.0.0.1:" + strings.TrimPrefix(endpoint, "minio:")
	}
	client, err := minio.New(endpoint, &minio.Options{Creds: credentials.NewStaticV4(cfg.S3AccessKey, cfg.S3SecretKey, ""), Secure: secure})
	if err != nil {
		return fmt.Errorf("initialize local object storage: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if exists, err := client.BucketExists(ctx, cfg.S3Bucket); err != nil {
		return fmt.Errorf("check local media bucket: %w", err)
	} else if !exists {
		return fmt.Errorf("local media bucket %q does not exist", cfg.S3Bucket)
	}
	r.storage = client
	return nil
}

func (r *runner) uploadFixtureImage(slug, sourceURL string) (string, error) {
	key := "ui-fixtures/" + strings.TrimPrefix(r.ledger.Run, "validation-") + "/" + slug + ".jpg"
	for _, existing := range r.ledger.ImageKeys {
		if existing == key {
			return r.mediaBaseURL + "/media/" + key, nil
		}
	}
	request, err := http.NewRequest(http.MethodGet, sourceURL, nil)
	if err != nil {
		return "", err
	}
	request.Header.Set("User-Agent", "Grepmind-Near-Local-QA/1.0")
	response, err := r.client.Do(request)
	if err != nil {
		return "", fmt.Errorf("download category image: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("category image source returned HTTP %d", response.StatusCode)
	}
	contentType := strings.ToLower(strings.TrimSpace(strings.Split(response.Header.Get("Content-Type"), ";")[0]))
	if contentType != "image/jpeg" && contentType != "image/jpg" {
		return "", fmt.Errorf("category image source returned unsupported type %q", contentType)
	}
	data, err := io.ReadAll(io.LimitReader(response.Body, (8<<20)+1))
	if err != nil {
		return "", err
	}
	if len(data) == 0 || len(data) > 8<<20 {
		return "", errors.New("category image must be between 1 byte and 8 MiB")
	}
	// Record intended key before writing so cleanup can recover after interruption.
	r.ledger.ImageKeys = append(r.ledger.ImageKeys, key)
	if err := r.save(); err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if _, err := r.storage.PutObject(ctx, config.Load().S3Bucket, key, bytes.NewReader(data), int64(len(data)), minio.PutObjectOptions{ContentType: "image/jpeg"}); err != nil {
		return "", fmt.Errorf("upload fixture image to MinIO: %w", err)
	}
	return r.mediaBaseURL + "/media/" + key, nil
}

func (r *runner) clean() error {
	if !strings.HasPrefix(r.ledger.Run, "validation-") {
		return errors.New("invalid cleanup manifest")
	}
	if _, err := uuid.Parse(strings.TrimPrefix(r.ledger.Run, "validation-")); err != nil {
		return errors.New("invalid cleanup run ID")
	}
	if len(r.ledger.ImageKeys) > 0 {
		if r.storage == nil {
			return errors.New("storage must be initialized before fixture image cleanup")
		}
		prefix := "ui-fixtures/" + strings.TrimPrefix(r.ledger.Run, "validation-") + "/"
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		for _, key := range r.ledger.ImageKeys {
			if !strings.HasPrefix(key, prefix) || strings.Contains(key, "..") {
				return fmt.Errorf("refusing to delete object outside fixture prefix: %q", key)
			}
			if err := r.storage.RemoveObject(ctx, config.Load().S3Bucket, key, minio.RemoveObjectOptions{}); err != nil {
				return fmt.Errorf("remove fixture image %q: %w", key, err)
			}
		}
	}
	for _, u := range r.ledger.Users {
		if _, err := uuid.Parse(u.ID); err != nil {
			return err
		}
		err := r.db.Transaction(context.Background(), func(tx *sqlx.Tx) error {
			var exists bool
			if err := tx.QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE id=$1 AND phone_e164=$2 AND display_name=$3)`, u.ID, u.Phone, r.ledger.Run).Scan(&exists); err != nil {
				return err
			}
			if !exists {
				return nil
			} // Never delete an unrelated account on phone collision.
			for _, statement := range []string{
				`DELETE FROM notifications WHERE user_id=$1 OR business_id IN(SELECT id FROM businesses WHERE owner_user_id=$1)`,
				`DELETE FROM service_requests WHERE customer_user_id=$1 OR business_id IN(SELECT id FROM businesses WHERE owner_user_id=$1)`,
				`DELETE FROM otp_codes WHERE phone_e164=(SELECT phone_e164 FROM users WHERE id=$1)`,
				`DELETE FROM users WHERE id=$1`,
			} {
				if _, err := tx.Exec(statement, u.ID); err != nil {
					return err
				}
			}
			return nil
		})
		if err != nil {
			return fmt.Errorf("cleanup failed; retain manifest and rerun with --cleanup: %w", err)
		}
	}
	var remaining int
	if err := r.db.Get(&remaining, `SELECT count(*) FROM users WHERE display_name=$1`, r.ledger.Run); err != nil {
		return err
	}
	if remaining != 0 {
		return fmt.Errorf("cleanup verification failed: %d accounts remain", remaining)
	}
	if err := os.Remove(r.manifest); err != nil && !os.IsNotExist(err) {
		return err
	}
	if err := os.Remove(r.manifest + ".tmp"); err != nil && !os.IsNotExist(err) {
		return err
	}
	fmt.Println("PASS cleanup: generated users, businesses, categories, products, services, requests, notifications, OTPs and sessions removed")
	return nil
}
