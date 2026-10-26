// Follows rules/frontend/entity-data-access.md, "HTTP client" (apiErrors, ApiError, isApiError).
import { createPlugin, isArthronError } from 'arthron';
import type { ApiResponse } from './api.response';

type ApiErrorDetails = { status: number; errorCode: string | null; requestId: string | null; message: string };

export class ApiError extends Error {
  override readonly name = 'ApiError';
  readonly status: number;
  readonly errorCode: string | null;
  readonly requestId: string | null;

  constructor(details: ApiErrorDetails, options?: ErrorOptions) {
    super(details.message, options);
    this.status = details.status;
    this.errorCode = details.errorCode;
    this.requestId = details.requestId;
  }
}

export function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError;
}

export const apiErrors = createPlugin({
  pluginName: 'apiErrors',
  async middleware(requestContext, next) {
    try {
      return await next(requestContext);
    } catch (error) {
      if (!isArthronError(error) || error.status === 0) throw error;
      const body = typeof error.payload === 'object' ? (error.payload as Partial<ApiResponse<unknown>> | null) : null;
      throw new ApiError(
        {
          status: error.status,
          errorCode: body?.errorCode ?? null,
          requestId: body?.requestId ?? null,
          message: body?.message ?? error.message,
        },
        { cause: error },
      );
    }
  },
});
