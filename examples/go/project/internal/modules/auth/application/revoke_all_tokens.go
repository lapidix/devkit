// rules/go-server/application.md; a stub: the example only calls it

package application

import "context"

type RevokeAllTokensCommand struct {
	UserID string
}

type RevokeAllTokens struct{}

func NewRevokeAllTokens() *RevokeAllTokens {
	return &RevokeAllTokens{}
}

func (uc *RevokeAllTokens) Execute(_ context.Context, _ RevokeAllTokensCommand) error {
	return nil
}
