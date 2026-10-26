// Follows rules/frontend/entity-data-access.md ("HTTP client", unwrap) and rules/api/contract.md (standard response, lists).
import type { ResponsePromise } from 'arthron';

export type ApiResponse<T> = {
  result: T;
  message: string | null;
  timestamp: string;
  requestId: string;
  errorCode: string | null;
};

export type PaginatedDto<T> = { items: T[]; total: number; page: number; pageSize: number };

export type PageResult<T> = { items: T[]; total: number; page: number; pageSize: number };

export async function unwrap<T>(call: ResponsePromise): Promise<T> {
  const body = await call.json<ApiResponse<T>>();
  return body.result;
}

export function toEntityList<D, E>(dto: PaginatedDto<D>, toEntity: (item: D) => E): PageResult<E> {
  return { items: dto.items.map((item) => toEntity(item)), total: dto.total, page: dto.page, pageSize: dto.pageSize };
}
