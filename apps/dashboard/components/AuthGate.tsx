"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import { clearAuthentication, getStoredToken } from "../lib/auth";
import { refreshCurrentUser } from "../lib/session";

interface AuthGateProps {
  readonly children: ReactNode;
}

export function AuthGate({ children }: AuthGateProps) {
  const router = useRouter();
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let active = true;

    async function verifySession(): Promise<void> {
      const token = getStoredToken();

      if (!token) {
        router.replace("/login");
        return;
      }

      try {
        await refreshCurrentUser();

        if (active) {
          setReady(true);
        }
      } catch {
        clearAuthentication();

        if (active) {
          router.replace("/login");
        }
      }
    }

    void verifySession();

    return () => {
      active = false;
    };
  }, [router]);

  if (!ready) {
    return (
      <main className="center">
        <p>Loading SportsOS…</p>
      </main>
    );
  }

  return <>{children}</>;
}
