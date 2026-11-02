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
	"io"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

type owner struct {
	ID    string
	Phone string
}
type ledger struct {
	Run   string
	Users []owner
}
type runner struct {
	db               *database.DB
	base, manifest   string
	ledger           ledger
	client           *http.Client
	previousMerchant string
}
type category struct {
	Slug string `json:"slug"`
	Name string `json:"name"`
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
	flag.Parse()
	if err := run(*base, *cities, *manifest, *cleanup, *allow); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(base, cities, path string, cleanup, allow bool) (result error) {
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
	r := &runner{db: db, base: strings.TrimRight(base, "/"), manifest: path, client: &http.Client{Timeout: 15 * time.Second}}
	if cleanup {
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if err = json.Unmarshal(data, &r.ledger); err != nil {
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
	if err = r.save(); err != nil {
		return err
	}
	defer func() { result = errors.Join(result, r.clean()) }()
	var categories []category
	if err = r.api("GET", "/categories", "", nil, 200, &categories); err != nil {
		return err
	}
	if len(categories) == 0 {
		return errors.New("API has no active categories")
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

func (r *runner) clean() error {
	if !strings.HasPrefix(r.ledger.Run, "validation-") {
		return errors.New("invalid cleanup manifest")
	}
	if _, err := uuid.Parse(strings.TrimPrefix(r.ledger.Run, "validation-")); err != nil {
		return errors.New("invalid cleanup run ID")
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
