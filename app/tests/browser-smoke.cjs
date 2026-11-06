// Prueba visual opcional. Requiere Playwright disponible en NODE_PATH.
const {chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'msedge'});
 try {
  const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://localhost:3000');await page.getByRole('heading',{name:'Ingresa a tu espacio'}).waitFor();
  await page.getByRole('button',{name:'Administrador',exact:true}).click();
  if(!await page.locator('#password').isVisible())throw new Error('Contraseña administrativa no visible');
  await page.getByRole('button',{name:'Estudiante',exact:true}).click();
  await page.screenshot({path:'tmp/login-desktop.png',fullPage:true});
  await page.setViewportSize({width:390,height:844});
  if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw new Error('Desbordamiento horizontal móvil');
  await page.screenshot({path:'tmp/login-mobile.png',fullPage:true});
  if(errors.length)throw new Error(errors.join('\n'));
  console.log('Login escritorio/móvil: correcto. Sin errores JS ni desbordamiento.');
 } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
