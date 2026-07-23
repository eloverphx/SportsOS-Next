import './globals.css';
export const metadata = { title: 'SportsOS', description: 'SportsOS control platform' };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
