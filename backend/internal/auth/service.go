package auth

import (
	"errors"
	"time"

	"github.com/jmoiron/sqlx"
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db  *database.DB
	cfg *config.Config
	now func() time.Time
}

func NewService(db *database.DB, cfg *config.Config) *Service {
	return &Service{
		db:  db,
		cfg: cfg,
		now: time.Now,
	}
}

var errNotFound = errors.New("not found")

var _ = sqlx.DB{}
var _ = database.ErrNotFound
