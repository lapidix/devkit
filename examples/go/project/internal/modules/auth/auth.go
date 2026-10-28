// rules/go-server/architecture.md: the module root re-exports what other modules may use

package auth

import "example.com/server/internal/modules/auth/application"

type (
	RevokeAllTokens        = application.RevokeAllTokens
	RevokeAllTokensCommand = application.RevokeAllTokensCommand
)
