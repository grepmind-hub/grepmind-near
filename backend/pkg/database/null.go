package database

import (
	"database/sql"
	"fmt"
	"time"
)

// NullTime wraps time.Time for nullable timestamp columns.
type NullTime struct {
	Time  time.Time
	Valid bool
}

func (nt *NullTime) Scan(value interface{}) error {
	if value == nil {
		nt.Valid = false
		return nil
	}
	switch v := value.(type) {
	case time.Time:
		nt.Time = v
		nt.Valid = true
		return nil
	case []byte:
		t, err := time.Parse("2006-01-02 15:04:05.999999999-07:00", string(v))
		if err != nil {
			return err
		}
		nt.Time = t
		nt.Valid = true
		return nil
	default:
		return fmt.Errorf("unsupported scan type for NullTime: %T", value)
	}
}

// NullString wraps sql.NullString with convenience scanning.
type NullString struct {
	sql.NullString
}

func (ns *NullString) Scan(value interface{}) error {
	if value == nil {
		ns.NullString = sql.NullString{Valid: false}
		return nil
	}
	switch v := value.(type) {
	case string:
		ns.NullString = sql.NullString{String: v, Valid: true}
		return nil
	case []byte:
		ns.NullString = sql.NullString{String: string(v), Valid: true}
		return nil
	default:
		return fmt.Errorf("unsupported scan type for NullString: %T", value)
	}
}
