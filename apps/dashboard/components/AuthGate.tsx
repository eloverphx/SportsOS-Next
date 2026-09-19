"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { clearAuthentication, getStoredToken } from "../lib/auth";
import { ApiError } from "../lib/authenticated-api";
import { refreshCurrentUser } from "../lib/session";

interface AuthGateProps {
  readonly children: ReactNode;
}

export function AuthGate({ children }: AuthGateProps) {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  const [temporarilyUnavailable, setTemporarilyUnavailable] = useState(false);
  const [retryNonce, setRetryNonce] = useState(0);

  useEffect(() => {
    let active = true;

    async function verifySession(): Promise<void> {
      const token = getStoredToken();

      if (!token) {
        router.replace("/login");
        return;
      }

      setTemporarilyUnavailable(false);

      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          await refreshCurrentUser();

          if (active) {
            setReady(true);
            setTemporarilyUnavailable(false);
          }

          return;
        } catch (error) {
          const confirmedAuthenticationFailure =
            error instanceof ApiError &&
            (error.status === 400 || error.status === 401 || error.status === 403);

          if (confirmedAuthenticationFailure) {
            clearAuthentication();

            if (active) {
              router.replace("/login");
            }

            return;
          }

          if (attempt < 2) {
            await new Promise((resolve) => window.setTimeout(resolve, 1000 * (attempt + 1)));

            if (!active) return;

            continue;
          }

          /*
           * Preserve the stored session on transient API/network failures.
           * The operator can retry without being forced to sign in again.
           */
          if (active) {
            setTemporarilyUnavailable(true);
          }
        }
      }
    }

    void verifySession();

    return () => {
      active = false;
    };
  }, [router, retryNonce]);

  if (!ready) {
    return (
      <main className="center">
        {temporarilyUnavailable ? (
          <div className="login">
            <div className="brand large">SportsOS</div>
            <h1>Connection interrupted</h1>
            <p>Your session is still saved. SportsOS could not reach the API.</p>
            <button
              type="button"
              onClick={() => {
                setTemporarilyUnavailable(false);
                setRetryNonce((value) => value + 1);
              }}
            >
              Retry connection
            </button>
          </div>
        ) : (
          <p>Reconnecting to SportsOS…</p>
        )}
      </main>
    );
  }

  return <>{children}</>;
}
