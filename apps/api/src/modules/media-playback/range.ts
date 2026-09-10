export interface ByteRange {
  readonly start: number;
  readonly end: number;
  readonly length: number;
}

export type ByteRangeResult =
  | { readonly kind: "full" }
  | { readonly kind: "range"; readonly range: ByteRange }
  | { readonly kind: "invalid" };

export function parseByteRange(
  rangeHeader: string | undefined,
  sizeBytes: number,
): ByteRangeResult {
  if (!rangeHeader) {
    return { kind: "full" };
  }

  if (!Number.isSafeInteger(sizeBytes) || sizeBytes <= 0) {
    return { kind: "invalid" };
  }

  const match = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());

  if (!match) {
    return { kind: "invalid" };
  }

  const [, rawStart, rawEnd] = match;

  if (!rawStart && !rawEnd) {
    return { kind: "invalid" };
  }

  let start: number;
  let end: number;

  if (!rawStart) {
    const suffixLength = Number(rawEnd);

    if (!Number.isSafeInteger(suffixLength) || suffixLength <= 0) {
      return { kind: "invalid" };
    }

    start = Math.max(0, sizeBytes - suffixLength);
    end = sizeBytes - 1;
  } else {
    start = Number(rawStart);

    if (!Number.isSafeInteger(start) || start < 0 || start >= sizeBytes) {
      return { kind: "invalid" };
    }

    if (!rawEnd) {
      end = sizeBytes - 1;
    } else {
      end = Number(rawEnd);

      if (!Number.isSafeInteger(end) || end < start) {
        return { kind: "invalid" };
      }

      end = Math.min(end, sizeBytes - 1);
    }
  }

  return {
    kind: "range",
    range: {
      start,
      end,
      length: end - start + 1,
    },
  };
}
