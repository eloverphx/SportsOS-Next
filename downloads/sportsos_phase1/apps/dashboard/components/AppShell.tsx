'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import type { ReactNode } from 'react';
const links = ['Dashboard','Games','Teams','Organizations','Streaming','Media','Scoreboards','Users','Administration','System Health'];
export function AppShell({ children }: { children: ReactNode }) {
  const router = useRouter();
  function logout() { localStorage.removeItem('sportsos_token'); router.push('/login'); }
  return <div className="shell"><aside><div className="brand">SportsOS</div><nav>{links.map((x) => <Link key={x} href={x === 'Dashboard' ? '/dashboard' : '#'}>{x}</Link>)}</nav></aside><section className="workspace"><header><span>Sports Operations Center</span><button className="secondary" onClick={logout}>Sign out</button></header><div className="content">{children}</div></section></div>;
}
