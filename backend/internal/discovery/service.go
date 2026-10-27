package discovery

import (
	"grepmind-near/backend/pkg/config"
	"grepmind-near/backend/pkg/database"
)

type Service struct {
	db  *database.DB
	cfg *config.Config
}

func NewService(db *database.DB, cfg *config.Config) *Service {
	return &Service{db: db, cfg: cfg}
}

var _ = config.Config{}
