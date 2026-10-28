// rules/database/sqlc.md: the pool, and the transaction that travels in ctx

package database

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Executor has the methods sqlc's DBTX needs, so generated queries run on the pool or on a transaction.
type Executor interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type DB struct {
	pool *pgxpool.Pool
}

type txKey struct{}

func New(ctx context.Context, url string, poolSize int32) (*DB, error) {
	config, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, fmt.Errorf("parse database url: %w", err)
	}
	config.MaxConns = poolSize
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, fmt.Errorf("open database pool: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}
	return &DB{pool: pool}, nil
}

func (d *DB) Conn(ctx context.Context) Executor { //nolint:ireturn // the open transaction or the pool: two concrete types
	if tx, ok := ctx.Value(txKey{}).(pgx.Tx); ok {
		return tx
	}
	return d.pool
}

func (d *DB) Run(ctx context.Context, fn func(ctx context.Context) error) error {
	if _, ok := ctx.Value(txKey{}).(pgx.Tx); ok {
		return fn(ctx) // join the transaction already open
	}
	return pgx.BeginFunc(ctx, d.pool, func(tx pgx.Tx) error {
		return fn(context.WithValue(ctx, txKey{}, tx)) // rolled back when fn returns an error or panics
	})
}

func (d *DB) Close() {
	d.pool.Close()
}
