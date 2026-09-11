import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { normalizeRole } from "./roles.js";

export interface SignupOrganization {
  readonly id: number;
  readonly name: string;
}

export async function listSignupOrganizations(): Promise<SignupOrganization[]> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT id, name
     FROM organizations
     WHERE active = TRUE
     ORDER BY name, id`,
  );

  return rows.map((row) => ({
    id: Number(row.id),
    name: String(row.name),
  }));
}

export interface PendingSignupInput {
  readonly organizationId: number;
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly username: string;
  readonly passwordHash: string;
}

export async function organizationAcceptsSignup(organizationId: number): Promise<boolean> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT id
     FROM organizations
     WHERE id = ?
       AND active = TRUE
     LIMIT 1`,
    [organizationId],
  );

  return rows.length > 0;
}

export async function createPendingSignup(input: PendingSignupInput): Promise<number> {
  const [result] = await pool.execute<ResultSetHeader>(
    `INSERT INTO users (
       organization_id,
       first_name,
       last_name,
       email,
       username,
       password_hash,
       role,
       account_status
     )
     VALUES (?, ?, ?, ?, ?, ?, 'viewer', 'PENDING')`,
    [
      input.organizationId,
      input.firstName,
      input.lastName,
      input.email,
      input.username,
      input.passwordHash,
    ],
  );

  return Number(result.insertId);
}

interface PendingAccountRow extends RowDataPacket {
  id: number | string;
  organization_id: number | string;
  first_name: string;
  last_name: string;
  email: string;
  username: string;
  role: string;
  created_at: Date | string;
}

export interface PendingAccount {
  readonly id: number;
  readonly organizationId: number;
  readonly firstName: string;
  readonly lastName: string;
  readonly email: string;
  readonly username: string;
  readonly role: ReturnType<typeof normalizeRole>;
  readonly createdAt: string;
}

function iso(value: Date | string): string {
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

export async function listPendingAccounts(organizationId: number): Promise<PendingAccount[]> {
  const [rows] = await pool.execute<PendingAccountRow[]>(
    `SELECT
       id,
       organization_id,
       first_name,
       last_name,
       email,
       username,
       role,
       created_at
     FROM users
     WHERE organization_id = ?
       AND account_status = 'PENDING'
     ORDER BY created_at, id`,
    [organizationId],
  );

  return rows.map((row) => ({
    id: Number(row.id),
    organizationId: Number(row.organization_id),
    firstName: row.first_name,
    lastName: row.last_name,
    email: row.email,
    username: row.username,
    role: normalizeRole(row.role),
    createdAt: iso(row.created_at),
  }));
}

export async function approvePendingAccount(input: {
  organizationId: number;
  userId: number;
  approvedByUserId: number;
}): Promise<boolean> {
  const [result] = await pool.execute<ResultSetHeader>(
    `UPDATE users
     SET account_status = 'ACTIVE',
         approved_at = CURRENT_TIMESTAMP(3),
         approved_by_user_id = ?
     WHERE id = ?
       AND organization_id = ?
       AND account_status = 'PENDING'`,
    [input.approvedByUserId, input.userId, input.organizationId],
  );

  return result.affectedRows > 0;
}

export async function rejectPendingAccount(input: {
  organizationId: number;
  userId: number;
  rejectedByUserId: number;
}): Promise<boolean> {
  const [result] = await pool.execute<ResultSetHeader>(
    `UPDATE users
     SET account_status = 'REJECTED',
         approved_at = CURRENT_TIMESTAMP(3),
         approved_by_user_id = ?
     WHERE id = ?
       AND organization_id = ?
       AND account_status = 'PENDING'`,
    [input.rejectedByUserId, input.userId, input.organizationId],
  );

  return result.affectedRows > 0;
}
