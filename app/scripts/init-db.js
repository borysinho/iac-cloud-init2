import mysql from 'mysql2/promise';
import {readFile} from 'node:fs/promises';
import {hashPassword} from '../src/services/security.js';
const name=process.env.DB_NAME||'uagrm_asistencia';
if(!/^[a-zA-Z0-9_]+$/.test(name)) throw new Error('DB_NAME debe contener solo letras, números y guion bajo.');
const password=process.env.ADMIN_PASSWORD;
if(!password || password.length<12) throw new Error('Configura ADMIN_PASSWORD en .env con al menos 12 caracteres.');
const db=await mysql.createConnection({host:process.env.DB_HOST||'127.0.0.1',port:Number(process.env.DB_PORT||3306),user:process.env.DB_USER||'root',password:process.env.DB_PASSWORD||'',multipleStatements:true});
try {
 await db.query(`CREATE DATABASE IF NOT EXISTS \`${name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
 await db.query(`USE \`${name}\``);
 await db.query(await readFile(new URL('../database/schema.sql',import.meta.url),'utf8'));
 await db.execute('INSERT IGNORE INTO administrators(username,password_hash) VALUES(?,?)',[process.env.ADMIN_USER||'admin',hashPassword(password)]);
 console.log('Base de datos lista. El administrador existente conserva su contraseña.');
} finally {await db.end();}
