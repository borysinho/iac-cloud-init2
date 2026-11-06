import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import multer from 'multer';
import {randomBytes} from 'node:crypto';
export function createApp(service,{allowedOrigins=['http://localhost:8080','http://127.0.0.1:8080'],trustedProxies=[]}={}) {
 const app=express(),sessions=new Map();
 app.set('trust proxy',trustedProxies);
 app.disable('x-powered-by');app.use(helmet());app.use(express.json({limit:'100kb'}));
 // El backend solo sirve la API. CORS admite los clientes configurados.
 app.use('/api',(req,res,next)=>{
  res.set('Cache-Control','no-store');res.vary('Origin');
  const origin=req.headers.origin;
  if(origin && !allowedOrigins.includes(origin))return res.status(403).json({message:'Origen no permitido.'});
  if(origin){res.set('Access-Control-Allow-Origin',origin);res.set('Access-Control-Allow-Methods','GET, POST, PUT, OPTIONS');res.set('Access-Control-Allow-Headers','Content-Type, Authorization');}
  if(req.method==='OPTIONS')return res.sendStatus(204);
  next();
 });
 app.use('/api/login',rateLimit({windowMs:15*60*1000,limit:30,standardHeaders:true,legacyHeaders:false}));
 function pruneSessions(){for(const [key,s] of sessions)if(s.expires<=Date.now())sessions.delete(key);}
 const token=req=>req.headers.authorization?.match(/^Bearer ([A-Za-z0-9]+)$/)?.[1];
 function auth(req,res,next){const key=token(req),s=sessions.get(key);if(!s || s.expires<=Date.now()){if(key)sessions.delete(key);return res.status(401).json({message:'Inicia sesión para continuar.'});}req.user=s;next();}
 const wrap=fn=>(req,res,next)=>Promise.resolve(fn(req,res,next)).catch(next);
 app.post('/api/login',wrap(async(req,res)=>{const user=await service.login(req.body);pruneSessions();const key=randomBytes(32).toString('hex');sessions.set(key,{...user,expires:Date.now()+8*60*60*1000});res.json({...user,token:key});}));
 app.post('/api/logout',auth,(req,res)=>{sessions.delete(token(req));res.json({message:'Sesión cerrada.'});});
 app.get('/api/me',auth,(req,res)=>res.json({role:req.user.role,id:req.user.id,name:req.user.name,registration:req.user.registration}));
 app.get('/api/dashboard',auth,wrap(async(req,res)=>res.json(await service.dashboard(req.user))));
 app.post('/api/attendance',auth,wrap(async(req,res)=>res.json(await service.mark(req.user))));
 app.put('/api/attendance',auth,wrap(async(req,res)=>res.json(await service.correct(req.user,req.body))));
 app.get('/api/activities',auth,wrap(async(req,res)=>res.json(await service.activities(req.user,req.query))));
 const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:3*1024*1024,files:1}});
 app.post('/api/import/:type',auth,upload.single('file'),wrap(async(req,res)=>{
  const {data,result}=await service.prepareImport(req.user,{type:req.params.type,buffer:req.file?.buffer,filename:req.file?.originalname});
  req.user.draft ||= {};req.user.draft[req.params.type]=data;res.json(result);
 }));
 app.post('/api/modules/activate',auth,wrap(async(req,res)=>{const result=await service.activate(req.user,req.body,req.user.draft);delete req.user.draft;res.json(result);}));
 function excel(res,filename,buffer){res.set({'Content-Type':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','Content-Disposition':`attachment; filename="${filename}"`});res.send(Buffer.from(buffer));}
 app.get('/api/template/:type',auth,wrap(async(req,res)=>excel(res,`plantilla-${req.params.type}.xlsx`,await service.template(req.user,req.params.type))));
 app.get('/api/export',auth,wrap(async(req,res)=>excel(res,'asistencias.xlsx',await service.export(req.user))));
 app.use((error,req,res,next)=>{
  const status={INVALID:400,UNAUTHENTICATED:401,FORBIDDEN:403,NOT_FOUND:404,LIMIT_FILE_SIZE:400}[error.code]||error.status||500;
  console.error(error.code||error.message);res.status(status).json({message:status<500?(error.code==='LIMIT_FILE_SIZE'?'Archivo demasiado grande (máximo 3 MB).':error.message):'No se pudo completar la operación. Revisa la conexión a MySQL y la consola.',details:error.details});
 });
 // Caducidad diferida al acceder: no hay temporizadores que impidan cerrar las pruebas.
 return app;
}
