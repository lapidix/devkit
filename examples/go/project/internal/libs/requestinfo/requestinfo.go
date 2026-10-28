// rules/go-server/http.md: the request id, and the user once authentication runs; set by middleware the example does not need

package requestinfo

import "context"

type Info struct {
	ID     string
	UserID string
}

type ctxKey struct{}

func With(ctx context.Context, info *Info) context.Context {
	return context.WithValue(ctx, ctxKey{}, info)
}

// From returns the request's info, which the middleware fills in as it learns more, or an empty one outside a request.
func From(ctx context.Context) *Info {
	if info, ok := ctx.Value(ctxKey{}).(*Info); ok {
		return info
	}
	return &Info{}
}
