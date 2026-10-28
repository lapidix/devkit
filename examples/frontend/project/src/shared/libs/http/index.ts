// Follows rules/frontend/shared.md (libs/http): slices import the client and its helpers from here.
export { ApiContractError, required } from './api.contract';
export { ApiError, isApiError } from './api.errors';
export { type ApiResponse, type PageResult, type PaginatedDto, toEntityList, unwrap } from './api.response';
export { type HttpClient, httpClient } from './http.client';
