export function buildRecordingCaptureArgs(sourceUrl: string, outputPath: string): string[] {
  return [
    "-hide_banner",
    "-nostdin",
    "-loglevel",
    "warning",
    "-i",
    sourceUrl,
    "-map",
    "0:v?",
    "-map",
    "0:a?",
    "-c",
    "copy",
    "-f",
    "matroska",
    outputPath,
  ];
}

export function buildRecordingRemuxArgs(inputPath: string, outputPath: string): string[] {
  return [
    "-hide_banner",
    "-nostdin",
    "-loglevel",
    "error",
    "-y",
    "-i",
    inputPath,
    "-map",
    "0:v:0?",
    "-map",
    "0:a:0?",
    "-c",
    "copy",
    "-movflags",
    "+faststart",
    outputPath,
  ];
}

export function buildRecordingTranscodeArgs(inputPath: string, outputPath: string): string[] {
  return [
    "-hide_banner",
    "-nostdin",
    "-loglevel",
    "error",
    "-y",
    "-i",
    inputPath,
    "-map",
    "0:v:0?",
    "-map",
    "0:a:0?",
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-crf",
    "23",
    "-c:a",
    "aac",
    "-b:a",
    "160k",
    "-movflags",
    "+faststart",
    outputPath,
  ];
}
