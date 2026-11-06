// Adaptador MySQL: solo esta capa conoce tablas, SQL y conexiones.
import {rows, transaction} from './database.js';
function repository(connection) {
 const query=(sql,params=[])=>rows(sql,params,connection);
 return {
  activeModule:async(lock=false)=>(await query(`SELECT id,name FROM modules WHERE active=1${lock?' FOR UPDATE':''}`))[0]||null,
  administrator:async username=>(await query('SELECT * FROM administrators WHERE username=?',[username]))[0],
  identifyStudents:(moduleId,identifier)=>query('SELECT * FROM students WHERE module_id=? AND (registration=? OR email=?)',[moduleId,identifier,identifier]),
  students:(moduleId,id)=>query(`SELECT id,registration,name,email FROM students WHERE module_id=?${id===undefined?'':' AND id=?'} ORDER BY name`,id===undefined?[moduleId]:[moduleId,id]),
  dates:moduleId=>query('SELECT id,class_date,start_time,end_time FROM class_dates WHERE module_id=? ORDER BY class_date',[moduleId]),
  records:(moduleId,id)=>query(`SELECT student_id,class_date_id,status,marked_at FROM attendances WHERE module_id=?${id===undefined?'':' AND student_id=?'}`,id===undefined?[moduleId]:[moduleId,id]),
  student:async(moduleId,id)=>(await query('SELECT * FROM students WHERE module_id=? AND id=?',[moduleId,id]))[0],
  date:async(moduleId,day)=>(await query('SELECT * FROM class_dates WHERE module_id=? AND class_date=?',[moduleId,day]))[0],
  dateById:async(moduleId,id)=>(await query('SELECT * FROM class_dates WHERE module_id=? AND id=?',[moduleId,id]))[0],
  attendance:async(studentId,dateId)=>(await query('SELECT * FROM attendances WHERE student_id=? AND class_date_id=?',[studentId,dateId]))[0],
  insertMark:(moduleId,studentId,dateId,timestamp)=>query("INSERT INTO attendances(module_id,student_id,class_date_id,status,marked_at,updated_at) VALUES(?,?,?,'Presente',?,?)",[moduleId,studentId,dateId,timestamp,timestamp]),
  correct:(moduleId,studentId,dateId,status,timestamp)=>query('INSERT INTO attendances(module_id,student_id,class_date_id,status,updated_at) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE status=VALUES(status),updated_at=VALUES(updated_at)',[moduleId,studentId,dateId,status,timestamp]),
  audit:({moduleId,actor,action,studentId=null,affected=null,previous=null,next=null,timestamp})=>query('INSERT INTO activities(module_id,actor,action,student_id,affected,previous_value,new_value,created_at) VALUES(?,?,?,?,?,?,?,?)',[moduleId,actor,action,studentId,affected,previous,next,timestamp]),
  activities:(moduleId,{student,date})=>{
   const params=[moduleId]; let where='a.module_id=?';
   if(student){where+=' AND a.student_id=?';params.push(student);}
   if(date){where+=' AND DATE(a.created_at)=?';params.push(date);}
   return query(`SELECT a.*,s.name AS student_name FROM activities a LEFT JOIN students s ON s.id=a.student_id WHERE ${where} ORDER BY a.id DESC LIMIT 500`,params);
  },
  lockAdministrator:id=>query('SELECT id FROM administrators WHERE id=? FOR UPDATE',[id]),
  deactivateModules:()=>query('UPDATE modules SET active=0 WHERE active=1'),
  createModule:async name=>(await query('INSERT INTO modules(name,active) VALUES(?,1)',[name])).insertId,
  insertStudent:(id,s)=>query('INSERT INTO students(module_id,registration,name,email) VALUES(?,?,?,?)',[id,s.registration,s.name,s.email]),
  insertDate:(id,d)=>query('INSERT INTO class_dates(module_id,class_date,start_time,end_time) VALUES(?,?,?,?)',[id,d.date,d.start,d.end])
 };
}
export const mysqlRepository={...repository(),transaction:fn=>transaction(c=>fn(repository(c)))};
