"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

function getApiUrl(): string {
  const configuredUrl = process.env.NEXT_PUBLIC_API_URL;

  if (configuredUrl) {
    return configuredUrl.replace(/\/$/, "");
  }

  if (typeof window !== "undefined") {
    return `${window.location.protocol}//${window.location.hostname}:4001`;
  }

  return "http://localhost:4001";
}

interface LoginResponse {
  token?: string;
  user?: unknown;
  error?: string;
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

      const body = (await response.json()) as LoginResponse;

      if (!response.ok) {
        throw new Error(body.error ?? "Login failed");
      }

      if (!body.token || !body.user) {
        throw new Error("The login response was incomplete");
      }

      localStorage.setItem("sportsos_token", body.token);
      localStorage.setItem("sportsos_user", JSON.stringify(body.user));

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
