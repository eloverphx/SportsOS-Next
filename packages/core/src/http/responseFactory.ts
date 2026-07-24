import type { ApiErrorResponse, ApiSuccessResponse } from "../types/ApiResponse.js";
import type { RequestContext } from "./RequestContext.js";

export function successResponse<T>(
  context: RequestContext,
  data: T
): ApiSuccessResponse<T> {
  return {
    success: true,
    requestId: context.requestId,
    timestamp: context.timestamp,
    data
  };
}

export function errorResponse(
  context: RequestContext,
  code: string,
  message: string,
  details?: unknown
): ApiErrorResponse {
  return {
    success: false,
    requestId: context.requestId,
    timestamp: context.timestamp,
    error: {
      code,
      message,
      details
    }
  };
}