import { pool } from '../infrastructure/database.js';

export async function audit(userId: string, action: string, details: object): Promise<void> {
  await pool.execute(
    'INSERT INTO audit_log (user_id, action, details) VALUES (?, ?, ?)',
    [userId, action, JSON.stringify(details)]
  );
}
