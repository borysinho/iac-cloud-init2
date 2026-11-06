import test from 'node:test';
import assert from 'node:assert/strict';
import {readdir,readFile} from 'node:fs/promises';
// Protege límites: negocio/presentación no pueden importar el adaptador MySQL.
test('Negocio no depende de presentación ni datos concretos',async()=>{
 for(const name of await readdir(new URL('../src/repositories/',import.meta.url))){if(!name.endsWith('.js'))continue;const source=await readFile(new URL('../src/repositories/'+name,import.meta.url),'utf8');assert.doesNotMatch(source,/from\s+['"][^'"]*(?:services|presentation|express)/,name);}
 for(const name of await readdir(new URL('../src/services/',import.meta.url))){if(!name.endsWith('.js'))continue;const source=await readFile(new URL('../src/services/'+name,import.meta.url),'utf8');assert.doesNotMatch(source,/from\s+['"][^'"]*(?:repositories|presentation|express|mysql2)/,name);assert.doesNotMatch(source,/\b(?:SELECT|INSERT INTO|UPDATE .* SET|DELETE FROM)\b/,name);}
});
test('Presentación no importa negocio concreto ni persistencia; usa contrato inyectado',async()=>{
 const source=await readFile(new URL('../src/presentation/app.js',import.meta.url),'utf8');assert.doesNotMatch(source,/from\s+['"][^'"]*(?:repositories|services|mysql2)/);assert.doesNotMatch(source,/\b(?:SELECT|INSERT INTO|DELETE FROM)\b/);
 const ui=await readFile(new URL('../public/app.js',import.meta.url),'utf8');assert.doesNotMatch(ui,/class_date\s*<\s*dashboard.today/);assert.match(ui,/current\?\.canMark/);
});
