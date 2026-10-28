// rules/go-server/architecture.md: the composition root; the server, middleware and lifecycle are left out, as the checks run none of them

package app

import (
	"github.com/danielgtaylor/huma/v2"

	"example.com/server/internal/infrastructure/database"
)

// New builds every module and registers its routes on api.
func New(api huma.API, db *database.DB) {
	auth := newAuthModule()
	user := newUserModule(db, auth.revokeAllTokens)
	user.handler.Register(api)
}
