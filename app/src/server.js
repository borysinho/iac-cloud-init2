// Punto de composición: conecta contratos con adaptadores concretos.
import {createApp} from './presentation/app.js';
import {createAttendanceService} from './services/attendance.js';
import {mysqlRepository} from './repositories/asistencia.js';
import {pool} from './repositories/database.js';
import {verifyPassword} from './services/security.js';
import {parseExcel,workbookBuffer} from './services/imports.js';
const service=createAttendanceService({repository:mysqlRepository,verifyPassword,parseExcel,workbookBuffer});
const allowedOrigins=(process.env.FRONTEND_ORIGINS||'http://localhost:8080,http://127.0.0.1:8080').split(',').map(s=>s.trim()).filter(Boolean);
const trustedProxies=(process.env.TRUSTED_PROXIES||'').split(',').map(s=>s.trim()).filter(Boolean);
const app=createApp(service,{allowedOrigins,trustedProxies});
const server=app.listen(Number(process.env.PORT||8090),process.env.BACKEND_HOST||'0.0.0.0',()=>console.log(`Backend API: puerto ${process.env.PORT||8090}`));
let stopping=false;
function shutdown(){if(stopping)return;stopping=true;server.close(async()=>{await pool.end();process.exit(0);});}
process.on('SIGINT',shutdown);
process.on('SIGTERM',shutdown);
