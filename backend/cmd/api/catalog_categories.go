package main

import (
	"encoding/json"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"grepmind-near/backend/internal/auth"
	"grepmind-near/backend/pkg/database"
)

// Categories are always resolved inside the authenticated merchant's business.
func merchantCatalogCategories(_ *auth.Service, db *database.DB, w http.ResponseWriter, r *http.Request, userID string) {
	businessID, role, err := resolveMerchantBusiness(r.Context(), db, userID, r.URL.Query().Get("business_id"))
	if err != nil {
		writeError(w, 403, "FORBIDDEN", "Business access required.")
		return
	}
	if r.Method != http.MethodGet && role != "owner" && role != "manager" {
		writeError(w, 403, "FORBIDDEN", "Owner or manager access required.")
		return
	}
	id := r.PathValue("id")
	if id != "" {
		if _, err := uuid.Parse(id); err != nil {
			writeError(w, 400, "VALIDATION_ERROR", "Invalid category ID.")
			return
		}
	}
	if r.Method == http.MethodGet {
		items := []map[string]string{}
		rows, err := db.QueryContext(r.Context(), `SELECT id, name FROM merchant_catalog_categories WHERE business_id = $1 ORDER BY lower(name), id`, businessID)
		if err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to load categories.")
			return
		}
		defer rows.Close()
		for rows.Next() {
			var id, name string
			if err := rows.Scan(&id, &name); err != nil {
				writeError(w, 500, "INTERNAL_ERROR", "Unable to read categories.")
				return
			}
			items = append(items, map[string]string{"id": id, "name": name})
		}
		if rows.Err() != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read categories.")
			return
		}
		writeJSON(w, 200, envelope{"data": items})
		return
	}
	if r.Method == http.MethodDelete {
		result, err := db.ExecContext(r.Context(), `DELETE FROM merchant_catalog_categories WHERE id = $1 AND business_id = $2`, id, businessID)
		if err != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to delete category.")
			return
		}
		count, _ := result.RowsAffected()
		if count == 0 {
			writeError(w, 404, "NOT_FOUND", "Category not found.")
			return
		}
		w.WriteHeader(204)
		return
	}
	var body struct {
		Name string `json:"name"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 4096)
	if json.NewDecoder(r.Body).Decode(&body) != nil {
		writeError(w, 400, "VALIDATION_ERROR", "Invalid category.")
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	if utf8.RuneCountInString(body.Name) < 1 || utf8.RuneCountInString(body.Name) > 80 {
		writeError(w, 400, "VALIDATION_ERROR", "Use a category name between 1 and 80 characters.")
		return
	}
	status := 200
	if r.Method == http.MethodPost {
		err = db.QueryRowContext(r.Context(), `INSERT INTO merchant_catalog_categories (business_id,name) VALUES ($1,$2) RETURNING id`, businessID, body.Name).Scan(&id)
		status = 201
	} else {
		err = db.QueryRowContext(r.Context(), `UPDATE merchant_catalog_categories SET name=$1 WHERE id=$2 AND business_id=$3 RETURNING id`, body.Name, id, businessID).Scan(&id)
	}
	if err != nil {
		writeError(w, 409, "CATEGORY_CONFLICT", "Category could not be saved. Refresh and check for duplicate names.")
		return
	}
	writeJSON(w, status, envelope{"data": map[string]string{"id": id, "name": body.Name}})
}
