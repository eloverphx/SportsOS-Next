export interface PaginationInput {
  page: number;
  pageSize: number;
}

export interface PaginationMetadata {
  page: number;
  pageSize: number;
  totalItems: number;
  totalPages: number;
  hasPreviousPage: boolean;
  hasNextPage: boolean;
}

export interface PaginatedResponse<TItem> {
  items: ReadonlyArray<TItem>;
  pagination: PaginationMetadata;
}
