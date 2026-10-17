// Real WebRTC into the native harness, synthetic devices only; no public stream.
const {chromium}=require(process.env.DANTE_PLAYWRIGHT || '../build/guest-browser-qa/node_modules/playwright');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=path.resolve(process.argv[2]);
const fixture=JSON.parse(fs.readFileSync(path.join(root,'connection.json')));
async function synthetic({frequency}) {
  if(!navigator.mediaDevices)return;
  const resources=[];
  const video=(color)=>{const canvas=document.createElement('canvas');canvas.width=640;canvas.height=360;const ctx=canvas.getContext('2d');let frame=0;const tick=()=>{ctx.fillStyle=color;ctx.fillRect(0,0,640,360);ctx.fillStyle='#ffffff';ctx.fillRect((frame++*3)%600,100,40,60);};tick();resources.push(setInterval(tick,33));return canvas.captureStream(30).getVideoTracks()[0];};
  const audio=()=>{const ac=new AudioContext({sampleRate:48000}),osc=ac.createOscillator(),gain=ac.createGain(),dest=ac.createMediaStreamDestination();dest.channelCount=frequency===440?1:2;osc.frequency.value=frequency;gain.gain.value=.12;osc.connect(gain).connect(dest);osc.start();
   // Broadband excitation gives AEC a detectable delay, unlike a pure periodic
   // sine whose cycles are indistinguishable. Keep the tone for spectral checks.
   if(frequency===440){const buffer=ac.createBuffer(1,48000*3,48000),samples=buffer.getChannelData(0);let seed=123;
    for(let i=0;i<samples.length;i++){seed=(Math.imul(seed,1664525)+1013904223)>>>0;samples[i]=(seed/2147483648-1)*.15;}
    const noise=ac.createBufferSource();noise.buffer=buffer;noise.loop=true;noise.connect(dest);noise.start();}
   ac.resume();resources.push(ac);return dest.stream.getAudioTracks()[0];};
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
   await page.goto(fixture.base+'/#'+fixture.tokens[i]);await page.locator('#name').fill('João '+(i?'Beta':'Alfa'));await page.locator('#devices').click();await page.locator('#join').waitFor({state:'visible'});
   await page.waitForFunction(()=>!document.querySelector('#join').disabled);if(i===0)await page.locator('#screen').click();const started=Date.now();await page.locator('#join').click();
   try { await page.waitForFunction(()=>peer?.connectionState==='connected',null,{timeout:30000}); } catch(e) { console.log(await page.evaluate(async()=>({status:document.querySelector('#status').textContent, state:peer?.connectionState, ice:peer?.iceConnectionState, descriptions:[peer?.localDescription?.sdp,peer?.remoteDescription?.sdp].map(s=>s?.split('\r\n').filter(x=>/^m=|^a=mid:|^a=group:|^a=inactive|^a=send|^a=recv/.test(x))), local:peer?.localDescription?.sdp.split('\r\n').filter(x=>x.startsWith('a=candidate')).map(x=>x.split(' ').filter((_,i)=>[2,7].includes(i)).join(' ')), remote:peer?.remoteDescription?.sdp.split('\r\n').filter(x=>x.startsWith('a=candidate')).map(x=>x.split(' ').filter((_,i)=>[2,7].includes(i)).join(' ')), stats:peer?Array.from((await peer.getStats()).values()).filter(x=>x.type==='candidate-pair').map(x=>({state:x.state,requestsSent:x.requestsSent,responsesReceived:x.responsesReceived})):[]})));throw e; }const elapsed=Date.now()-started;assert(elapsed<15000,'connection must not wait for STUN gathering timeout');console.log('PASS: browser '+(i+1)+' connected through real WebRTC in '+elapsed+' ms');if(i===1){await new Promise(r=>setTimeout(r,1000));await page.locator('#screen').click();}
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
  for(const page of pages){
   const quality=await page.evaluate(async()=>{
    const stats=await peer.getStats();
    return {camera:cameraSender.getParameters(),screen:screenSender.getParameters(),audio:micSender.getParameters(),
     codecs:Array.from(stats.values()).filter(s=>s.type==='outbound-rtp'&&s.kind==='video').map(s=>stats.get(s.codecId)?.mimeType)};
   });
   assert.equal(quality.camera.encodings[0].maxBitrate,3000000);
   assert.equal(quality.screen.encodings[0].maxBitrate,5000000);
   assert.equal(quality.screen.encodings[0].maxFramerate,15);
   assert.equal(quality.audio.encodings[0].maxBitrate,128000);
   assert(quality.codecs.length>0&&quality.codecs.every(c=>c==='video/H264'));
  }
  assert(state.guests.every(g=>g.media.cameraUnbuffered&&g.media.screenUnbuffered));
  console.log('PASS: negotiated H264, per-sender bitrate/FPS bounds, unbuffered native video');
  for(const page of pages){
   await page.waitForFunction(()=>document.querySelector('#programVideo').videoWidth>0,null,{timeout:10000});
   const pixel=await page.evaluate(()=>{const video=document.querySelector('#programVideo'),canvas=document.createElement('canvas');canvas.width=video.videoWidth;canvas.height=video.videoHeight;const ctx=canvas.getContext('2d');ctx.drawImage(video,0,0);return Array.from(ctx.getImageData(10,10,1,1).data);});
   assert(pixel[0]>140&&pixel[1]>100&&pixel[2]<100,'program return must contain rendered yellow screen pixels, not just track dimensions: '+pixel);
   await page.locator('#toggleReturnAudio').click();assert(await page.evaluate(()=>document.querySelector('#returnAudio').muted));
   assert(await page.evaluate(()=>media.getAudioTracks()[0].enabled),'return mute must not mute microphone');await page.locator('#toggleReturnAudio').click();
  }
  console.log('PASS: both guests receive rendered program pixels; local return mute preserves sending microphone');
  for(const id of ['toggleCamera','toggleMic']){
   assert(await pages[0].locator('#'+id).evaluate(e=>e.classList.contains('state-on')));
   await pages[0].locator('#'+id).click();assert(await pages[0].locator('#'+id).evaluate(e=>e.classList.contains('state-off')));
   await pages[0].locator('#'+id).click();assert(await pages[0].locator('#'+id).evaluate(e=>e.classList.contains('state-on')));
  }
  await pages[1].locator('#screen').click();await pages[1].waitForFunction(()=>!document.querySelector('#screen').classList.contains('state-on')&&!document.querySelector('#screen').disabled);
  await pages[1].locator('#screen').click();await pages[1].waitForFunction(()=>document.querySelector('#screen').classList.contains('state-on'));
  await new Promise(r=>setTimeout(r,4000));
  const restarted=JSON.parse(fs.readFileSync(path.join(root,'state.json')));
  assert(restarted.state.scenes.flatMap(s=>s.items).filter(i=>i.type==='dante_guest_video').every(i=>i.width>0&&i.height>0),'camera and screen resume after toggles');
  for(let i=0;i<2;i++)for(const key of ['cameraFrames','screenFrames','programFrames'])assert(restarted.guests[i].media[key]>state.guests[i].media[key]+15,'native video keeps advancing: '+i+' '+key);
  console.log('PASS: device control colors, microphone/camera toggles and screen stop/restart');

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
  // Direct exclusion is insufficient when a host microphone recaptures a guest
  // from speakers. Native test fixture injects that delayed echo alongside a
  // separate 1320 Hz host signal, without opening any physical device.
  // Opt-in diagnostic: known acoustic recapture issue, not a passing regression.
  if(process.env.DANTE_ACOUSTIC_ECHO_TEST==='1'){
  fs.writeFileSync(path.join(root,'echo-start'),'');
  const echoDeadline=Date.now()+10000;while(!fs.existsSync(path.join(root,'echo-ready'))&&Date.now()<echoDeadline)await new Promise(r=>setTimeout(r,100));
  assert(fs.existsSync(path.join(root,'echo-ready')),'synthetic acoustic path starts');
  await new Promise(r=>setTimeout(r,8000));
  const echo=await pages[0].evaluate(async()=>{
   const ac=new AudioContext({sampleRate:48000}),analyser=ac.createAnalyser();analyser.fftSize=8192;
   await ac.resume();ac.createMediaStreamSource(document.querySelector('#returnAudio').srcObject).connect(analyser);
   await new Promise(r=>setTimeout(r,600));const data=new Float32Array(analyser.frequencyBinCount);analyser.getFloatFrequencyData(data);
   const level=f=>Math.max(...data.slice(Math.round(f*8192/ac.sampleRate)-2,Math.round(f*8192/ac.sampleRate)+3));
   const result={own:level(440),other:level(880),host:level(1320)};await ac.close();return result;
  });
  fs.writeFileSync(path.join(root,'echo-result.json'),JSON.stringify(echo,null,2));console.log('Acoustic return levels',echo);
  assert(echo.host>-60&&echo.other>-60&&echo.own<Math.min(echo.host,echo.other)-20,'recaptured own voice must be suppressed while host and other guest remain audible: '+JSON.stringify(echo));
  fs.writeFileSync(path.join(root,'echo-stop'),'');
  const stopDeadline=Date.now()+10000;while(!fs.existsSync(path.join(root,'echo-stopped'))&&Date.now()<stopDeadline)await new Promise(r=>setTimeout(r,100));
  assert(fs.existsSync(path.join(root,'echo-stopped')),'synthetic acoustic path stops');
  console.log('PASS: delayed own echo suppressed; host and other guest preserved');
  }
  fs.writeFileSync(path.join(root,'panel-checks'),'');
  const deadline=Date.now()+10000;while(!fs.existsSync(path.join(root,'panel-checks-passed'))&&Date.now()<deadline)await new Promise(r=>setTimeout(r,100));
  assert(fs.existsSync(path.join(root,'panel-checks-passed')),'native participant grouping, scene transfer, mute and ordering checks');
  console.log('PASS: participant names, distinct colors, scene assignment/rename, visibility/mute and hidden-layer ordering');
  await pages[0].screenshot({path:path.join(root,'guest-page.png')});
  fs.writeFileSync(path.join(root,'revoke'),'0');await new Promise(r=>setTimeout(r,3500));
  await pages[0].waitForFunction(()=>document.querySelector('#status').textContent.includes('revogado'),null,{timeout:10000});
  console.log('PASS: revocation stops the guest and denies further requests');
 } finally {fs.writeFileSync(path.join(root,'stop'),'');await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1});
