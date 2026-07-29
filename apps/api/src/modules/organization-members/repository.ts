import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { normalizeRole, type Role } from "../auth/index.js";

interface OrganizationMemberRow extends RowDataPacket {
  id: number | string;
  organization_id: number | string;
  first_name: string;
  last_name: string;
  email: string;
  username: string;
  role: string;
}

export interface OrganizationMember {
  readonly id: number;
  readonly organizationId: number;
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly username: string;
  readonly role: Role;
}

function mapOrganizationMember(row: OrganizationMemberRow): OrganizationMember {
  return {
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    firstName: row.first_name,
    lastName: row.last_name,
    email: row.email,
    username: row.username,
    role: normalizeRole(row.role),
  };
}

export async function listOrganizationMembers(
  organizationId: number,
): Promise<OrganizationMember[]> {
  const [rows] = await pool.execute<OrganizationMemberRow[]>(
    `SELECT
       id,
       organization_id,
       first_name,
       last_name,
       email,
       username,
       role
     FROM users
     WHERE organization_id = ?
     ORDER BY last_name, first_name, id`,
    [organizationId],
  );

  return rows.map(mapOrganizationMember);
}

export async function findOrganizationMember(
  organizationId: number,
  userId: number,
): Promise<OrganizationMember | null> {
  const [rows] = await pool.execute<OrganizationMemberRow[]>(
    `SELECT
       id,
       organization_id,
       first_name,
       last_name,
       email,
       username,
       role
     FROM users
     WHERE id = ?
       AND organization_id = ?
     LIMIT 1`,
    [userId, organizationId],
  );

  return rows[0] ? mapOrganizationMember(rows[0]) : null;
}

export async function updateOrganizationMemberRole(
  organizationId: number,
  userId: number,
  role: Role,
): Promise<boolean> {
  const [result] = await pool.execute<ResultSetHeader>(
    `UPDATE users
     SET role = ?
     WHERE id = ?
       AND organization_id = ?`,
    [role, userId, organizationId],
  );

  return result.affectedRows > 0;
}
