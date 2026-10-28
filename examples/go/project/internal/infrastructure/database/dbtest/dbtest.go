// rules/go-server/testing.md: skipped without TEST_DATABASE_URL, failing with CI=true

package dbtest

import (
	"os"
	"testing"

	"example.com/server/internal/infrastructure/database"
)

func Open(t *testing.T) *database.DB {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		if os.Getenv("CI") == "true" {
			t.Fatal("TEST_DATABASE_URL is required in CI")
		}
		t.Skip("TEST_DATABASE_URL is not set")
	}
	db, err := database.New(t.Context(), url, 4)
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	t.Cleanup(db.Close)
	return db
}
