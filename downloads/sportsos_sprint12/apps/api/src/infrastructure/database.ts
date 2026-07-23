import mysql, { type Pool } from 'mysql2/promise';
import { env } from '../config/env.js';

export const pool: Pool = mysql.createPool({
  host: env.MYSQL_HOST,
  port: env.MYSQL_PORT,
  database: env.MYSQL_DATABASE,
  user: env.MYSQL_USER,
  password: env.MYSQL_PASSWORD,
  connectionLimit: 10
});
