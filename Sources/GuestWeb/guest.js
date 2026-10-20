'use strict';
const $=id=>document.getElementById(id);
const storage={get:key=>{try{return sessionStorage.getItem(key);}catch{return null;}},set:(key,value)=>{try{sessionStorage.setItem(key,value);}catch{}}};
const token=location.hash.slice(1)||storage.get('dante-invite')||'';
if(/^[a-f0-9]{64}$/.test(token)){storage.set('dante-invite',token);history.replaceState(null,'',location.pathname);}
let client=storage.get('dante-client');if(!client){client=crypto.randomUUID();storage.set('dante-client',client);}
let media=null,screen=null,peer=null,cameraSender=null,micSender=null,screenSender=null,heartbeat=null,context=null,animation=null,joining=false,preparing=false,mediaGeneration=0,screenGeneration=0,sharingBusy=false,connectionGeneration=0,connectionDeadline=null,reconnectTimer=null,reconnectAttempts=0;
let chatTimer=null,chatBusy=false,chatCursor=0,chatIdentity='',chatUnread=0,chatParticipants=[];
const renderedChatIDs=new Set();
// Bounds, not forced minimums: congestion control must still be able to recover
// on a slower link. Prefer retaining pixels and reducing FPS for legible screens.
const sendQuality={camera:{maxBitrate:3000000,maxFramerate:30,priority:'medium'},screen:{maxBitrate:5000000,maxFramerate:15,priority:'medium'},audio:{maxBitrate:128000,priority:'high'}};
function preferH264(transceiver){
 // H265 capability levels can differ between the browser's camera and screen
 // transceivers, colliding on a bundled payload type in the native receiver.
 const codecs=RTCRtpSender.getCapabilities?.('video')?.codecs.filter(c=>c.mimeType.toLowerCase()!=='video/h265');
 if(!codecs||!transceiver.setCodecPreferences)return;
 const h264=codecs.filter(c=>c.mimeType.toLowerCase()==='video/h264');
 if(h264.length)try{transceiver.setCodecPreferences([...h264,...codecs.filter(c=>!h264.includes(c))]);}catch{}
}
async function configureSender(sender,kind){
 if(!sender)return;
 const parameters=sender.getParameters();if(!parameters.encodings?.length)return;
 for(const encoding of parameters.encodings)Object.assign(encoding,sendQuality[kind]);
 if(kind!=='audio')parameters.degradationPreference='maintain-resolution';
 try{await sender.setParameters(parameters);}catch{
  // Some browsers don't expose priority/degradationPreference. Keep their
  // transport usable and retry only the standard bitrate/frame-rate bounds.
  const fallback=sender.getParameters();
  for(const encoding of fallback.encodings||[]){encoding.maxBitrate=sendQuality[kind].maxBitrate;if(kind!=='audio')encoding.maxFramerate=sendQuality[kind].maxFramerate;}
  try{await sender.setParameters(fallback);}catch{}
 }
}
function status(text){$('status').textContent=text;$('stageStatus').textContent=text;}
function stageMode(enabled){
 document.body.classList.toggle('stage-mode',enabled);
 if(!enabled){document.body.classList.remove('chat-open','settings-open');$('openChat').hidden=true;$('openSettings').hidden=true;$('closeSettings').hidden=true;$('stagePlaceholder').hidden=true;$('reconnectNow').hidden=true;$('headerSubtitle').textContent='Prepare seus dispositivos para entrar';}
 else {$('openChat').hidden=false;$('openSettings').hidden=false;$('stagePlaceholder').hidden=!$('programReturn').hidden;$('headerSubtitle').textContent=$('name').value.trim()+' · no palco';}
 $('openChat').setAttribute('aria-expanded',String(document.body.classList.contains('chat-open')));
 $('openSettings').setAttribute('aria-expanded',String(document.body.classList.contains('settings-open')));
}
function togglePanel(which){
 const opening=!document.body.classList.contains(which+'-open');
 document.body.classList.toggle('chat-open',which==='chat'&&opening);
 document.body.classList.toggle('settings-open',which==='settings'&&opening);
 $('chatPanel').hidden=!(which==='chat'&&opening);
 $('closeSettings').hidden=!(which==='settings'&&opening);
 $('openChat').setAttribute('aria-expanded',String(document.body.classList.contains('chat-open')));
 $('openSettings').setAttribute('aria-expanded',String(document.body.classList.contains('settings-open')));
 if(which==='chat'&&opening){chatUnread=0;updateChatBadge();$('chatText').focus();}
}
function updateChatBadge(){$('chatBadge').hidden=chatUnread===0;$('chatBadge').textContent=String(Math.min(chatUnread,99));}
function refreshRecipients(people){
 chatParticipants=people.filter(person=>person&&typeof person.id==='string'&&typeof person.name==='string'&&person.id!==chatIdentity);
 const selected=$('chatTo').value;$('chatTo').replaceChildren();
 for(const person of [{id:'all',name:'Todos · conversa geral'},...chatParticipants]){
  const option=document.createElement('option');option.value=person.id;option.textContent=person.id==='all'?person.name:`@${person.name} · privada`;$('chatTo').append(option);
 }
 $('chatTo').value=chatParticipants.some(person=>person.id===selected)?selected:'all';updateChatPrivacy();
}
function updateChatPrivacy(){
 const target=chatParticipants.find(person=>person.id===$('chatTo').value);
 $('chatPrivacy').textContent=target?`Privada: somente você e @${target.name} verão esta mensagem.`:'Todos os participantes verão esta mensagem.';
}
function renderChat(messages){
 const list=$('chatMessages');
 for(const message of messages){
  if(!Number.isInteger(message.id)||typeof message.text!=='string'||typeof message.senderName!=='string')continue;
  if(renderedChatIDs.has(message.id))continue;
  renderedChatIDs.add(message.id);
  list.querySelector('.chat-empty')?.remove();
  const row=document.createElement('div');row.className='chat-message';row.dataset.messageId=String(message.id);if(message.senderID===chatIdentity)row.classList.add('own');if(message.recipientID!=='all')row.classList.add('private');
  const meta=document.createElement('div');meta.className='chat-meta';
  const author=document.createElement('strong');author.textContent=message.senderName;meta.append(author);
  if(message.recipientID!=='all'){const target=document.createElement('em');target.textContent=` · privada para @${message.recipientName}`;meta.append(target);}
  const time=document.createElement('span');time.textContent=' · '+new Date(message.sentAt*1000).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'});meta.append(time);
  const body=document.createElement('p');body.textContent=message.text;row.append(meta,body);list.append(row);
  if(message.senderID!==chatIdentity&&!document.body.classList.contains('chat-open'))chatUnread++;
 }
 while(list.children.length>150){const oldest=list.firstElementChild;renderedChatIDs.delete(Number(oldest.dataset.messageId));oldest.remove();}
 list.scrollTop=list.scrollHeight;updateChatBadge();
}
function acceptChat(data){
 if(typeof data.chatIdentity==='string')chatIdentity=data.chatIdentity;
 if(Array.isArray(data.participants))refreshRecipients(data.participants);
 if(Array.isArray(data.chatMessages))renderChat(data.chatMessages);
 if(Number.isInteger(data.chatCursor))chatCursor=Math.max(chatCursor,data.chatCursor);
}
async function pollChat(){
 if(chatBusy||!peer||peer.connectionState!=='connected')return;
 chatBusy=true;
 try{acceptChat(await api('/status',{chatAfter:chatCursor}));$('chatError').textContent='';}
 catch(error){if(document.body.classList.contains('chat-open'))$('chatError').textContent=error.message;}
 finally{chatBusy=false;}
}
function mentionedRecipient(text){
 const lower=text.toLocaleLowerCase('pt-BR'),mentions=[];
 for(const person of chatParticipants){
  const marker='@'+person.name.toLocaleLowerCase('pt-BR');let offset=0;
  while((offset=lower.indexOf(marker,offset))!==-1){
   const next=lower[offset+marker.length];
   if((offset===0||/\s/.test(lower[offset-1]))&&(!next||/[\s.,:;!?]/.test(next)))mentions.push({id:person.id,offset,length:marker.length});
   offset+=marker.length;
  }
 }
 const longest=new Map();for(const match of mentions)if(!longest.has(match.offset)||longest.get(match.offset).length<match.length)longest.set(match.offset,match);
 const identities=new Set([...longest.values()].map(match=>match.id));
 if(identities.size===1)return [...identities][0];
 if(identities.size>1)throw new Error('Há mais de uma @menção. Escolha um destinatário privado na lista.');
 if(/(^|\s)@/.test(text))throw new Error('Participante mencionado indisponível. Escolha o destinatário privado na lista.');
 return 'all';
}
async function sendChat(event){
 event.preventDefault();const text=$('chatText').value.trim();if(!text)return;
 let recipient=$('chatTo').value;
 try{
  if(recipient==='all')recipient=mentionedRecipient(text);
  $('chatSend').disabled=true;
  const data=await api('/status',{chatText:text,chatTo:recipient,chatAfter:chatCursor});
  $('chatText').value='';$('chatError').textContent='';acceptChat(data);
 }catch(error){$('chatError').textContent=error.message||'Não foi possível enviar a mensagem.';}
 finally{$('chatSend').disabled=false;}
}
async function api(path,body={}){
 const response=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},body:JSON.stringify({client,...body}),signal:AbortSignal.timeout(22000)});
 let data={};try{data=await response.json();}catch{}
 if(!response.ok){const error=new Error(data.error||'Não foi possível falar com o estúdio. Confira a conexão.');error.status=response.status;throw error;}return data;
}
function failure(error){
 const messages={NotAllowedError:'Acesso não autorizado. Use o ícone ao lado do endereço para permitir câmera e microfone e clique em Ativar novamente.',NotFoundError:'Conecte uma câmera e um microfone e tente novamente.',NotReadableError:'A câmera ou o microfone está ocupado. Feche o aplicativo que está usando o dispositivo e tente novamente.',OverconstrainedError:'O dispositivo escolhido não está disponível. Selecione a opção padrão ou conecte-o novamente.',SecurityError:'O navegador bloqueou os dispositivos. Abra o convite em uma conexão HTTPS.'};
 status(messages[error.name]||error.message||'Não foi possível concluir. Tente novamente.');
}
function updateControls(){
 const camera=media?.getVideoTracks()[0],mic=media?.getAudioTracks()[0];
 for(const [id,track,on,off] of [['toggleCamera',camera,'Desligar câmera','Ligar câmera'],['toggleMic',mic,'Silenciar microfone','Ligar microfone']]){
  const enabled=!!track&&track.readyState==='live'&&track.enabled;
  $(id).classList.toggle('state-on',enabled);$(id).classList.toggle('state-off',!!track&&!enabled);
  $(id).setAttribute('aria-pressed',String(enabled));$(id).textContent=enabled?on:off;
 }
 const sharing=!!screen?.getVideoTracks().some(track=>track.readyState==='live');
 $('screen').classList.toggle('state-on',sharing);$('screen').setAttribute('aria-pressed',String(sharing));
 $('screen').textContent=sharing?'Parar compartilhamento':'Compartilhar tela';
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
  next=await navigator.mediaDevices.getUserMedia({video:{deviceId:selectedDevice('camera'),width:{ideal:1280,max:1920},height:{ideal:720,max:1080},frameRate:{ideal:30,max:30}},audio:{channelCount:{ideal:1,max:2},deviceId:selectedDevice('microphone'),echoCancellation:true,noiseSuppression:true,autoGainControl:true}});
  if(generation!==mediaGeneration){next.getTracks().forEach(t=>t.stop());return;}
  if(peer){previousCamera=cameraSender.track;previousMic=micSender.track;await cameraSender.replaceTrack(next.getVideoTracks()[0]);await micSender.replaceTrack(next.getAudioTracks()[0]);await configureSender(cameraSender,'camera');await configureSender(micSender,'audio');}
  if(generation!==mediaGeneration){next.getTracks().forEach(t=>t.stop());return;}
  media?.getTracks().forEach(t=>t.stop());media=next;next=null;updateControls();$('preview').srcObject=media;$('previewEmpty').hidden=true;
  $('preview').play().catch(()=>{});
  $('join').disabled=false;$('toggleCamera').disabled=false;$('toggleMic').disabled=false;$('toggleCamera').textContent='Desligar câmera';$('toggleMic').textContent='Silenciar microfone';
  $('devices').textContent='Atualizar dispositivos';$('devices').classList.add('secondary');
  for(const track of media.getTracks())track.onended=()=>{if(media?.getTracks().includes(track)){status('Um dispositivo foi desconectado. Conecte-o novamente e clique em Atualizar dispositivos.');$('join').disabled=true;updateControls();}};
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
 if(sharingBusy)return;sharingBusy=true;$('screen').disabled=true;const generation=screenGeneration;
 try{
  if(screen){const previous=screen;screen=null;previous.getTracks().forEach(t=>t.stop());$('screenPreview').srcObject=null;$('screenPreview').hidden=true;updateControls();await screenSender?.replaceTrack(null);return;}
  const next=await navigator.mediaDevices.getDisplayMedia({video:{width:{max:1920},height:{max:1080},frameRate:{ideal:15,max:15}},audio:false});
  if(generation!==screenGeneration){next.getTracks().forEach(t=>t.stop());return;}
  const track=next.getVideoTracks()[0];
  if('contentHint' in track)track.contentHint='detail';
  try{await screenSender?.replaceTrack(track);await configureSender(screenSender,'screen');}catch(error){next.getTracks().forEach(t=>t.stop());throw error;}
  if(generation!==screenGeneration){next.getTracks().forEach(t=>t.stop());return;}
  screen=next;$('screenPreview').srcObject=screen;$('screenPreview').hidden=false;updateControls();
  track.onended=()=>{if(screen===next){screen=null;void screenSender?.replaceTrack(null).catch(failure);$('screenPreview').srcObject=null;$('screenPreview').hidden=true;updateControls();}};
 }catch(e){if(e.name!=='NotAllowedError')failure(e);}
 finally{sharingBusy=false;$('screen').disabled=false;updateControls();}
}
function closeConnection(){
 const previous=peer;peer=null;
 if(chatTimer)clearInterval(chatTimer);chatTimer=null;
 $('nameActions').hidden=true;
 if(heartbeat)clearInterval(heartbeat);heartbeat=null;
 if(connectionDeadline)clearTimeout(connectionDeadline);connectionDeadline=null;
 if(reconnectTimer)clearTimeout(reconnectTimer);reconnectTimer=null;
 $('returnAudio').pause();$('returnAudio').srcObject=null;$('listen').hidden=true;
 $('programVideo').srcObject=null;$('programReturn').hidden=true;$('stagePlaceholder').hidden=!document.body.classList.contains('stage-mode');
 previous?.close();cameraSender=micSender=screenSender=null;
}
function scheduleReconnect(message,grace=1000){
 if(reconnectTimer||joining||!media||media.getTracks().some(track=>track.readyState!=='live'))return;
 const delay=Math.min(15000,grace*2**Math.min(reconnectAttempts++,4));
 status(message+' Tentaremos reconectar automaticamente.');
 $('join').textContent='Reconectar agora';$('join').hidden=false;$('join').disabled=false;
 $('reconnectNow').hidden=false;
 reconnectTimer=setTimeout(()=>{reconnectTimer=null;void join();},delay);
}
async function join(){
 if(joining)return;
 if(!$('name').value.trim()){status('Informe seu nome para entrar.');$('name').focus();return;}
 if(!media||media.getTracks().some(track=>track.readyState!=='live')){status('Ative câmera e microfone antes de entrar.');return;}
 const generation=++connectionGeneration;joining=true;closeConnection();stageMode(true);
 let retryableFailure=false;
 $('join').disabled=true;$('leave').hidden=false;status('Conectando ao estúdio…');
 try{
  const info=await api('/join',{name:$('name').value.trim()});
  if(generation!==connectionGeneration)return;
  if(!info.trickleICE)throw new Error('O apresentador precisa atualizar o Dante Live e gerar um novo convite.');
  const negotiation=crypto.randomUUID(),candidates=[];
  const pc=new RTCPeerConnection({iceServers:info.iceServers});peer=pc;
  pc.onicecandidate=event=>{if(event.candidate&&candidates.length<64)candidates.push(event.candidate.toJSON());};
  const cameraTransceiver=pc.addTransceiver(media.getVideoTracks()[0],{direction:'sendrecv',streams:[media],sendEncodings:[sendQuality.camera]});
  preferH264(cameraTransceiver);cameraSender=cameraTransceiver.sender;
  micSender=pc.addTransceiver(media.getAudioTracks()[0],{direction:'sendrecv',streams:[media],sendEncodings:[sendQuality.audio]}).sender;
  const screenTransceiver=pc.addTransceiver(screen?.getVideoTracks()[0]||'video',{direction:'sendonly',streams:screen?[screen]:[],sendEncodings:[sendQuality.screen]});
  preferH264(screenTransceiver);screenSender=screenTransceiver.sender;
  pc.ontrack=event=>{if(pc!==peer)return;if(event.track.kind==='video'){$('programVideo').srcObject=new MediaStream([event.track]);$('programReturn').hidden=false;$('stagePlaceholder').hidden=true;$('programVideo').play().catch(()=>{});}if(event.track.kind==='audio'){$('returnAudio').srcObject=new MediaStream([event.track]);$('returnAudio').play().catch(()=>{$('listen').hidden=false;});}};
  pc.onconnectionstatechange=()=>{if(pc!==peer)return;const state=pc.connectionState;
   if(state==='connected'){clearTimeout(connectionDeadline);connectionDeadline=null;if(reconnectTimer)clearTimeout(reconnectTimer);reconnectTimer=null;reconnectAttempts=0;status('Conectado. Aguarde o apresentador inserir você na cena.');$('join').hidden=true;$('reconnectNow').hidden=true;$('nameActions').hidden=false;if(!chatTimer){chatTimer=setInterval(()=>{void pollChat();},3000);void pollChat();}}
   if(state==='disconnected')scheduleReconnect('A conexão oscilou.',5000);
   if(state==='failed')scheduleReconnect('A conexão de áudio e vídeo caiu.');
  };
  // Send SDP immediately. Local/direct candidates remain usable while STUN is
  // slow or blocked; later candidates travel over the authenticated HTTPS API.
  await pc.setLocalDescription(await pc.createOffer());
  if(pc!==peer)return;
  const answer=await api('/offer',{sdp:pc.localDescription.sdp,negotiation});
  if(pc!==peer)return;await pc.setRemoteDescription(answer);
  if(pc!==peer)return;
  await configureSender(cameraSender,'camera');await configureSender(micSender,'audio');await configureSender(screenSender,'screen');
  if(pc!==peer)return;
  let polling=false,remoteCount=0,sentCount=0,lastPoll=0,failures=0;
  const exchange=async()=>{
   if(pc!==peer||polling||(pc.connectionState==='connected'&&Date.now()-lastPoll<2500))return;
   polling=true;lastPoll=Date.now();const sentThrough=candidates.length;
   try{
    const state=await api('/ice',{negotiation,candidates:candidates.slice(sentCount,sentThrough),camera:!!media?.getVideoTracks()[0]?.enabled,screen:!!screen,microphone:!!media?.getAudioTracks()[0]?.enabled});
    if(pc!==peer)return;failures=0;sentCount=sentThrough;
    for(const candidate of state.candidates.slice(remoteCount)){await pc.addIceCandidate(candidate);remoteCount++;if(pc!==peer)return;}
    if(pc.connectionState==='connected')status(state.admitted?'Você está disponível na cena do apresentador. Ele controla o que vai ao ar.':'Conectado. Aguarde o apresentador inserir você na cena.');
   }catch(error){
    if(pc!==peer)return;
    if([403,410].includes(error.status)){await leave();failure(error);return;}
    if(error.status===409){closeConnection();scheduleReconnect('A tentativa anterior terminou.');return;}
    if(++failures>=3)status('A comunicação com o estúdio está instável. Tentando novamente…');
   }finally{polling=false;}
  };
  heartbeat=setInterval(exchange,500);void exchange();
  if(pc.connectionState!=='connected')connectionDeadline=setTimeout(()=>{
   if(pc!==peer||pc.connectionState==='connected')return;closeConnection();
   status('Não encontramos um caminho de áudio e vídeo nesta rede. O convite abriu, mas a mídia não conectou. Tente Reconectar ou outra conexão de internet.');
   scheduleReconnect('Não encontramos um caminho de áudio e vídeo nesta rede.');
  },45000);
 }catch(error){if(generation===connectionGeneration){retryableFailure=![403,409,410].includes(error.status);closeConnection();failure(error);$('join').disabled=false;$('join').hidden=false;$('join').textContent='Tentar novamente';$('reconnectNow').hidden=false;}}
 finally{if(generation===connectionGeneration){
  joining=false;
  if(retryableFailure)scheduleReconnect('A comunicação com o estúdio falhou.');
  else if(peer?.connectionState==='failed')scheduleReconnect('A conexão de áudio e vídeo caiu.');
  else if(peer?.connectionState==='disconnected')scheduleReconnect('A conexão oscilou.',5000);
 }}
}
async function leave(){
 ++screenGeneration;++connectionGeneration;joining=false;closeConnection();stageMode(false);
 chatCursor=0;chatIdentity='';chatUnread=0;renderedChatIDs.clear();$('chatMessages').replaceChildren();updateChatBadge();
 ++mediaGeneration;preparing=false;$('devices').disabled=false;$('devices').textContent='Ativar câmera e microfone';$('devices').classList.remove('secondary');$('previewEmpty').hidden=false;
 media?.getTracks().forEach(t=>t.stop());screen?.getTracks().forEach(t=>t.stop());media=screen=null;
 if(animation)cancelAnimationFrame(animation);if(context){await context.close();context=null;}$('level').value=0;
 $('preview').srcObject=null;$('screenPreview').srcObject=null;$('screenPreview').hidden=true;$('screen').textContent='Compartilhar tela';$('returnAudio').srcObject=null;$('listen').hidden=true;
 $('join').hidden=false;$('join').disabled=true;$('join').textContent='Entrar no estúdio';$('leave').hidden=true;$('toggleCamera').disabled=true;$('toggleMic').disabled=true;
 updateControls();api('/leave').catch(()=>{});status('Você saiu. Câmera e microfone foram desligados.');
}
$('devices').onclick=prepare;$('camera').onchange=prepare;$('microphone').onchange=prepare;$('screen').onclick=shareScreen;$('join').onclick=join;$('reconnectNow').onclick=join;$('leave').onclick=leave;
$('openChat').onclick=()=>togglePanel('chat');$('closeChat').onclick=()=>togglePanel('chat');$('openSettings').onclick=()=>togglePanel('settings');$('closeSettings').onclick=()=>togglePanel('settings');
$('chatTo').onchange=updateChatPrivacy;$('chatForm').onsubmit=sendChat;
$('chatText').onkeydown=event=>{if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();$('chatForm').requestSubmit();}};
$('saveName').onclick=async()=>{
 const name=$('name').value.trim();
 if(!peer||peer.connectionState!=='connected'){$('nameStatus').textContent='Conecte-se ao estúdio para alterar o nome.';return;}
 if(!name||name.length>60){$('nameStatus').textContent='Informe um nome com até 60 caracteres.';return;}
 $('saveName').disabled=true;$('nameStatus').textContent='Atualizando nome…';
 try{const result=await api('/status',{name});$('name').value=result.name;$('headerSubtitle').textContent=result.name+' · no palco';$('nameStatus').textContent='Nome atualizado na cena. Sua câmera e seu áudio continuam conectados.';}
 catch(error){$('nameStatus').textContent=error.message||'Não foi possível atualizar o nome.';}
 finally{$('saveName').disabled=false;}
};
$('toggleCamera').onclick=()=>{const track=media?.getVideoTracks()[0];if(track){track.enabled=!track.enabled;$('toggleCamera').textContent=track.enabled?'Desligar câmera':'Ligar câmera';updateControls();}};
$('toggleMic').onclick=()=>{const track=media?.getAudioTracks()[0];if(track){track.enabled=!track.enabled;$('toggleMic').textContent=track.enabled?'Silenciar microfone':'Ligar microfone';updateControls();}};
$('listen').onclick=()=>{$('returnAudio').play().then(()=>{$('listen').hidden=true;}).catch(failure);};
if(!/^[a-f0-9]{64}$/.test(token)){status('Convite inválido. Abra o link completo recebido do apresentador.');$('devices').disabled=true;$('screen').disabled=true;}
else if(!navigator.mediaDevices?.getUserMedia||!window.RTCPeerConnection){status('Use uma versão atual do Chrome, Edge, Safari ou Firefox em uma conexão HTTPS.');$('devices').disabled=true;}

// Listing devices never requests access. Capture starts only after an explicit click.
if(/^[a-f0-9]{64}$/.test(token)&&navigator.mediaDevices?.getUserMedia&&window.RTCPeerConnection){void listDevices().catch(()=>{});navigator.mediaDevices.addEventListener?.('devicechange',()=>{if(!preparing)void listDevices().catch(()=>{});});}
window.addEventListener('pagehide',()=>{++connectionGeneration;closeConnection();++mediaGeneration;media?.getTracks().forEach(t=>t.stop());screen?.getTracks().forEach(t=>t.stop());peer?.close();if(heartbeat)clearInterval(heartbeat);if(chatTimer)clearInterval(chatTimer);if(animation)cancelAnimationFrame(animation);void context?.close();});
if(!navigator.mediaDevices?.getDisplayMedia)$('screen').hidden=true;

$('toggleReturnAudio').onclick=()=>{const audio=$('returnAudio');audio.muted=!audio.muted;$('toggleReturnAudio').textContent=audio.muted?'Ouvir retorno':'Silenciar retorno';$('toggleReturnAudio').setAttribute('aria-pressed',String(!audio.muted));$('toggleReturnAudio').classList.toggle('state-off',audio.muted);};
