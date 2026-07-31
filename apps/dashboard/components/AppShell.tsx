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
  {
    label: "Dashboard",
    href: "/dashboard",
  },
  {
    label: "Organizations",
    href: "/organizations",
    permission: PERMISSIONS.ORGANIZATION_READ,
  },
  {
    label: "Teams",
    href: "/teams",
    permission: PERMISSIONS.TEAM_READ,
  },
  {
    label: "Seasons",
    href: "/seasons",
    permission: PERMISSIONS.SEASON_READ,
  },
  {
    label: "Players",
    href: "/players",
    permission: PERMISSIONS.PLAYER_READ,
  },
  {
    label: "Rosters",
    href: "/rosters",
    permission: PERMISSIONS.TEAM_ROSTER_MANAGE,
  },
  {
    label: "Games",
    href: "/games",
    permission: PERMISSIONS.GAME_READ,
  },
  {
    label: "Streaming",
    href: "#",
    permission: PERMISSIONS.STREAM_READ,
  },
  {
    label: "Scoreboards",
    href: "#",
    permission: PERMISSIONS.SCOREBOARD_READ,
  },
  {
    label: "Users",
    href: "/users",
    permission: PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE,
  },
  {
    label: "System Health",
    href: "/system-health",
    permission: PERMISSIONS.SYSTEM_READ,
  },
];

interface AppShellProps {
  readonly children: ReactNode;
}

export function AppShell({ children }: AppShellProps) {
  const router = useRouter();
  const pathname = usePathname();

  const [user, setUser] = useState<AuthenticatedUser | null>(null);

  useEffect(() => {
    setUser(getStoredUser());
  }, []);

  const visibleLinks = links.filter(
    (link) => !link.permission || userHasPermission(user, link.permission),
  );

  function logout(): void {
    clearAuthentication();
    router.replace("/login");
  }
  function isActivePath(pathname: string, href: string): boolean {
    if (href === "#") {
      return false;
    }

    return pathname === href || pathname.startsWith(`${href}/`);
  }
  return (
    <div className="shell">
      <aside>
        <div className="brand">SportsOS</div>

        <nav>
          {visibleLinks.map((link) => (
            <Link
              className={isActivePath(pathname, link.href) ? "active" : ""}
              key={link.label}
              href={link.href}
            >
              {link.label}
            </Link>
          ))}
        </nav>
      </aside>

      <section className="workspace">
        <header>
          <span>
            {user
              ? `${user.firstName} ${user.lastName} · ${user.organizationName}`
              : "Sports Operations Center"}
          </span>

          <button className="secondary" onClick={logout}>
            Sign out
          </button>
        </header>

        <div className="content">{children}</div>
      </section>
    </div>
  );
}
