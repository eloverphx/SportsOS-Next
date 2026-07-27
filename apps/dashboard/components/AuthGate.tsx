"use client";
import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
const API = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4001";
export function AuthGate({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [ready, setReady] = useState(false);
  useEffect(() => {
    const token = localStorage.getItem("sportsos_token");
    if (!token) {
      router.replace("/login");
      return;
    }
    fetch(`${API}/auth/me`, { headers: { Authorization: `Bearer ${token}` } })
      .then((r) => {
        if (!r.ok) throw new Error();
        return r.json();
      })
      .then(() => setReady(true))
      .catch(() => {
        localStorage.removeItem("sportsos_token");
        router.replace("/login");
      });
  }, [router]);
  if (!ready)
    return (
      <main className="center">
        <div className="card">Checking session…</div>
      </main>
    );
  return <>{children}</>;
}
