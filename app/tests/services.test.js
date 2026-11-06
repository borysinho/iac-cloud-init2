import test from 'node:test';
import assert from 'node:assert/strict';
import {createAttendanceService} from '../src/services/attendance.js';
const admin={role:'admin',id:1,name:'admin'},student={role:'student',id:10,moduleId:1,name:'Ana'};
function fixture() {
 let state={modules:[{id:1,name:'Actual',active:true}],students:[{id:10,moduleId:1,registration:'001',name:'Ana',email:'ana@example.com'}],dates:[{id:1,moduleId:1,class_date:'2026-10-12'},{id:2,moduleId:1,class_date:'2026-10-13'},{id:3,moduleId:1,class_date:'2026-10-14'}],records:[],logs:[]};
 const repo={
  activeModule:async()=>state.modules.find(m=>m.active),
  administrator:async()=>({id:1,username:'admin',password_hash:'hash'}),
  identifyStudents:async(m,i)=>state.students.filter(s=>s.moduleId===m && [s.registration,s.email].includes(i)),
  students:async(m,id)=>state.students.filter(s=>s.moduleId===m && (id===undefined||s.id===id)),
  dates:async m=>state.dates.filter(d=>d.moduleId===m),records:async(m,id)=>state.records.filter(r=>r.moduleId===m && (id===undefined||r.student_id===id)),
  student:async(m,id)=>state.students.find(s=>s.moduleId===m && s.id===id),date:async(m,day)=>state.dates.find(d=>d.moduleId===m && d.class_date===day),dateById:async(m,id)=>state.dates.find(d=>d.moduleId===m && d.id===id),
  attendance:async(s,d)=>state.records.find(r=>r.student_id===s && r.class_date_id===d),
  insertMark:async(m,s,d,t)=>state.records.push({moduleId:m,student_id:s,class_date_id:d,status:'Presente',marked_at:t}),
  correct:async(m,s,d,status)=>{let r=await repo.attendance(s,d);if(r)r.status=status;else state.records.push({moduleId:m,student_id:s,class_date_id:d,status,marked_at:null});},
  audit:async log=>state.logs.push(log),activities:async()=>state.logs,
  lockAdministrator:async()=>{},deactivateModules:async()=>state.modules.forEach(m=>m.active=false),
  createModule:async name=>{const id=state.modules.length+1;state.modules.push({id,name,active:true});return id;},
  insertStudent:async(m,s)=>state.students.push({...s,id:state.students.length+10,moduleId:m}),
  insertDate:async(m,d)=>state.dates.push({id:state.dates.length+1,moduleId:m,class_date:d.date}),
  transaction:async fn=>{const before=structuredClone(state);try{return await fn(repo);}catch(e){state=before;throw e;}}
 };
 const service=createAttendanceService({repository:repo,clock:()=>({day:'2026-10-13',timestamp:'2026-10-13 12:00:00'}),verifyPassword:(p)=>p==='valid',parseExcel:async()=>[],workbookBuffer:async(type,data)=>data});
 return {service,repo,state:()=>state};
}
test('RF-01/02: acceso por registro o correo activo y credenciales administrativas',async()=>{
 const {service}=fixture();for(const identifier of ['001','ana@example.com'])assert.equal((await service.login({role:'student',identifier})).id,10);
 await assert.rejects(service.login({role:'student',identifier:'otro'}),{code:'UNAUTHENTICATED'});
 await assert.rejects(service.login({role:'admin',identifier:'admin',password:'wrong'}),{code:'UNAUTHENTICATED'});
 assert.equal((await service.login({role:'admin',identifier:'admin',password:'valid'})).role,'admin');
});
test('RF-03/04/05: estados y habilitación se calculan en negocio; exportación coincide',async()=>{
 const {service}=fixture(),d=await service.dashboard(student);
 assert.deepEqual(d.records.map(r=>[r.status,r.canMark]),[['Falta',false],['Pendiente',true],['Pendiente',false]]);
 assert.deepEqual((await service.export(admin)).map(r=>r[3]),d.records.map(r=>r.status));
});
test('RN-03/04/07: marca única, hora real y auditoría en la misma transacción',async()=>{
 const {service,state}=fixture();await service.mark(student);await service.mark(student);
 assert.equal(state().records.length,1);assert.equal(state().records[0].marked_at,'2026-10-13 12:00:00');assert.equal(state().logs.length,1);
 assert.equal((await service.dashboard(student)).records[1].canMark,false);
});
test('RN-04: no se marca si hoy no está programado',async()=>{
 const {service,state}=fixture();state().dates=state().dates.filter(d=>d.id!==2);
 await assert.rejects(service.mark(student),{code:'INVALID'});assert.equal(state().records.length,0);
});
test('RF-07: corrección audita valores y conserva la hora original; estudiante no sobrescribe',async()=>{
 const {service,state}=fixture();await service.mark(student);await service.correct(admin,{studentId:10,dateId:2,status:'Falta'});
 assert.equal(state().records[0].marked_at,'2026-10-13 12:00:00');assert.equal(state().logs[1].previous,'Presente');assert.equal(state().logs[1].next,'Falta');
 assert.equal((await service.mark(student)).status,'Falta');assert.equal(state().logs.length,2);
 await service.correct(admin,{studentId:10,dateId:1,status:'Presente'});assert.equal(state().logs[2].previous,'Falta');
});
test('Roles se verifican en negocio aun invocando servicios sin HTTP',async()=>{
 const {service}=fixture();for(const operation of [()=>service.correct(student,{}),()=>service.activate(student,{},{}),()=>service.activities(student,{}),()=>service.export(student),()=>service.template(student,'dates'),()=>service.prepareImport(student,{})])await assert.rejects(operation(),{code:'FORBIDDEN'});
 await assert.rejects(service.mark(admin),{code:'FORBIDDEN'});await assert.rejects(service.dashboard(null),{code:'UNAUTHENTICATED'});
});
test('RF-13/15: activación confirmada conserva historial e inicia sin marcas',async()=>{
 const {service,state}=fixture();await service.mark(student);
 const draft={students:[{registration:'002',name:'Luis',email:'l@example.com'}],dates:[{date:'2026-10-14',start:'18:00',end:'21:00'}]};
 await assert.rejects(service.activate(admin,{name:'Nuevo',confirm:false},draft),{code:'INVALID'});assert.equal(state().modules[0].active,true);
 await service.activate(admin,{name:'Nuevo',confirm:true},draft);assert.equal(state().modules.filter(m=>m.active).length,1);assert.equal(state().modules.length,2);assert.equal(state().records.length,1);
 assert.equal((await service.dashboard(admin)).records[0].status,'Pendiente');
 await assert.rejects(service.dashboard(student),{code:'UNAUTHENTICATED'});await assert.rejects(service.mark(student),{code:'FORBIDDEN'});
});
test('Fallo de auditoría revierte marca y fallo de importación revierte activación',async()=>{
 const {service,repo,state}=fixture();repo.audit=async()=>{throw new Error('audit failed');};await assert.rejects(service.mark(student),/audit failed/);assert.equal(state().records.length,0);
 repo.insertDate=async()=>{throw new Error('insert failed');};await assert.rejects(service.activate(admin,{name:'Nuevo',confirm:true},{students:[{registration:'2'}],dates:[{date:'2026-10-14'}]}),/insert failed/);
 assert.equal(state().modules.length,1);assert.equal(state().modules[0].active,true);assert.equal(state().students.length,1);
});
