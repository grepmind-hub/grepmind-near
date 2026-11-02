package discovery

import "net/http"

// Locations derives supported cities and listing counts from approved businesses.
func (s *Service) Locations(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.QueryContext(r.Context(), `SELECT city, count(*), avg(ST_Y(location::geometry)), avg(ST_X(location::geometry)) FROM businesses WHERE status='approved' AND city IS NOT NULL AND btrim(city) != '' GROUP BY city ORDER BY city LIMIT 200`)
	if err != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to load locations.")
		return
	}
	defer rows.Close()
	items := []map[string]interface{}{}
	for rows.Next() {
		var city string
		var count int
		var lat, lng float64
		if rows.Scan(&city, &count, &lat, &lng) != nil {
			writeError(w, 500, "INTERNAL_ERROR", "Unable to read locations.")
			return
		}
		items = append(items, map[string]interface{}{"city": city, "count": count, "latitude": lat, "longitude": lng})
	}
	if rows.Err() != nil {
		writeError(w, 500, "INTERNAL_ERROR", "Unable to read locations.")
		return
	}
	writeJSON(w, 200, envelope{"data": items})
}
