"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import {
  PERMISSIONS,
  getStoredUser,
  userHasPermission,
  type AuthenticatedUser,
  type Role,
} from "../../lib/auth";
import { authenticatedFetch } from "../../lib/authenticated-api";

interface OrganizationMember {
  readonly id: number;
  readonly organizationId: number;
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly username: string;
  readonly role: Role;
}

interface MembersResponse {
  readonly members: OrganizationMember[];
}

interface UpdateMemberResponse {
  readonly success: boolean;
  readonly member: OrganizationMember;
}

interface RoleOption {
  readonly value: Role;
  readonly label: string;
}

interface CreateMemberForm {
  firstName: string;
  lastName: string;
  email: string;
  username: string;
  password: string;
  role: Role;
}

const STANDARD_ROLE_OPTIONS: readonly RoleOption[] = [
  {
    value: "organization_admin",
    label: "Organization administrator",
  },
  {
    value: "team_admin",
    label: "Team administrator",
  },
  {
    value: "coach",
    label: "Coach",
  },
  {
    value: "scorekeeper",
    label: "Scorekeeper",
  },
  {
    value: "broadcaster",
    label: "Broadcaster",
  },
  {
    value: "viewer",
    label: "Viewer",
  },
];

const SYSTEM_ROLE_OPTIONS: readonly RoleOption[] = [
  {
    value: "system_admin",
    label: "System administrator",
  },
  {
    value: "organization_owner",
    label: "Organization owner",
  },
  ...STANDARD_ROLE_OPTIONS,
];

const blankMemberForm: CreateMemberForm = {
  firstName: "",
  lastName: "",
  email: "",
  username: "",
  password: "",
  role: "viewer",
};

function roleLabel(role: Role): string {
  return SYSTEM_ROLE_OPTIONS.find((option) => option.value === role)?.label ?? role;
}

