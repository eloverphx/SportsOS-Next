import { describe, expect, it } from "vitest";
import { parseByteRange } from "../src/modules/media-playback/range.js";

describe("M37.10 media playback range parser", () => {
  it("uses the full object when Range is absent", () => {
    expect(parseByteRange(undefined, 1000)).toEqual({ kind: "full" });
  });

  it("parses an explicit byte range", () => {
    expect(parseByteRange("bytes=100-299", 1000)).toEqual({
      kind: "range",
      range: { start: 100, end: 299, length: 200 },
    });
  });

  it("clamps an oversized end offset", () => {
    expect(parseByteRange("bytes=900-5000", 1000)).toEqual({
      kind: "range",
      range: { start: 900, end: 999, length: 100 },
    });
  });

  it("parses open-ended and suffix ranges", () => {
    expect(parseByteRange("bytes=800-", 1000)).toEqual({
      kind: "range",
      range: { start: 800, end: 999, length: 200 },
    });

    expect(parseByteRange("bytes=-250", 1000)).toEqual({
      kind: "range",
      range: { start: 750, end: 999, length: 250 },
    });
  });

  it("rejects malformed or unsatisfiable ranges", () => {
    for (const value of [
      "items=0-10",
      "bytes=-0",
      "bytes=1000-",
      "bytes=500-100",
      "bytes=0-1,4-5",
    ]) {
      expect(parseByteRange(value, 1000)).toEqual({ kind: "invalid" });
    }
  });
});
