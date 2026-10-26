// rules/go-server/http.md: huma checks route registrations only when they run, so this test runs them

package app_test

import (
	"testing"

	"github.com/danielgtaylor/huma/v2/humatest"
	"github.com/stretchr/testify/assert"

	"example.com/server/internal/app"
)

func TestNew(t *testing.T) {
	t.Run("registers every user route with huma", func(t *testing.T) {
		_, api := humatest.New(t)

		app.New(api, nil)

		for _, path := range []string{"/api/users", "/api/users/{id}", "/api/users/{id}/withdraw"} {
			assert.Contains(t, api.OpenAPI().Paths, path)
		}
	})
}
