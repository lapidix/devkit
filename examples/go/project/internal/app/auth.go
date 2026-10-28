// rules/go-server/architecture.md: one composition file per module

package app

import "example.com/server/internal/modules/auth/application"

type authModule struct {
	revokeAllTokens *application.RevokeAllTokens // the user module revokes a withdrawn user's tokens through it
}

func newAuthModule() authModule {
	return authModule{revokeAllTokens: application.NewRevokeAllTokens()}
}