export default function UsersPage() {
  const [currentUser, setCurrentUser] = useState<AuthenticatedUser | null>(null);

  const [members, setMembers] = useState<OrganizationMember[]>([]);

  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  const [updatingUserId, setUpdatingUserId] = useState<number | null>(null);
  const [createForm, setCreateForm] = useState<CreateMemberForm>(blankMemberForm);

  const [creating, setCreating] = useState(false);
  const canManageMembers = userHasPermission(currentUser, PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE);

  const roleOptions =
    currentUser?.role === "system_admin" ? SYSTEM_ROLE_OPTIONS : STANDARD_ROLE_OPTIONS;

  const loadMembers = useCallback(async (user: AuthenticatedUser): Promise<void> => {
    const response = await authenticatedFetch<MembersResponse>(
      `/organizations/${user.organizationId}/members`,
    );

    setMembers(response.members);
  }, []);

  useEffect(() => {
    let active = true;

    async function load(): Promise<void> {
      const user = getStoredUser();

      if (!user) {
        if (active) {
          setError("Your user session could not be loaded.");
          setLoading(false);
        }

        return;
      }

      if (active) {
        setCurrentUser(user);
      }

      if (!userHasPermission(user, PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE)) {
        if (active) {
          setLoading(false);
        }

        return;
      }

      try {
        await loadMembers(user);
      } catch (caughtError) {
        if (active) {
          setError(
            caughtError instanceof Error
              ? caughtError.message
              : "Could not load organization members",
          );
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    void load();

    return () => {
      active = false;
    };
  }, [loadMembers]);

  const filteredMembers = useMemo(() => {
    const query = search.trim().toLowerCase();

    if (!query) {
      return members;
    }

    return members.filter((member) =>
      [member.firstName, member.lastName, member.email, member.username, roleLabel(member.role)]
        .join(" ")
        .toLowerCase()
        .includes(query),
    );
  }, [members, search]);

  async function updateRole(member: OrganizationMember, role: Role): Promise<void> {
    if (!currentUser || role === member.role) {
      return;
    }

    setUpdatingUserId(member.id);
    setError("");

    try {
      const response = await authenticatedFetch<UpdateMemberResponse>(
        `/organizations/${currentUser.organizationId}/members/${member.id}/role`,
        {
          method: "PATCH",
          body: JSON.stringify({
            role,
          }),
        },
      );

      setMembers((existingMembers) =>
        existingMembers.map((existingMember) =>
          existingMember.id === member.id ? response.member : existingMember,
        ),
      );
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : "Could not update the member role",
      );
    } finally {
      setUpdatingUserId(null);
    }
  }

  async function createMember(event: React.FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    if (!currentUser) {
      return;
    }

    setCreating(true);
    setError("");

    try {
      const response = await authenticatedFetch<UpdateMemberResponse>(
        `/organizations/${currentUser.organizationId}/members`,
        {
          method: "POST",
          body: JSON.stringify(createForm),
        },
      );

      setMembers((existing) =>
        [...existing, response.member].sort((left, right) =>
          `${left.lastName} ${left.firstName}`.localeCompare(
            `${right.lastName} ${right.firstName}`,
          ),
        ),
      );

      setCreateForm(blankMemberForm);
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Could not create the user");
    } finally {
      setCreating(false);
    }
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Users</h1>
            <p className="muted">
              Manage access for {currentUser?.organizationName ?? "your organization"}.
            </p>
          </div>

          {canManageMembers && (
            <input
              className="search"
              placeholder="Search users"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          )}
        </div>

        {!loading && !canManageMembers && (
          <section className="panel">
            <h2>Access restricted</h2>
            <p className="muted">
              Your account does not have permission to manage organization members.
            </p>
          </section>
        )}

        {!loading && canManageMembers && (
          <section className="panel">
            <h2>Add user</h2>

            <form className="formGrid" onSubmit={createMember}>
              <label>
                First name
                <input
                  required
                  value={createForm.firstName}
                  onChange={(event) =>
                    setCreateForm({
                      ...createForm,
                      firstName: event.target.value,
                    })
                  }
                />
              </label>

              <label>
                Last name
                <input
                  required
                  value={createForm.lastName}
                  onChange={(event) =>
                    setCreateForm({
                      ...createForm,
                      lastName: event.target.value,
                    })
                  }
                />
              </label>

              <label>
                Email
                <input
                  required
                  type="email"
                  value={createForm.email}
                  onChange={(event) =>
                    setCreateForm({
                      ...createForm,
                      email: event.target.value,
                    })
                  }
                />
              </label>

              <label>
                Username
                <input
                  required
                  minLength={3}
                  value={createForm.username}
                  onChange={(event) =>
                    setCreateForm({
                      ...createForm,
                      username: event.target.value,
                    })
                  }
                />
              </label>

              <label>
                Temporary password
                <input
                  required
                  type="password"
                  minLength={10}
                  autoComplete="new-password"
                  value={createForm.password}
                  onChange={(event) =>
                    setCreateForm({
                      ...createForm,
                      password: event.target.value,
                    })
                  }
                />
              </label>

              <label>
                Role
                <select
                  value={createForm.role}
                  onChange={(event) =>
                    setCreateForm({
                      ...createForm,
                      role: event.target.value as Role,
                    })
                  }
                >
                  {roleOptions.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </label>

              <div className="formActions">
                <button disabled={creating}>{creating ? "Creating…" : "Create user"}</button>
              </div>
            </form>
          </section>
        )}

        {loading && (
          <section className="panel">
            <p>Loading organization members…</p>
          </section>
        )}

        {error && <p className="error">{error}</p>}

        {!loading && canManageMembers && (
          <section className="panel">
            <h2>Organization members</h2>

            {filteredMembers.length === 0 ? (
              <p className="muted">No matching organization members were found.</p>
            ) : (
              <div className="entityGrid">
                {filteredMembers.map((member) => {
                  const isCurrentUser = member.id === currentUser?.id;

                  const ownerProtected =
                    member.role === "organization_owner" && currentUser?.role !== "system_admin";

                  const roleLocked =
                    isCurrentUser || ownerProtected || updatingUserId === member.id;

                  return (
                    <article className="entityCard" key={member.id}>
                      <div className="entityTop">
                        <div className="logo fallback">
                          {member.firstName.slice(0, 1).toUpperCase()}
                          {member.lastName.slice(0, 1).toUpperCase()}
                        </div>

                        <div>
                          <h3>
                            {member.firstName} {member.lastName}
                          </h3>

                          <p>@{member.username}</p>
                        </div>
                      </div>

                      <p>{member.email}</p>

                      <label>
                        Role
                        <select
                          value={member.role}
                          disabled={roleLocked}
                          onChange={(event) => void updateRole(member, event.target.value as Role)}
                        >
                          {!roleOptions.some((option) => option.value === member.role) && (
                            <option value={member.role}>{roleLabel(member.role)}</option>
                          )}

                          {roleOptions.map((option) => (
                            <option key={option.value} value={option.value}>
                              {option.label}
                            </option>
                          ))}
                        </select>
                      </label>

                      {isCurrentUser && <p className="muted">You cannot change your own role.</p>}

                      {ownerProtected && (
                        <p className="muted">
                          Only a system administrator can modify an organization owner.
                        </p>
                      )}

                      {updatingUserId === member.id && <p className="muted">Updating role…</p>}
                    </article>
                  );
                })}
              </div>
            )}
          </section>
        )}
      </AppShell>
    </AuthGate>
  );
}
