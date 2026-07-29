"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { getApiUrl } from "../../lib/api-url";
import { storeAuthentication, type LoginResponse } from "../../lib/auth";

interface LoginErrorResponse {
  readonly error?: string;
}
export default function LoginPage() {
  const router = useRouter();

  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    setBusy(true);
    setError("");

    try {
      const response = await fetch(`${getApiUrl()}/auth/login`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          identifier,
          password,
        }),
      });

      const body = (await response.json()) as LoginResponse | LoginErrorResponse;

      if (!response.ok) {
        const errorBody = body as LoginErrorResponse;

        throw new Error(errorBody.error ?? "Login failed");
      }

      const login = body as LoginResponse;

      if (!login.token || !login.user) {
        throw new Error("The login response was incomplete");
      }

      storeAuthentication(login.token, login.user);

      router.push("/dashboard");
      router.refresh();
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Unable to connect to the SportsOS API",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="center">
      <form className="login" onSubmit={submit}>
        <div className="brand large">SportsOS</div>

        <h1>Sign in</h1>
        <p>Access your sports operations center.</p>

        <input
          autoComplete="username"
          placeholder="Username or email"
          value={identifier}
          onChange={(event) => setIdentifier(event.target.value)}
          required
        />

        <input
          autoComplete="current-password"
          type="password"
          placeholder="Password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
          required
        />

        {error && <p className="error">{error}</p>}

        <button disabled={busy} type="submit">
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </main>
  );
}
