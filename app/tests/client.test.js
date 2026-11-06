import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
test('Cliente usa backend configurado y token para login, consultas y Excel; limpia al salir',async()=>{
 const elements=new Map(),storage=new Map(),requests=[],downloads=[];
 const node=selector=>{if(!elements.has(selector))elements.set(selector,{value:'001',hidden:false,textContent:'',innerHTML:'',classList:{add(){},remove(){}},querySelectorAll:()=>[]});return elements.get(selector);};
 const document={querySelector:node,querySelectorAll:()=>[],body:{append(){}},createElement:()=>({click(){downloads.push(this.download);},remove(){}})};
 const context=vm.createContext({document,window:{APP_CONFIG:{apiBaseUrl:'http://192.168.1.30:3000/api'},addEventListener(){}},sessionStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},Headers,FormData,Intl,Date,URL,clearTimeout(){},setTimeout:fn=>{fn();},fetch:async(url,options)=>{
  requests.push({url,options});
  if(url.endsWith('/login'))return Response.json({id:10,role:'student',name:'Ana',token:'abc123'});
  if(url.endsWith('/dashboard'))return Response.json({module:null,dates:[],students:[],records:[]});
  if(url.endsWith('/export'))return new Response('xlsx');
  return Response.json({message:'ok'});
 }});
 vm.runInContext(await readFile(new URL('../public/app.js',import.meta.url),'utf8'),context);
 await node('#login-form').onsubmit({preventDefault(){},submitter:{disabled:false}});
 assert.equal(storage.get('attendanceToken'),'abc123');assert.equal(requests[0].url,'http://192.168.1.30:3000/api/login');assert.equal(requests[0].options.credentials,'omit');
 assert.equal(requests[1].options.headers.get('Authorization'),'Bearer abc123');
 await vm.runInContext("download('/export','asistencias.xlsx')",context);assert.deepEqual(downloads,['asistencias.xlsx']);assert.equal(requests[2].options.headers.get('Authorization'),'Bearer abc123');
 await node('#logout').onclick();assert.equal(storage.has('attendanceToken'),false);assert.equal(node('#login').hidden,false);
});
test('Cliente borra token ante sesión vencida y admite multipart sin forzar Content-Type',async()=>{
 const elements=new Map(),storage=new Map([['attendanceToken','expired']]),requests=[];
 const document={querySelector:s=>{if(!elements.has(s))elements.set(s,{hidden:false});return elements.get(s);},querySelectorAll:()=>[]};
 const context=vm.createContext({document,window:{APP_CONFIG:{apiBaseUrl:'http://backend:3000/api'},addEventListener(){}},sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},Headers,FormData,clearTimeout(){},setTimeout(){},fetch:async(url,options)=>{requests.push({url,options});return Response.json({message:'Sesión vencida'},{status:401});}});
 vm.runInContext(await readFile(new URL('../public/app.js',import.meta.url),'utf8'),context);
 await new Promise(resolve=>setImmediate(resolve));assert.equal(storage.has('attendanceToken'),false);
 await assert.rejects(vm.runInContext("request('/import/students',{method:'POST',body:new FormData()})",context),/Sesión vencida/);assert.equal(requests.at(-1).options.headers.has('Content-Type'),false);
});

test('Configuración estática permite usar la API del mismo origen sin Node en el cliente',async()=>{
 const context=vm.createContext({window:{}});
 vm.runInContext(await readFile(new URL('../public/config.js',import.meta.url),'utf8'),context);
 assert.equal(context.window.APP_CONFIG.apiBaseUrl,'/api');
 assert.equal(Object.isFrozen(context.window.APP_CONFIG),true);
 const html=await readFile(new URL('../public/index.html',import.meta.url),'utf8');
 assert.ok(html.indexOf('src="/config.js"')<html.indexOf('src="/app.js"'));
});
