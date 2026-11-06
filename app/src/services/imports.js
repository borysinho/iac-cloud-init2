import ExcelJS from 'exceljs';
const clean = value => String(value ?? '').trim();
function cellValue(cell) { const v=cell.value; if(v && typeof v==='object' && 'formula' in v) throw new Error('No se admiten fórmulas. Pega los valores antes de importar.'); if(v && typeof v==='object' && 'text' in v) return v.text; return v; }
function dateValue(v) {
 if(v instanceof Date) return v.toISOString().slice(0,10);
 const s=clean(v); const m=s.match(/^(\d{2})\/(\d{2})\/(\d{4})$/); const result=m?`${m[3]}-${m[2]}-${m[1]}`:s;
 if(!/^\d{4}-\d{2}-\d{2}$/.test(result) || !Number.isFinite(Date.parse(result)) || new Date(result).toISOString().slice(0,10)!==result) throw new Error('Fecha inválida; usa DD/MM/AAAA o AAAA-MM-DD.'); return result;
}
function timeValue(v) {
 if(v instanceof Date) return v.toISOString().slice(11,16);
 if(typeof v==='number') { const minutes=Math.round((v%1)*1440); return `${String(Math.floor(minutes/60)).padStart(2,'0')}:${String(minutes%60).padStart(2,'0')}`; }
 const s=clean(v); if(!/^([01]\d|2[0-3]):[0-5]\d$/.test(s)) throw new Error('Hora inválida; usa HH:MM.'); return s;
}
export async function parseExcel(buffer,type) {
 const wb=new ExcelJS.Workbook(); await wb.xlsx.load(buffer); const sheet=wb.worksheets[0];
 if(!sheet || sheet.rowCount<2) throw Object.assign(new Error('El Excel está vacío.'),{code:'INVALID'});
 if(sheet.rowCount>5001) throw Object.assign(new Error('Máximo 5000 filas por archivo.'),{code:'INVALID'});
 const expected=type==='students'?['Número de registro','Nombre completo','Correo electrónico']:['Fecha','Hora inicio','Hora fin'];
 const normalize=s=>clean(s).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
 if(expected.some((h,i)=>normalize(sheet.getRow(1).getCell(i+1).text)!==normalize(h))) throw Object.assign(new Error(`Encabezados esperados: ${expected.join(', ')}.`),{code:'INVALID'});
 const data=[], errors=[], seen=new Set();
 sheet.eachRow((row,n)=> { if(n===1) return; try {
  const v=[1,2,3].map(i=>cellValue(row.getCell(i))); let item,key;
  if(type==='students') { item={registration:clean(v[0]),name:clean(v[1]),email:clean(v[2]).toLowerCase()}; key=item.registration;
   if(!key || !item.name || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(item.email)) throw new Error('Registro, nombre y correo válido son obligatorios.');
   if(key.length>50 || item.name.length>180 || item.email.length>200) throw new Error('Uno de los campos excede la longitud permitida.');
  } else { item={date:dateValue(v[0]),start:timeValue(v[1]),end:timeValue(v[2])}; key=item.date; if(item.end<=item.start) throw new Error('La hora final debe ser posterior a la inicial.'); }
  if(seen.has(key)) throw new Error('Registro o fecha duplicados.'); seen.add(key); data.push(item);
 } catch(e) {errors.push(`Fila ${n}: ${e.message}`);} });
 if(errors.length) throw Object.assign(new Error('Corrige el archivo antes de continuar.'),{code:'INVALID',details:errors});
 if(!data.length) throw Object.assign(new Error('No se encontraron filas de datos.'),{code:'INVALID'}); return data;
}
export async function workbookBuffer(type, data=[]) {
 const wb=new ExcelJS.Workbook(); const ws=wb.addWorksheet(type==='students'?'Estudiantes':type==='dates'?'Fechas':'Asistencias');
 const headers=type==='students'?['Número de registro','Nombre completo','Correo electrónico']:type==='dates'?['Fecha','Hora inicio','Hora fin']:['Registro','Estudiante','Fecha','Estado','Hora de marca'];
 ws.addRow(headers); data.forEach(row=>ws.addRow(row)); ws.getRow(1).font={bold:true,color:{argb:'FFFFFFFF'}}; ws.getRow(1).fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF123B70'}}; ws.columns.forEach(col=>col.width=28); return wb.xlsx.writeBuffer();
}
