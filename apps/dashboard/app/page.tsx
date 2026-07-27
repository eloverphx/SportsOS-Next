"use client";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
const API = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4001";
export default function Home() {
  const router = useRouter();
  useEffect(() => {
    fetch(`${API}/setup/status`)
      .then((r) => r.json())
      .then((d) => router.replace(d.complete ? "/login" : "/setup"))
      .catch(() => router.replace("/login"));
  }, [router]);
  return (
    <main className="center">
      <div className="card">Loading SportsOS…</div>
    </main>
  );
}
