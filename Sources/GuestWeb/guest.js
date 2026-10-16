'use strict';
const $=id=>document.getElementById(id);
const storage={get:key=>{try{return sessionStorage.getItem(key);}catch{return null;}},set:(key,value)=>{try{sessionStorage.setItem(key,value);}catch{}}};
const token=location.hash.slice(1)||storage.get('dante-invite')||'';
if(/^[a-f0-9]{64}$/.test(token)){storage.set('dante-invite',token);history.replaceState(null,'',location.pathname);}
let client=storage.get('dante-client');if(!client){client=crypto.randomUUID();storage.set('dante-client',client);}
let media=null,screen=null,peer=null,cameraSender=null,micSender=null,screenSender=null,heartbeat=null,context=null,animation=null,joining=false,preparing=false,mediaGeneration=0;
function status(text){$('status').textContent=text;}
async function api(path,body={}){
 const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify({client,...body}),signal:AbortSignal.timeout(22000)});
 let data={};try{data=await response.json();}catch{}
 if(!response.ok){const error=new Error(data.error||'Não foi possível falar com o estúdio. Confira a conexão.');error.status=response.status;throw error;}return data;
}
function failure(error){
 const messages={NotAllowedError:'Acesso não autorizado. Use o ícone ao lado do endereço para permitir câmera e microfone e clique em Ativar novamente.',NotFoundError:'Conecte uma câmera e um microfone e tente novamente.',NotReadableError:'A câmera ou o microfone está ocupado. Feche o aplicativo que está usando o dispositivo e tente novamente.',OverconstrainedError:'O dispositivo escolhido não está disponível. Selecione a opção padrão ou conecte-o novamente.',SecurityError:'O navegador bloqueou os dispositivos. Abra o convite em uma conexão HTTPS.'};
 status(messages[error.name]||error.message||'Não foi possível concluir. Tente novamente.');
}
async function listDevices(){
 const devices=await navigator.mediaDevices.enumerateDevices();
 for(const [id,kind,track] of [['camera','videoinput',media?.getVideoTracks()[0]],['microphone','audioinput',media?.getAudioTracks()[0]]]){
  const select=$(id),selected=track?.getSettings().deviceId||select.value;
  select.replaceChildren();const fallback=document.createElement('option');fallback.value='';fallback.textContent=id==='camera'?'Câmera padrão':'Microfone padrão';select.append(fallback);
  devices.filter(d=>d.kind===kind&&d.deviceId).forEach((d,i)=>{const option=document.createElement('option');option.value=d.deviceId;option.dataset.device='true';option.textContent=d.label||`${id==='camera'?'Câmera':'Microfone'} ${i+1}`;select.append(option);});
  select.value=[...select.options].some(option=>option.value===selected)?selected:'';select.disabled=preparing;
 }
}
function selectedDevice(id){const option=$(id).selectedOptions[0];return option?.dataset.device==='true'&&option.value?{exact:option.value}:undefined;}
async function prepare(){
 if(preparing)return;
 preparing=true;const generation=++mediaGeneration;let next=null;let previousCamera=null,previousMic=null;
 $('devices').disabled=true;$('camera').disabled=true;$('microphone').disabled=true;
 status('Permita câmera e microfone no aviso do navegador. A prévia será exibida aqui.');
 try{
  next=await navigator.mediaDevices.getUserMedia({video:{deviceId:selectedDevice('camera'),width:{ideal:1280,max:1920},height:{ideal:720,max:1080},frameRate:{ideal:30,max:30}},audio:{deviceId:selectedDevice('microphone'),echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
  if(generation!==mediaGeneration){next.getTracks().forEach(t=>t.stop());return;}
  if(peer){previousCamera=cameraSender.track;previousMic=micSender.track;await cameraSender.replaceTrack(next.getVideoTracks()[0]);await micSender.replaceTrack(next.getAudioTracks()[0]);}
  if(generation!==mediaGeneration){next.getTracks().forEach(t=>t.stop());return;}
  media?.getTracks().forEach(t=>t.stop());media=next;next=null;$('preview').srcObject=media;$('previewEmpty').hidden=true;
  $('preview').play().catch(()=>{});
  $('join').disabled=false;$('toggleCamera').disabled=false;$('toggleMic').disabled=false;$('toggleCamera').textContent='Desligar câmera';$('toggleMic').textContent='Silenciar microfone';
  $('devices').textContent='Atualizar dispositivos';$('devices').classList.add('secondary');
  for(const track of media.getTracks())track.onended=()=>{if(media?.getTracks().includes(track)){status('Um dispositivo foi desconectado. Conecte-o novamente e clique em Atualizar dispositivos.');$('join').disabled=true;}};
  // Device labels and a level meter enhance the preview; their failure must not
  // discard an otherwise working camera/microphone stream.
  await listDevices().catch(()=>{});
  // Some browsers leave AudioContext.resume pending until another user gesture.
  // This optional meter must not lock device selection or prevent retrying capture.
  void meter(generation).catch(()=>{});
  if(generation===mediaGeneration)status(peer?'Dispositivos atualizados.':'Tudo pronto. Informe seu nome e entre no estúdio.');
 }catch(e){
  if(next){if(peer){if(previousCamera)await cameraSender?.replaceTrack(previousCamera).catch(()=>{});if(previousMic)await micSender?.replaceTrack(previousMic).catch(()=>{});}next.getTracks().forEach(t=>t.stop());}
  if(generation===mediaGeneration)failure(e);
 }finally{if(generation===mediaGeneration){preparing=false;$('devices').disabled=false;$('camera').disabled=false;$('microphone').disabled=false;}}
}
async function meter(generation){
 if(animation)cancelAnimationFrame(animation);animation=null;const previous=context;context=null;if(previous)await previous.close();
 if(generation!==mediaGeneration||!media?.getAudioTracks().length)return;
 const nextContext=new AudioContext();context=nextContext;await nextContext.resume();
 if(generation!==mediaGeneration){if(context===nextContext)context=null;await nextContext.close();return;}
 const analyser=nextContext.createAnalyser();analyser.fftSize=512;nextContext.createMediaStreamSource(media).connect(analyser);const samples=new Float32Array(512);
 const draw=()=>{analyser.getFloatTimeDomainData(samples);let sum=0;for(const x of samples)sum+=x*x;$('level').value=Math.min(1,Math.sqrt(sum/samples.length)*4);animation=requestAnimationFrame(draw);};draw();
}
async function shareScreen(){
 try{
  if(screen){screen.getTracks().forEach(t=>t.stop());screen=null;await screenSender?.replaceTrack(null);$('screenPreview').hidden=true;$('screen').textContent='Compartilhar uma tela…';return;}
  screen=await navigator.mediaDevices.getDisplayMedia({video:{width:{max:1920},height:{max:1080},frameRate:{max:30}},audio:false});
  const track=screen.getVideoTracks()[0];await screenSender?.replaceTrack(track);$('screenPreview').srcObject=screen;$('screenPreview').hidden=false;$('screen').textContent='Parar compartilhamento';
  track.onended=()=>{if(screen){screen=null;screenSender?.replaceTrack(null);$('screenPreview').hidden=true;$('screen').textContent='Compartilhar uma tela…';}};
 }catch(e){if(e.name!=='NotAllowedError')failure(e);}
}
function gathered(pc){return new Promise((resolve,reject)=>{
 if(pc.iceGatheringState==='complete'){resolve();return;}
 const timer=setTimeout(()=>{pc.removeEventListener('icegatheringstatechange',check);reject(new Error('A rede demorou para responder. Tente novamente; redes restritas podem precisar de TURN.'));},15000);
 function check(){if(pc.iceGatheringState==='complete'){clearTimeout(timer);pc.removeEventListener('icegatheringstatechange',check);resolve();}}
 pc.addEventListener('icegatheringstatechange',check);
});}
async function join(){
 if(joining)return;if(!$('name').value.trim()){status('Informe seu nome para entrar.');$('name').focus();return;}if(!media){status('Prepare os dispositivos primeiro.');return;}
 joining=true;$('join').disabled=true;status('Conectando ao estúdio…');
 try{
  peer?.close();if(heartbeat)clearInterval(heartbeat);
  const info=await api('/join',{name:$('name').value.trim()});
  const pc=new RTCPeerConnection({iceServers:info.iceServers});peer=pc;
  cameraSender=pc.addTransceiver(media.getVideoTracks()[0],{direction:'sendonly',streams:[media]}).sender;
  micSender=pc.addTransceiver(media.getAudioTracks()[0],{direction:'sendrecv',streams:[media]}).sender;
  screenSender=pc.addTransceiver(screen?.getVideoTracks()[0]||'video',{direction:'sendonly',streams:screen?[screen]:[]}).sender;
  pc.ontrack=event=>{if(event.track.kind==='audio'){$('returnAudio').srcObject=new MediaStream([event.track]);$('returnAudio').play().catch(()=>{$('listen').hidden=false;});}};
  pc.onconnectionstatechange=()=>{if(pc!==peer)return;const state=pc.connectionState;
   if(state==='connected'){status('Conectado. Aguarde o apresentador inserir você na cena.');$('join').hidden=true;$('leave').hidden=false;}
   if(state==='disconnected'||state==='failed'){status('A conexão caiu. Clique em Reconectar. Se continuar falhando, peça ao apresentador para configurar TURN.');$('join').textContent='Reconectar';$('join').hidden=false;$('join').disabled=false;}
  };
  let polling=false;
  heartbeat=setInterval(async()=>{if(polling)return;polling=true;try{const state=await api('/status',{camera:!!media?.getVideoTracks()[0]?.enabled,screen:!!screen});if(peer?.connectionState==='connected')status(state.admitted?'Você está disponível na cena do apresentador. Ele controla o que vai ao ar.':'Conectado. Aguarde o apresentador inserir você na cena.');}catch(e){if(e.status===403||e.status===410){await leave();clearInterval(heartbeat);}failure(e);pc.close();$('join').hidden=false;$('join').disabled=false;$('join').textContent='Reconectar';}finally{polling=false;}},2500);
  await pc.setLocalDescription(await pc.createOffer());await gathered(pc);const answer=await api('/offer',{sdp:pc.localDescription.sdp});await pc.setRemoteDescription(answer);
 }catch(e){peer?.close();peer=null;if(heartbeat)clearInterval(heartbeat);failure(e);$('join').disabled=false;$('join').hidden=false;$('join').textContent='Tentar novamente';}
 finally{joining=false;}
}
async function leave(){
 ++mediaGeneration;preparing=false;$('devices').disabled=false;$('devices').textContent='Ativar câmera e microfone';$('devices').classList.remove('secondary');$('previewEmpty').hidden=false;
 if(heartbeat)clearInterval(heartbeat);heartbeat=null;peer?.close();peer=null;cameraSender=micSender=screenSender=null;
 media?.getTracks().forEach(t=>t.stop());screen?.getTracks().forEach(t=>t.stop());media=screen=null;
 if(animation)cancelAnimationFrame(animation);if(context){await context.close();context=null;}$('level').value=0;
 $('preview').srcObject=null;$('screenPreview').srcObject=null;$('screenPreview').hidden=true;$('screen').textContent='Compartilhar tela';$('returnAudio').srcObject=null;$('listen').hidden=true;
 $('join').hidden=false;$('join').disabled=true;$('join').textContent='Entrar no estúdio';$('leave').hidden=true;$('toggleCamera').disabled=true;$('toggleMic').disabled=true;
 api('/leave').catch(()=>{});status('Você saiu. Câmera e microfone foram desligados.');
}
$('devices').onclick=prepare;$('camera').onchange=prepare;$('microphone').onchange=prepare;$('screen').onclick=shareScreen;$('join').onclick=join;$('leave').onclick=leave;
$('toggleCamera').onclick=()=>{const track=media?.getVideoTracks()[0];if(track){track.enabled=!track.enabled;$('toggleCamera').textContent=track.enabled?'Desligar câmera':'Ligar câmera';}};
$('toggleMic').onclick=()=>{const track=media?.getAudioTracks()[0];if(track){track.enabled=!track.enabled;$('toggleMic').textContent=track.enabled?'Silenciar microfone':'Ligar microfone';}};
$('listen').onclick=()=>{$('returnAudio').play().then(()=>{$('listen').hidden=true;}).catch(failure);};
if(!/^[a-f0-9]{64}$/.test(token)){status('Convite inválido. Abra o link completo recebido do apresentador.');$('devices').disabled=true;$('screen').disabled=true;}
else if(!navigator.mediaDevices?.getUserMedia||!window.RTCPeerConnection){status('Use uma versão atual do Chrome, Edge, Safari ou Firefox em uma conexão HTTPS.');$('devices').disabled=true;}

// Listing devices never requests access. Capture starts only after an explicit click.
if(/^[a-f0-9]{64}$/.test(token)&&navigator.mediaDevices?.getUserMedia&&window.RTCPeerConnection){void listDevices().catch(()=>{});navigator.mediaDevices.addEventListener?.('devicechange',()=>{if(!preparing)void listDevices().catch(()=>{});});}
window.addEventListener('pagehide',()=>{++mediaGeneration;media?.getTracks().forEach(t=>t.stop());screen?.getTracks().forEach(t=>t.stop());peer?.close();if(heartbeat)clearInterval(heartbeat);if(animation)cancelAnimationFrame(animation);void context?.close();});
if(!navigator.mediaDevices?.getDisplayMedia)$('screen').hidden=true;
