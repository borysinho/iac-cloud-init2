import {institutionalNow, attendanceState, assertMarkable} from './rules.js';
// Contratos inyectados: repositorio, reloj, contraseña y Excel. Sin Express ni MySQL.
export function createAttendanceService({repository, clock=institutionalNow, verifyPassword, parseExcel, workbookBuffer}) {
 const fail=(message,code='INVALID')=>{throw Object.assign(new Error(message),{code});};
 function authorize(user,role) {
  if(!user) fail('Inicia sesión para continuar.','UNAUTHENTICATED');
  if(!['admin','student'].includes(user.role) || (role && user.role!==role)) fail(role==='admin'?'Acceso exclusivo del administrador.':'Acceso exclusivo de estudiantes.','FORBIDDEN');
 }
 const log=(r,moduleId,actor,action,studentId=null,affected=null,previous=null,next=null)=>r.audit({moduleId,actor,action,studentId,affected,previous,next,timestamp:clock().timestamp});
 async function dashboard(user) {
  authorize(user); const module=await repository.activeModule(),now=clock();
  if(!module)return {module:null,today:now.day,dates:[],students:[],records:[]};
  if(user.role==='student' && user.moduleId!==module.id)fail('Se activó otro módulo. Vuelve a ingresar.','UNAUTHENTICATED');
  const id=user.role==='student'?user.id:undefined;
  const dates=await repository.dates(module.id),students=await repository.students(module.id,id),stored=await repository.records(module.id,id);
  const byAttendance=new Map(stored.map(r=>[`${r.student_id}:${r.class_date_id}`,r]));
  const records=students.flatMap(s=>dates.map(d=>{
   const record=byAttendance.get(`${s.id}:${d.id}`);
   return {student_id:s.id,class_date_id:d.id,status:attendanceState(record,d.class_date,now.day),marked_at:record?.marked_at||null,canMark:user.role==='student' && d.class_date===now.day && !record};
  }));
  return {module,today:now.day,dates,students,records};
 }
 return {
  dashboard,
  async login({role,identifier,password}) {
   if(typeof identifier!=='string' || identifier.length>200)fail('Ingresa tu identificador.');
   let user;
   if(role==='admin') {const a=await repository.administrator(identifier.trim());if(a && typeof password==='string' && password.length<=200 && verifyPassword(password,a.password_hash))user={role,id:a.id,name:a.username};}
   else if(role==='student') {const m=await repository.activeModule();if(m){const matches=await repository.identifyStudents(m.id,identifier.trim());if(matches.length===1){const s=matches[0];user={role,id:s.id,name:s.name,registration:s.registration,moduleId:m.id};}}}
   if(!user)fail('No se pudo ingresar. Revisa tus datos y tu inscripción al módulo activo.','UNAUTHENTICATED');return user;
  },
  async mark(user) {
   authorize(user,'student');return repository.transaction(async r=>{
    const module=await r.activeModule(true);if(!module)fail('No hay módulo activo.');
    const student=await r.student(module.id,user.id);if(!student || user.moduleId!==module.id)fail('Tu matrícula ya no pertenece al módulo activo. Vuelve a ingresar.','FORBIDDEN');
    const now=clock(),date=await r.date(module.id,now.day);assertMarkable(date?.class_date,now.day);
    const existing=await r.attendance(student.id,date.id);if(existing)return {message:'Ya existe un registro para hoy.',status:existing.status};
    await r.insertMark(module.id,student.id,date.id,now.timestamp);await log(r,module.id,student.registration,'Marca de asistencia',student.id,String(date.id),null,'Presente');
    return {message:'Tu asistencia se registró correctamente.',status:'Presente'};
   });
  },
  async correct(user,{studentId,dateId,status}) {
   authorize(user,'admin');if(!['Presente','Falta'].includes(status))fail('Estado inválido.');
   return repository.transaction(async r=>{
    const module=await r.activeModule(true);if(!module)fail('No hay módulo activo.');
    const student=await r.student(module.id,studentId),date=await r.dateById(module.id,dateId);if(!student || !date)fail('Estudiante o fecha inválidos.');
    const old=await r.attendance(studentId,dateId),previous=attendanceState(old,date.class_date,clock().day);
    await r.correct(module.id,studentId,dateId,status,clock().timestamp);await log(r,module.id,user.name,'Corrección administrativa',studentId,String(dateId),previous,status);
    return {message:'Asistencia actualizada. El cambio quedó auditado.'};
   });
  },
  async activities(user,filter) {authorize(user,'admin');const m=await repository.activeModule();return m?repository.activities(m.id,filter):[];},
  async prepareImport(user,{type,buffer,filename}) {
   authorize(user,'admin');if(!['students','dates'].includes(type) || !buffer || !filename?.toLowerCase().endsWith('.xlsx'))fail('Selecciona un archivo .xlsx válido.');
   const data=await parseExcel(buffer,type);return {data,result:{count:data.length,preview:data.slice(0,10),message:`Archivo validado: ${data.length} filas.`}};
  },
  async activate(user,{name,confirm},draft) {
   authorize(user,'admin');name=String(name||'').trim();if(confirm!==true || !name || name.length>150 || !draft?.students?.length || !draft?.dates?.length)fail('Importa ambos archivos, indica el nombre y confirma la activación.');
   return repository.transaction(async r=>{
    await r.lockAdministrator(user.id);await r.deactivateModules();const id=await r.createModule(name);
    for(const s of draft.students)await r.insertStudent(id,s);for(const d of draft.dates)await r.insertDate(id,d);
    await log(r,id,user.name,'Activación de módulo');return {message:'Nuevo módulo activado. Los datos anteriores se conservaron.'};
   });
  },
  async template(user,type) {authorize(user,'admin');if(!['students','dates'].includes(type))fail('Plantilla inexistente.','NOT_FOUND');return workbookBuffer(type,type==='students'?[['1001','María Pérez','maria@example.com']]:[[clock().day,'18:00','21:00']]);},
  async export(user) {
   authorize(user,'admin');const data=await dashboard(user);if(!data.module)fail('No hay módulo activo.');
   const byAttendance=new Map(data.records.map(r=>[`${r.student_id}:${r.class_date_id}`,r]));
   return workbookBuffer('report',data.students.flatMap(s=>data.dates.map(d=>{const r=byAttendance.get(`${s.id}:${d.id}`);return [s.registration,s.name,d.class_date,r.status,r.marked_at];})));
  }
 };
}
