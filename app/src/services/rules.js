export function institutionalNow(date = new Date()) {
 const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: process.env.INSTITUTION_TIMEZONE || 'America/La_Paz', year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', second:'2-digit', hourCycle:'h23' }).formatToParts(date).map(p => [p.type,p.value]));
 const day = `${parts.year}-${parts.month}-${parts.day}`;
 return { day, timestamp: `${day} ${parts.hour}:${parts.minute}:${parts.second}` };
}
export function attendanceState(record, date, today) { return record?.status || (date < today ? 'Falta' : 'Pendiente'); }
export function assertMarkable(classDay, today) { if(classDay !== today) throw Object.assign(new Error('Solo puedes registrar asistencia durante la fecha de clase.'), {code:'INVALID'}); }
