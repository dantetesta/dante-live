// Isolated browser regression: synthetic devices, no host app, room or public network.
const {chromium}=require(process.env.DANTE_PLAYWRIGHT || '../build/guest-browser-qa/node_modules/playwright');
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const output=path.resolve(process.argv[2]||'build/guest-onboarding-qa');fs.mkdirSync(output,{recursive:true});
const web=path.resolve(process.argv[3]||'Sources/GuestWeb');
const server=http.createServer((req,res)=>{const name={'/':'index.html','/guest.js':'guest.js','/guest.css':'guest.css'}[req.url.split('?')[0]];if(!name){res.writeHead(404).end();return;}res.writeHead(200,{'Content-Type':name.endsWith('.js')?'text/javascript':name.endsWith('.css')?'text/css':'text/html','Cache-Control':'no-store','Permissions-Policy':'camera=(self), microphone=(self), display-capture=(self)','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; media-src 'self' blob:; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"});res.end(fs.readFileSync(path.join(web,name)));});
async function synthetic(){
 if(!navigator.mediaDevices)return;
 window.fixture={requests:[],streams:[],error:null};
 const video=()=>{const canvas=document.createElement('canvas');canvas.width=640;canvas.height=360;const c=canvas.getContext('2d');c.fillStyle='#286875';c.fillRect(0,0,640,360);c.fillStyle='#c0e9e7';c.font='32px system-ui';c.fillText('Câmera de teste',170,190);return canvas.captureStream(1).getVideoTracks()[0];};
 const audio=()=>{const ac=new AudioContext(),destination=ac.createMediaStreamDestination(),osc=ac.createOscillator(),gain=ac.createGain();gain.gain.value=0;osc.connect(gain).connect(destination);osc.start();return destination.stream.getAudioTracks()[0];};
 Object.defineProperty(navigator.mediaDevices,'getUserMedia',{value:async options=>{
  fixture.requests.push(options);if(fixture.error)throw new DOMException('Falha simulada',fixture.error);
  for(const [kind,known] of [['video',['camera-1','camera-2']],['audio',['mic-1','mic-2']]])if(options[kind]?.deviceId?.exact&&!known.includes(options[kind].deviceId.exact))throw new DOMException('Identificador desconhecido','OverconstrainedError');
  const stream=new MediaStream([video(),audio()]);fixture.streams.push(stream);return stream;
 }});
 Object.defineProperty(navigator.mediaDevices,'enumerateDevices',{value:async()=>[{kind:'videoinput',deviceId:'camera-1',label:'Câmera integrada'},{kind:'videoinput',deviceId:'camera-2',label:'Câmera USB'},{kind:'audioinput',deviceId:'mic-1',label:'Microfone integrado'},{kind:'audioinput',deviceId:'mic-2',label:'Microfone USB'}]});
}
(async()=>{await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base=`http://127.0.0.1:${server.address().port}`;const browser=await chromium.launch({executablePath:process.env.DANTE_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--autoplay-policy=no-user-gesture-required','--use-fake-device-for-media-stream','--no-first-run']});const result={layouts:[],checks:[]};
 try{
  const context=await browser.newContext();await context.addInitScript(synthetic);const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.goto(base+'/#'+'a'.repeat(64));
  await page.locator('#devices').click();
  if(process.env.EXPECT_BASELINE_FAILURE){await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('Identificador desconhecido'));assert(await page.locator('#join').isDisabled());fs.writeFileSync(path.join(output,'baseline.json'),JSON.stringify({reproduced:true,request:await page.evaluate(()=>fixture.requests[0])},null,2));return;}
  await page.waitForFunction(()=>!document.querySelector('#join').disabled);assert.equal(await page.locator('#preview').evaluate(e=>e.srcObject?.getTracks().length),2);
  assert.equal(await page.evaluate(()=>fixture.requests[0].video.deviceId?.exact),undefined);assert.equal(await page.evaluate(()=>fixture.requests[0].audio.deviceId?.exact),undefined);result.checks.push('first preparation uses defaults, not placeholder labels');
  await page.locator('#camera').selectOption('camera-2');await page.waitForFunction(()=>!document.querySelector('#devices').disabled);assert.equal(await page.evaluate(()=>fixture.requests.at(-1).video.deviceId.exact),'camera-2');assert(await page.evaluate(()=>fixture.streams[0].getTracks().every(t=>t.readyState==='ended')));result.checks.push('device switch and previous stream release');
  await page.locator('#toggleCamera').click();assert.equal(await page.locator('#preview').evaluate(e=>e.srcObject.getVideoTracks()[0].enabled),false);await page.locator('#toggleCamera').click();
  await page.locator('#toggleMic').click();assert.equal(await page.locator('#preview').evaluate(e=>e.srcObject.getAudioTracks()[0].enabled),false);await page.locator('#toggleMic').click();result.checks.push('camera and microphone toggles');
  for(const [width,height] of [[1920,1080],[1366,768],[1280,720],[1024,768],[390,844],[360,640],[844,390]]){
   await page.setViewportSize({width,height});await page.waitForTimeout(60);const geometry=await page.evaluate(()=>({width:innerWidth,height:innerHeight,scrollWidth:document.documentElement.scrollWidth,scrollHeight:document.documentElement.scrollHeight,join:document.querySelector('#join').getBoundingClientRect().toJSON(),status:document.querySelector('#status').getBoundingClientRect().toJSON()}));
   assert(geometry.scrollWidth<=width,'horizontal overflow '+width);if(width>900){assert(geometry.scrollHeight<=height+1,'desktop needs scrolling '+JSON.stringify(geometry));assert(geometry.status.bottom<=height,'status below desktop viewport');}result.layouts.push(geometry);
   await page.screenshot({path:path.join(output,`guest-ready-${width}x${height}.png`),fullPage:true});
  }
  await page.setViewportSize({width:1366,height:768});await page.evaluate(()=>fixture.error='NotAllowedError');await page.locator('#devices').click();await page.waitForFunction(()=>document.querySelector('#status').textContent.includes('Acesso não autorizado'));assert(await page.locator('#preview').evaluate(e=>e.srcObject.getTracks().every(t=>t.readyState==='live')));result.checks.push('denied replacement keeps prior working media');
  await page.evaluate(()=>fixture.error=null);await page.locator('#devices').click();await page.waitForFunction(()=>!document.querySelector('#devices').disabled);await page.locator('#name').fill('Teste local');
  await page.evaluate(()=>window.dispatchEvent(new Event('pagehide')));assert(await page.evaluate(()=>fixture.streams.every(s=>s.getTracks().every(t=>t.readyState==='ended'))));result.checks.push('page exit releases devices');
  const fresh=await context.newPage();await fresh.goto(base+'/#'+'b'.repeat(64));await fresh.waitForTimeout(100);assert.equal(await fresh.evaluate(()=>fixture.requests.length),0);await fresh.setViewportSize({width:1366,height:768});await fresh.screenshot({path:path.join(output,'guest-initial-desktop.png'),fullPage:true});await fresh.setViewportSize({width:390,height:844});await fresh.screenshot({path:path.join(output,'guest-initial-mobile.png'),fullPage:true});result.checks.push('loading page lists devices without capturing');
  // A suspended audio meter must not keep the device controls locked.
  await fresh.evaluate(()=>AudioContext.prototype.resume=()=>new Promise(()=>{}));await fresh.locator('#devices').click();
  await fresh.waitForFunction(()=>!document.querySelector('#devices').disabled&&!document.querySelector('#join').disabled);
  result.checks.push('pending audio meter does not lock capture controls');

  // Exercise Chrome's own getUserMedia/enumerateDevices, without API replacements.
  // Fake devices are provided by Chrome itself; no physical camera/microphone opens.
  const nativeContext=await browser.newContext();await nativeContext.grantPermissions([],{origin:base});
  const native=await nativeContext.newPage();native.on('pageerror',e=>errors.push(e.message));await native.goto(base+'/#'+'c'.repeat(64));
  assert.equal(await native.locator('#preview').evaluate(e=>e.srcObject),null);
  await native.locator('#devices').click();await native.waitForFunction(()=>document.querySelector('#status').textContent.includes('Acesso não autorizado'));
  assert(await native.locator('#join').isDisabled());assert.equal(await native.locator('#devices').isDisabled(),false);
  result.checks.push('native browser permission denial remains recoverable');
  await nativeContext.grantPermissions(['camera','microphone'],{origin:base});await native.locator('#devices').click();
  await native.waitForFunction(()=>{const v=document.querySelector('#preview');return v.videoWidth>0&&v.currentTime>0&&!document.querySelector('#devices').disabled;});
  const tracks=await native.locator('#preview').evaluate(e=>e.srcObject.getTracks().map(t=>({kind:t.kind,state:t.readyState,label:!!t.label})));
  assert.deepEqual(tracks.map(t=>t.kind).sort(),['audio','video']);assert(tracks.every(t=>t.state==='live'&&t.label));
  assert(await native.locator('#camera option[data-device]').count()>0);assert(await native.locator('#microphone option[data-device]').count()>0);
  await native.waitForFunction(()=>document.querySelector('#level').value>0);
  await native.screenshot({path:path.join(output,'native-browser-ready.png'),fullPage:true});
  result.checks.push('native browser capture produces video frames, audio levels and device lists after retry');
  await native.evaluate(()=>window.dispatchEvent(new Event('pagehide')));
  assert(await native.locator('#preview').evaluate(e=>e.srcObject.getTracks().every(t=>t.readyState==='ended')));await nativeContext.close();
  assert.deepEqual(errors,[]);result.pass=true;fs.writeFileSync(path.join(output,'validation.json'),JSON.stringify(result,null,2));console.log(JSON.stringify({pass:true,checks:result.checks,layouts:result.layouts.length}));
 }finally{await browser.close();server.close();}
})().catch(e=>{server.close();console.error(e);process.exitCode=1;});
