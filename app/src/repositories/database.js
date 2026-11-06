import mysql from 'mysql2/promise';
export const pool = mysql.createPool({ host: process.env.DB_HOST || '127.0.0.1', port: Number(process.env.DB_PORT || 3306), user: process.env.DB_USER || 'root', password: process.env.DB_PASSWORD || '', database: process.env.DB_NAME || 'uagrm_asistencia', dateStrings: true, timezone: 'Z', connectionLimit: 10 });
export async function rows(sql, params = [], connection = pool) { const [result] = await connection.execute(sql, params); return result; }
export async function transaction(fn) {
 const connection = await pool.getConnection();
 try { await connection.beginTransaction(); const result = await fn(connection); await connection.commit(); return result; }
 catch (error) { await connection.rollback(); throw error; }
 finally { connection.release(); }
}
