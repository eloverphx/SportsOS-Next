import mysql, { type Pool } from "mysql2/promise";
import { config } from "@sportsos/config";

export const pool: Pool = mysql.createPool({
  host: config.database.host,
  port: config.database.port,
  database: config.database.name,
  user: config.database.user,
  password: config.database.password,
  connectionLimit: 10,
});
