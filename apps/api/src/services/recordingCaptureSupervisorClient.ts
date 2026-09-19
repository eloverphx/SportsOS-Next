export interface RecordingCaptureSupervisorSession {
  readonly gameId: string;
  readonly recordingId: number;
  readonly capturePath: string;
  readonly running: boolean;
  readonly exitCode: number | null;
  readonly startedAt: string;
}

export interface RecordingCaptureSupervisorStopResult {
  readonly gameId: string;
  readonly recordingId: number;
  readonly capturePath: string;
  readonly stderrTail: string;
  readonly exitCode: number | null;
}

function supervisorUrl(): string | null {
  const value = process.env.SPORTSOS_CAPTURE_SUPERVISOR_URL?.trim();
  return value ? value.replace(/\/+$/, "") : null;
}

function supervisorHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };

  const token = process.env.SPORTSOS_CAPTURE_SUPERVISOR_TOKEN?.trim();

  if (token) {
    headers.authorization = `Bearer ${token}`;
  }

  return headers;
}

export function isRecordingCaptureSupervisorConfigured(): boolean {
  return supervisorUrl() !== null;
}

async function supervisorRequest<T>(pathname: string, options: RequestInit = {}): Promise<T> {
  const baseUrl = supervisorUrl();

  if (!baseUrl) {
    throw new Error("Recording capture supervisor is not configured.");
  }

  const response = await fetch(`${baseUrl}${pathname}`, {
    ...options,
    headers: {
      ...supervisorHeaders(),
      ...options.headers,
    },
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");

    throw new Error(
      `Recording capture supervisor request failed (${response.status})${
        body ? `: ${body.slice(0, 1000)}` : ""
      }`,
    );
  }

  return (await response.json()) as T;
}

export async function startSupervisorRecordingCapture(input: {
  gameId: string;
  recordingId: number;
  sourceUrl: string;
}): Promise<RecordingCaptureSupervisorSession> {
  return await supervisorRequest<RecordingCaptureSupervisorSession>("/start", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export async function stopSupervisorRecordingCapture(
  gameId: string,
): Promise<RecordingCaptureSupervisorStopResult | null> {
  const baseUrl = supervisorUrl();

  if (!baseUrl) {
    throw new Error("Recording capture supervisor is not configured.");
  }

  const response = await fetch(`${baseUrl}/stop`, {
    method: "POST",
    headers: supervisorHeaders(),
    body: JSON.stringify({ gameId }),
  });

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    const body = await response.text().catch(() => "");

    throw new Error(
      `Recording capture supervisor stop failed (${response.status})${
        body ? `: ${body.slice(0, 1000)}` : ""
      }`,
    );
  }

  return (await response.json()) as RecordingCaptureSupervisorStopResult;
}

export async function listSupervisorRecordingCaptures(): Promise<
  RecordingCaptureSupervisorSession[]
> {
  const result = await supervisorRequest<{
    sessions: RecordingCaptureSupervisorSession[];
  }>("/sessions");

  return result.sessions;
}
