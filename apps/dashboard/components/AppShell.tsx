"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";
import {
  PERMISSIONS,
  clearAuthentication,
  getStoredUser,
  userHasPermission,
  type AuthenticatedUser,
  type Permission,
} from "../lib/auth";

interface NavigationLink {
  readonly label: string;
  readonly href: string;
  readonly permission?: Permission;
}

const links: readonly NavigationLink[] = [
  { label: "Dashboard", href: "/dashboard" },
  { label: "Organizations", href: "/organizations", permission: PERMISSIONS.ORGANIZATION_READ },
  { label: "Teams", href: "/teams", permission: PERMISSIONS.TEAM_READ },
  { label: "Seasons", href: "/seasons", permission: PERMISSIONS.SEASON_READ },
  { label: "Players", href: "/players", permission: PERMISSIONS.PLAYER_READ },
  { label: "Rosters", href: "/rosters", permission: PERMISSIONS.TEAM_ROSTER_MANAGE },
  { label: "Games", href: "/games", permission: PERMISSIONS.GAME_READ },
  {
    label: "Tournament Director",
    href: "/tournament-director",
    permission: PERMISSIONS.GAME_READ,
  },
  { label: "Streaming", href: "#", permission: PERMISSIONS.STREAM_READ },
  { label: "Scoreboards", href: "/scoreboards", permission: PERMISSIONS.SCOREBOARD_READ },
  { label: "Users", href: "/users", permission: PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE },
  { label: "System Health", href: "/system-health", permission: PERMISSIONS.SYSTEM_READ },
];

export function AppShell({ children }: { readonly children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [user, setUser] = useState<AuthenticatedUser | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => setUser(getStoredUser()), []);
  useEffect(() => setMenuOpen(false), [pathname]);

  useEffect(() => {
    if (!menuOpen) return;
    const close = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMenuOpen(false);
    };
    document.addEventListener("keydown", close);
    document.body.classList.add("menuOpenBody");
    return () => {
      document.removeEventListener("keydown", close);
      document.body.classList.remove("menuOpenBody");
    };
  }, [menuOpen]);

  const visibleLinks = links.filter(
    (link) => !link.permission || userHasPermission(user, link.permission),
  );

  function logout(): void {
    clearAuthentication();
    router.replace("/login");
  }

  function isActive(href: string): boolean {
    return href !== "#" && (pathname === href || pathname.startsWith(`${href}/`));
  }

  return (
    <div className="shell">
      {menuOpen && (
        <button
          className="menuBackdrop"
          aria-label="Close navigation"
          onClick={() => setMenuOpen(false)}
        />
      )}

      <aside className={menuOpen ? "open" : ""}>
        <div className="sidebarHead">
          <div className="brand">SportsOS</div>
          <button
            className="menuClose secondary"
            aria-label="Close navigation"
            onClick={() => setMenuOpen(false)}
          >
            ×
          </button>
        </div>

        <nav>
          {visibleLinks.map((link) => (
            <Link
              className={isActive(link.href) ? "active" : ""}
              key={link.label}
              href={link.href}
              onClick={() => setMenuOpen(false)}
            >
              {link.label}
            </Link>
          ))}
        </nav>
      </aside>

      <section className="workspace">
        <header>
          <div className="headerIdentity">
            <button
              className="menuToggle secondary"
              aria-label="Open navigation"
              aria-expanded={menuOpen}
              onClick={() => setMenuOpen((open) => !open)}
            >
              ☰
            </button>
            <span>
              {user
                ? `${user.firstName} ${user.lastName} · ${user.organizationName}`
                : "Sports Operations Center"}
            </span>
          </div>

          <button className="secondary" onClick={logout}>
            Sign out
          </button>
        </header>

        <div className="content">{children}</div>
      </section>
    </div>
  );
}
