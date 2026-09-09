import type { RowDataPacket } from "mysql2/promise";
import { pool } from "../../infrastructure/database.js";
import { AuthorizationError } from "./authorization-error.js";
import type { AuthenticatedIdentity } from "./types.js";

export type AccountStatus = "PENDING" | "ACTIVE" | "SUSPENDED" | "REJECTED";

export async function assertActiveAccount(identity: AuthenticatedIdentity): Promise<void> {
  const [rows] = await pool.execute<RowDataPacket[]>(
    `SELECT account_status
     FROM users
     WHERE id = ?
       AND organization_id = ?
     LIMIT 1`,
    [identity.userId, identity.organizationId],
  );

  const account = rows[0];

  if (!account) {
    throw new AuthorizationError("Authenticated account no longer exists");
  }

  if (String(account.account_status) !== "ACTIVE") {
    throw new AuthorizationError("Authenticated account is not active");
  }
}
