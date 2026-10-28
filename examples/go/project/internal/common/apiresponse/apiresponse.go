// rules/go-server/http.md: the standard response for successes; the error mapping (Install) is left out, as the example never calls it

package apiresponse

import (
	"context"
	"time"

	"example.com/server/internal/libs/requestinfo"
	"example.com/server/internal/shared/page"
)

type Body[T any] struct {
	Result    T       `json:"result"`
	Message   *string `json:"message"`
	Timestamp string  `json:"timestamp"`
	RequestID string  `json:"requestId"`
	ErrorCode *string `json:"errorCode"`
}

type Output[T any] struct {
	Body Body[T]
}

type Page[T any] struct {
	Items    []T `json:"items"`
	Total    int `json:"total"`
	Page     int `json:"page"`
	PageSize int `json:"pageSize"`
}

func OK[T any](ctx context.Context, result T) *Output[T] {
	return &Output[T]{Body: Body[T]{
		Result:    result,
		Timestamp: time.Now().UTC().Format(time.RFC3339),
		RequestID: requestinfo.From(ctx).ID,
	}}
}

func Empty(ctx context.Context) *Output[*struct{}] {
	return OK[*struct{}](ctx, nil)
}

// FromPage keeps the page info; page.Map builds the items with make, so an empty list encodes as [], never null.
func FromPage[T, R any](p page.Result[T], toItem func(T) R) Page[R] {
	mapped := page.Map(p, toItem)
	return Page[R]{Items: mapped.Items, Total: mapped.Total, Page: mapped.Page, PageSize: mapped.PageSize}
}
