// Real WebRTC into the native harness, synthetic devices only; no public stream.
const {chromium}=require(process.env.DANTE_PLAYWRIGHT || '../build/guest-browser-qa/node_modules/playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(process.argv[2]);
const fixture=JSON.parse(fs.readFileSync(path.join(root,'connection.json')));
async function synthetic({frequency}) {
  if(!navigator.mediaDevices)return;
  const resources=[];
  const video=(color)=>{const canvas=document.createElement('canvas');canvas.width=640;canvas.height=360;const ctx=canvas.getContext('2d');let frame=0;const tick=()=>{ctx.fillStyle=color;ctx.fillRect(0,0,640,360);ctx.fillStyle='#ffffff';ctx.fillRect((frame++*3)%600,100,40,60);};tick();resources.push(setInterval(tick,33));return canvas.captureStream(30).getVideoTracks()[0];};
  const audio=()=>{const ac=new AudioContext({sampleRate:48000}),osc=ac.createOscillator(),gain=ac.createGain(),dest=ac.createMediaStreamDestination();osc.frequency.value=frequency;gain.gain.value=.12;osc.connect(gain).connect(dest);osc.start();ac.resume();resources.push(ac);return dest.stream.getAudioTracks()[0];};
  Object.defineProperty(navigator.mediaDevices,'getUserMedia',{value:async()=>new MediaStream([video('#18a6be'),audio()])});
  Object.defineProperty(navigator.mediaDevices,'getDisplayMedia',{value:async()=>new MediaStream([video('#e0a822')])});
  Object.defineProperty(navigator.mediaDevices,'enumerateDevices',{value:async()=>[{kind:'videoinput',deviceId:'synthetic-camera',label:'Câmera sintética QA'},{kind:'audioinput',deviceId:'synthetic-microphone',label:'Microfone sintético QA'}]});
}
function keepDiscoveryPending(){
 const Native=window.RTCPeerConnection;
 window.RTCPeerConnection=class extends Native {
  constructor(...args){super(...args);Object.defineProperty(this,'iceGatheringState',{get:()=> 'gathering'});}
 };
}
(async()=>{
 const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--autoplay-policy=no-user-gesture-required','--no-first-run']});
 try {
  const pages=[];
  for(let i=0;i<2;i++){
   const context=await browser.newContext({viewport:{width:1100,height:900}});await context.grantPermissions(["camera","microphone"]);await context.addInitScript(synthetic,{frequency:i?880:440});if(process.env.DANTE_PENDING_DISCOVERY)await context.addInitScript(keepDiscoveryPending);const page=await context.newPage();pages.push(page);
   page.on('pageerror',e=>console.error('PAGE ERROR',e.message));
   await page.goto(fixture.base+'/#'+fixture.tokens[i]);await page.locator('#name').fill('QA convidado '+(i+1));await page.locator('#devices').click();await page.locator('#join').waitFor({state:'visible'});
   await page.waitForFunction(()=>!document.querySelector('#join').disabled);await page.locator('#screen').click();const started=Date.now();await page.locator('#join').click();
   try { await page.waitForFunction(()=>peer?.connectionState==='connected',null,{timeout:30000}); } catch(e) { console.log(await page.evaluate(async()=>({status:document.querySelector('#status').textContent, state:peer?.connectionState, ice:peer?.iceConnectionState, descriptions:[peer?.localDescription?.sdp,peer?.remoteDescription?.sdp].map(s=>s?.split('\r\n').filter(x=>/^m=|^a=mid:|^a=group:|^a=inactive|^a=send|^a=recv/.test(x))), local:peer?.localDescription?.sdp.split('\r\n').filter(x=>x.startsWith('a=candidate')).map(x=>x.split(' ').filter((_,i)=>[2,7].includes(i)).join(' ')), remote:peer?.remoteDescription?.sdp.split('\r\n').filter(x=>x.startsWith('a=candidate')).map(x=>x.split(' ').filter((_,i)=>[2,7].includes(i)).join(' ')), stats:peer?Array.from((await peer.getStats()).values()).filter(x=>x.type==='candidate-pair').map(x=>({state:x.state,requestsSent:x.requestsSent,responsesReceived:x.responsesReceived})):[]})));throw e; }const elapsed=Date.now()-started;assert(elapsed<15000,'connection must not wait for STUN gathering timeout');console.log('PASS: browser '+(i+1)+' connected through real WebRTC in '+elapsed+' ms');
  }
  await new Promise(r=>setTimeout(r,6000));
  const state=JSON.parse(fs.readFileSync(path.join(root,'state.json')));
  fs.writeFileSync(path.join(root,'observed.json'),JSON.stringify(state,null,2));
  const items=state.state.scenes.flatMap(s=>s.items);
  const videos=items.filter(i=>i.type==='dante_guest_video');
  console.log('Guest diagnostics',state.guests);console.log('Video items',videos.map(i=>({name:i.name,width:i.width,height:i.height})));
  assert.equal(videos.length,4);assert.ok(videos.every(i=>i.width>0&&i.height>0),'camera and screen dimensions');
  const levels=Object.values(state.levels);assert.equal(levels.length,2);assert.ok(levels.every(l=>l.peak.some(p=>p>-40)),'both microphones arrive in OBS meters');
  console.log('PASS: four video sources and two real incoming audio meters');
  assert(state.guests.every(g=>g.media.candidateErrors===0&&g.media.remoteCandidateCount>0),'native peer accepted trickled candidates');
  const stale=await pages[0].evaluate(async()=>{try{await api('/ice',{negotiation:crypto.randomUUID(),candidates:[]});return 200;}catch(e){return e.status;}});
  assert.equal(stale,409);console.log('PASS: previous negotiation cannot inject ICE into current peer');
  for(let i=0;i<2;i++){
   const result=await pages[i].evaluate(async({own,other})=>{
    const ac=new AudioContext({sampleRate:48000});await ac.resume();const analyser=ac.createAnalyser();analyser.fftSize=8192;ac.createMediaStreamSource(document.querySelector('#returnAudio').srcObject).connect(analyser);await new Promise(r=>setTimeout(r,500));const data=new Float32Array(analyser.frequencyBinCount);analyser.getFloatFrequencyData(data);
    const level=f=>Math.max(...data.slice(Math.round(f*8192/ac.sampleRate)-2,Math.round(f*8192/ac.sampleRate)+3));const result={own:level(own),other:level(other)};await ac.close();return result;
   },{own:i?880:440,other:i?440:880});
   assert.ok(result.other>-60&&result.other>result.own+15,'mix-minus should return the other guest, not own voice: '+JSON.stringify(result));
  }
  console.log('PASS: two-way return audio excludes each guest’s own tone');
  await pages[0].screenshot({path:path.join(root,'guest-page.png')});
  fs.writeFileSync(path.join(root,'revoke'),'0');await new Promise(r=>setTimeout(r,3500));
  await pages[0].waitForFunction(()=>document.querySelector('#status').textContent.includes('revogado'),null,{timeout:10000});
  console.log('PASS: revocation stops the guest and denies further requests');
 } finally {await browser.close();fs.writeFileSync(path.join(root,'stop'),'');}
})().catch(e=>{console.error(e.message);process.exitCode=1});
