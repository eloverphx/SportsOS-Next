export interface ApiSuccessResponse<TData> {
  success: true;
  requestId: string;
  timestamp: string;
  data: TData;
}

export interface ApiErrorBody {
  code: string;
  message: string;
  details?: unknown;
}

export interface ApiErrorResponse {
  success: false;
  requestId: string;
  timestamp: string;
  error: ApiErrorBody;
}

export type ApiResponse<TData> =
  | ApiSuccessResponse<TData>
  | ApiErrorResponse;