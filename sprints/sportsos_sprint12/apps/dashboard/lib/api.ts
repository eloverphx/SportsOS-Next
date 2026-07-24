export const API = process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:4001';
export function token(): string { return typeof window === 'undefined' ? '' : localStorage.getItem('sportsos_token') ?? ''; }
export async function api<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...options,
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token()}`, ...(options.headers ?? {}) }
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error ?? `Request failed (${response.status})`);
  return body as T;
}
export async function uploadLogo(file: File, organizationId?: number | null): Promise<{ id: number; url: string }> {
  if (file.size > 5 * 1024 * 1024) throw new Error('Logo must be 5 MB or smaller');
  const dataBase64 = await new Promise<string>((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result)); reader.onerror = () => reject(new Error('Could not read logo')); reader.readAsDataURL(file); });
  return api('/media/logo', { method: 'POST', body: JSON.stringify({ organizationId: organizationId ?? null, fileName: file.name, mimeType: file.type, dataBase64 }) });
}
