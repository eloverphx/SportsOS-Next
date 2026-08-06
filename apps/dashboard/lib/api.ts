export const API = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4001";
export function token(): string {
  return typeof window === "undefined" ? "" : (localStorage.getItem("sportsos_token") ?? "");
}
export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = new Headers(options.headers);
  headers.set("Authorization", `Bearer ${token()}`);
  if (
    options.body !== undefined &&
    !(options.body instanceof FormData) &&
    !headers.has("Content-Type")
  ) {
    headers.set("Content-Type", "application/json");
  }
  let response: Response;

  try {
    response = await fetch(`${API}${path}`, { ...options, headers });
  } catch {
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
