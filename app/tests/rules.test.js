import test from 'node:test';
import assert from 'node:assert/strict';
import {institutionalNow,attendanceState,assertMarkable} from '../src/services/rules.js';
import {hashPassword,verifyPassword} from '../src/services/security.js';
test('La fecha de Bolivia no cambia a medianoche UTC',()=>{assert.equal(institutionalNow(new Date('2026-10-14T02:00:00Z')).day,'2026-10-13');});
test('Solo se permite marcar en la fecha programada',()=>{assert.doesNotThrow(()=>assertMarkable('2026-10-13','2026-10-13'));assert.throws(()=>assertMarkable('2026-10-12','2026-10-13'));assert.throws(()=>assertMarkable(undefined,'2026-10-13'));});
test('Ausencia de marca equivale a Falta solo en fechas pasadas',()=>{assert.equal(attendanceState(null,'2026-10-12','2026-10-13'),'Falta');assert.equal(attendanceState(null,'2026-10-13','2026-10-13'),'Pendiente');assert.equal(attendanceState(null,'2026-10-14','2026-10-13'),'Pendiente');assert.equal(attendanceState({status:'Presente'},'2026-10-12','2026-10-13'),'Presente');});
test('Contraseña administrativa con salt y verificación',()=>{const hash=hashPassword('UnaClaveDePrueba123');assert.ok(verifyPassword('UnaClaveDePrueba123',hash));assert.equal(verifyPassword('incorrecta',hash),false);assert.notEqual(hashPassword('UnaClaveDePrueba123'),hash);});
