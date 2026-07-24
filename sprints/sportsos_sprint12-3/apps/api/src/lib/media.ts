import { env } from '../config/env.js';

export function logoUrl(assetId: number | null): string | null {
  return assetId ? `${env.PUBLIC_API_URL}/media/${assetId}` : null;
}
