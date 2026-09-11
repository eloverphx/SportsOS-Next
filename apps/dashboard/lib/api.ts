import { getStoredToken } from "./auth";
import { refreshAuthentication } from "./session-refresh";

export const API = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4001";

function headersFor(options: RequestInit, accessToken: string): Headers {
  const headers = new Headers(options.headers);

  headers.set("Authorization", `Bearer ${accessToken}`);

  if (
    options.body !== undefined &&
    !(options.body instanceof FormData) &&
    !headers.has("Content-Type")
  ) {
    headers.set("Content-Type", "application/json");
  }

  return headers;
}

async function fetchApi(
  path: string,
  options: RequestInit,
  accessToken: string,
): Promise<Response> {
  return await fetch(`${API}${path}`, {
    ...options,
    headers: headersFor(options, accessToken),
  });
}

export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const initialToken = getStoredToken();

  if (!initialToken) {
    throw new Error("Authentication is required");
  }

  let response: Response;

  try {
    response = await fetchApi(path, options, initialToken);

    if (response.status === 401) {
      const refreshedToken = await refreshAuthentication();
      response = await fetchApi(path, options, refreshedToken);
    }
  } catch (error) {
    if (error instanceof Error) {
      throw error;
    }

    throw new Error("Could not connect to the SportsOS API");
  }

  const body = await response.json().catch(() => ({}));

  if (!response.ok) {
    const message =
      typeof body.error === "string" && body.error.trim()
        ? body.error
        : response.status === 401
          ? "Your session has expired. Sign in again."
          : response.status === 403
            ? "You do not have permission to perform this action."
            : `Request failed (${response.status})`;

    throw new Error(message);
  }

  return body as T;
}

export async function uploadLogo(
  file: File,
  organizationId?: number | null,
): Promise<{ id: number; url: string }> {
  if (file.size > 5 * 1024 * 1024) throw new Error("Logo must be 5 MB or smaller");

  const dataBase64 = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();

    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error("Could not read logo"));
    reader.readAsDataURL(file);
  });

  return api("/media/logo", {
    method: "POST",
    body: JSON.stringify({
      organizationId: organizationId ?? null,
      fileName: file.name,
      mimeType: file.type,
      dataBase64,
    }),
  });
}
