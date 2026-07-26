import { config } from '@sportsos/config';

export function logoUrl(assetId: number | null): string | null {
  return assetId ? `${config.api.publicUrl}/media/${assetId}` : null;
}
