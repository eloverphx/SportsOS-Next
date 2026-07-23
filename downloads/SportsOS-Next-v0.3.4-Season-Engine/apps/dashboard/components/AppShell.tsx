'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import type { ReactNode } from 'react';
const links = [
  ['Dashboard','/dashboard'], ['Organizations','/organizations'], ['Teams','/teams'], ['Seasons','/seasons'], ['Players','/players'], ['Games','#'],
  ['Streaming','#'], ['Scoreboards','#'], ['Media','#'], ['Users','#'], ['Administration','#'], ['System Health','/dashboard']
];
export function AppShell({ children }: { children: ReactNode }) {
  const router = useRouter(); const pathname = usePathname();
  function logout() { localStorage.removeItem('sportsos_token'); router.push('/login'); }
  return <div className="shell"><aside><div className="brand">SportsOS</div><nav>{links.map(([label,href]) => <Link className={href !== '#' && pathname.startsWith(href) ? 'active' : ''} key={label} href={href}>{label}</Link>)}</nav></aside><section className="workspace"><header><span>Sports Operations Center</span><button className="secondary" onClick={logout}>Sign out</button></header><div className="content">{children}</div></section></div>;
}
