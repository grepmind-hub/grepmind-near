package database

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/jmoiron/sqlx"
)

type DB struct {
	*sqlx.DB
}

func Open(dsn string, maxOpenConns, maxIdleConns int, connMaxLifetime time.Duration) (*DB, error) {
	db, err := sqlx.Open("pgx", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	db.SetMaxOpenConns(maxOpenConns)
	db.SetMaxIdleConns(maxIdleConns)
	db.SetConnMaxLifetime(connMaxLifetime)

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping database: %w", err)
	}

	return &DB{db}, nil
}

func (d *DB) Close() error {
	return d.DB.Close()
}

func (d *DB) GetContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return d.DB.GetContext(ctx, dest, query, args...)
}

func (d *DB) SelectContext(ctx context.Context, dest interface{}, query string, args ...interface{}) error {
	return d.DB.SelectContext(ctx, dest, query, args...)
}

func (d *DB) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	return d.DB.ExecContext(ctx, query, args...)
}

func (d *DB) QueryRowxContext(ctx context.Context, query string, args ...interface{}) *sqlx.Row {
	return d.DB.QueryRowxContext(ctx, query, args...)
}

func (d *DB) Transaction(ctx context.Context, fn func(*sqlx.Tx) error) error {
	tx, err := d.DB.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		if rbErr := tx.Rollback(); rbErr != nil {
			return fmt.Errorf("tx error: %w, rollback error: %v", err, rbErr)
		}
		return err
	}
	return tx.Commit()
}
