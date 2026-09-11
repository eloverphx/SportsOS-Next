"use client";

import Link from "next/link";
import { useEffect, useState, type FormEvent } from "react";
import { getApiUrl } from "../../lib/api-url";

interface SignupOrganization {
  readonly id: number;
  readonly name: string;
}

interface SignupOrganizationsResponse {
  readonly organizations: SignupOrganization[];
}

interface SignupSuccessResponse {
  readonly success: true;
  readonly status: "PENDING_APPROVAL";
  readonly message: string;
}

interface ErrorResponse {
  readonly error?: string;
}

export default function SignupPage() {
  const [organizations, setOrganizations] = useState<SignupOrganization[]>([]);
  const [organizationId, setOrganizationId] = useState("");
  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loadingOrganizations, setLoadingOrganizations] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  useEffect(() => {
    let active = true;

    async function loadOrganizations(): Promise<void> {
      try {
        const response = await fetch(`${getApiUrl()}/auth/signup-organizations`);
        const body = (await response.json()) as SignupOrganizationsResponse | ErrorResponse;

        if (!response.ok) {
          throw new Error((body as ErrorResponse).error ?? "Could not load organizations");
        }

        if (active) {
          const loaded = (body as SignupOrganizationsResponse).organizations;
          setOrganizations(loaded);

          const onlyOrganization = loaded.length === 1 ? loaded[0] : undefined;

          if (onlyOrganization) {
            setOrganizationId(String(onlyOrganization.id));
          }
        }
      } catch (caughtError) {
        if (active) {
          setError(
            caughtError instanceof Error
              ? caughtError.message
              : "Could not connect to the SportsOS API",
          );
        }
      } finally {
        if (active) {
          setLoadingOrganizations(false);
        }
      }
    }

    void loadOrganizations();

    return () => {
      active = false;
    };
  }, []);

  async function submit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    setBusy(true);
    setError("");
    setSuccess("");

    try {
      const response = await fetch(`${getApiUrl()}/auth/signup`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          organizationId: Number(organizationId),
          firstName,
          lastName,
          email,
          username,
          password,
        }),
      });

      const body = (await response.json()) as SignupSuccessResponse | ErrorResponse;

      if (!response.ok) {
        throw new Error((body as ErrorResponse).error ?? "Signup request failed");
      }

      const result = body as SignupSuccessResponse;
      setSuccess(result.message);
      setPassword("");
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not connect to the SportsOS API",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="center">
      <form className="login" onSubmit={submit}>
        <div className="brand large">SportsOS</div>

        <h1>Request access</h1>
        <p>Choose your organization. An administrator must approve your account before sign in.</p>

        <label>
          Organization
          <select
            required
            disabled={loadingOrganizations || organizations.length === 0}
            value={organizationId}
            onChange={(event) => setOrganizationId(event.target.value)}
          >
            <option value="">
              {loadingOrganizations
                ? "Loading organizations…"
                : organizations.length === 0
                  ? "No organizations available"
                  : "Select organization"}
            </option>

            {organizations.map((organization) => (
              <option key={organization.id} value={organization.id}>
                {organization.name}
              </option>
            ))}
          </select>
        </label>

        <input
          required
          autoComplete="given-name"
          placeholder="First name"
          value={firstName}
          onChange={(event) => setFirstName(event.target.value)}
        />

        <input
          required
          autoComplete="family-name"
          placeholder="Last name"
          value={lastName}
          onChange={(event) => setLastName(event.target.value)}
        />

        <input
          required
          type="email"
          autoComplete="email"
          placeholder="Email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />

        <input
          required
          minLength={3}
          autoComplete="username"
          placeholder="Username"
          value={username}
          onChange={(event) => setUsername(event.target.value)}
        />

        <input
          required
          minLength={10}
          maxLength={128}
          type="password"
          autoComplete="new-password"
          placeholder="Password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />

        {error && <p className="error">{error}</p>}
        {success && <p>{success}</p>}

        <button disabled={busy || loadingOrganizations || organizations.length === 0} type="submit">
          {busy ? "Submitting…" : "Request access"}
        </button>

        <p className="muted">
          Already approved? <Link href="/login">Sign in</Link>
        </p>
      </form>
    </main>
  );
}
