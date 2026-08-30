import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.5 encoder runtime adapter / FFmpeg process control", () => {
  const runtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntime.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const credentials =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamCredentialResolver.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/encoderSessions.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("launches FFmpeg without a shell", () => {
    expect(
      runtime,
    ).toContain(
      "spawn(",
    );

    expect(
      runtime,
    ).toContain(
      "shell: false",
    );

    expect(
      runtime,
    ).toContain(
      "SPORTSOS_FFMPEG_PATH",
    );
  });

  it("requires a server-side source URL", () => {
    expect(
      runtime,
    ).toContain(
      "SPORTSOS_ENCODER_SOURCE_URL",
    );

    expect(
      runtime,
    ).toContain(
      "SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE",
    );
  });

  it("resolves credentials only from environment references", () => {
    expect(
      credentials,
    ).toContain(
      '"env://"',
    );

    expect(
      credentials,
    ).toContain(
      "process.env",
    );

    expect(
      credentials,
    ).not.toContain(
      "console.log",
    );
  });

  it("supports RTMP FLV and SRT MPEG-TS outputs", () => {
    expect(
      runtime,
    ).toContain(
      '"flv"',
    );

    expect(
      runtime,
    ).toContain(
      '"mpegts"',
    );
  });

  it("promotes a surviving runtime to LIVE", () => {
    expect(
      runtime,
    ).toContain(
      "markEncoderLive",
    );

    expect(
      runtime,
    ).toContain(
      "2000",
    );
  });

  it("stops gracefully before forcing termination", () => {
    expect(
      runtime,
    ).toContain(
      '"SIGTERM"',
    );

    expect(
      runtime,
    ).toContain(
      '"SIGKILL"',
    );

    expect(
      runtime,
    ).toContain(
      "5000",
    );
  });

  it("wires start and stop API actions to the runtime adapter", () => {
    expect(
      route,
    ).toContain(
      "startEncoderRuntime",
    );

    expect(
      route,
    ).toContain(
      "stopEncoderRuntime",
    );

    expect(
      route,
    ).toContain(
      "runtimeActive",
    );
  });
});
