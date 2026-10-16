#import "DanteGuestRTC.h"
#import <LiveKitWebRTC/LiveKitWebRTC.h>
#include <obs.h>
#include <util/platform.h>
#include <mach/mach_time.h>
#include <atomic>
#include <array>
#include <algorithm>
#include <cmath>

static void *guestCreate(obs_data_t *,obs_source_t *s){return s;}
static void guestDestroy(void *){}
void dante_register_guest_sources(void){
    obs_source_info v={};v.id="dante_guest_video";v.type=OBS_SOURCE_TYPE_INPUT;v.output_flags=OBS_SOURCE_ASYNC_VIDEO | OBS_SOURCE_DO_NOT_DUPLICATE;
    v.get_name=[](void*){return "Vídeo do convidado";};v.create=guestCreate;v.destroy=guestDestroy;obs_register_source(&v);
    obs_source_info a={};a.id="dante_guest_audio";a.type=OBS_SOURCE_TYPE_INPUT;a.output_flags=OBS_SOURCE_AUDIO | OBS_SOURCE_DO_NOT_DUPLICATE;
    a.get_name=[](void*){return "Microfone do convidado";};a.create=guestCreate;a.destroy=guestDestroy;obs_register_source(&a);
}
// One producer (OBS audio thread), one consumer (dedicated 10ms WebRTC pump).
// Fixed capacity, no allocation/locks/disk in the OBS callback. Overflow drops new
// samples; consumer discards backlog >100ms instead of growing latency forever.
struct ReturnRing {
    static constexpr uint64_t capacity=48000;
    std::array<int16_t,capacity> data{};
    std::atomic<uint64_t> written{0},read{0};
    std::atomic<int> peak{0};
    void push(const int16_t *p,size_t count){auto w=written.load(std::memory_order_relaxed),r=read.load(std::memory_order_acquire);
        if(count>capacity-(w-r))return;int max=0;for(size_t i=0;i<count;++i){data[(w+i)%capacity]=p[i];max=std::max(max,std::abs((int)p[i]));}peak=max;written.store(w+count,std::memory_order_release);}
    void pop(int16_t *p,size_t count){auto r=read.load(std::memory_order_relaxed),w=written.load(std::memory_order_acquire);
        if(w-r>9600)r=w-960;size_t n=std::min<uint64_t>(count,w-r);for(size_t i=0;i<n;++i)p[i]=data[(r+i)%capacity];
        std::fill(p+n,p+count,0);read.store(r+n,std::memory_order_release);}
};
static void returnAudio(void *raw,size_t,audio_data *data){((ReturnRing*)raw)->push((const int16_t*)data->data[0],data->frames*2);}
@interface DanteGuestAudioDevice:NSObject<LKRTCAudioDevice> {
    ReturnRing _ring;dispatch_queue_t _queue;dispatch_source_t _timer;
    id<LKRTCAudioDeviceDelegate> _delegate;
    std::atomic<bool> _playing,_recording;bool _initialized,_connected;NSInteger _slot;
}
- (instancetype)initWithSlot:(NSInteger)slot;
- (void)disconnect;
- (NSDictionary*)diagnostics;
@end
@implementation DanteGuestAudioDevice
- (instancetype)initWithSlot:(NSInteger)slot {if((self=[super init])){_slot=slot;_queue=dispatch_queue_create("com.dantetesta.guest.audio",DISPATCH_QUEUE_SERIAL);}return self;}
- (double)deviceInputSampleRate{return 48000;}- (double)deviceOutputSampleRate{return 48000;}
- (NSTimeInterval)inputIOBufferDuration{return .01;}- (NSTimeInterval)outputIOBufferDuration{return .01;}
- (NSTimeInterval)inputLatency{return 0;}- (NSTimeInterval)outputLatency{return 0;}
- (NSInteger)inputNumberOfChannels{return 2;}- (NSInteger)outputNumberOfChannels{return 2;}
- (BOOL)isInitialized{return _initialized;}- (BOOL)isPlaying{return _playing.load();}- (BOOL)isRecording{return _recording.load();}
- (BOOL)isPlayoutInitialized{return _initialized;}- (BOOL)isRecordingInitialized{return _initialized;}
- (BOOL)initializePlayout{return YES;}- (BOOL)initializeRecording{return YES;}
- (BOOL)startPlayout{_playing=true;return YES;}- (BOOL)stopPlayout{_playing=false;return YES;}
- (BOOL)startRecording{_recording=true;return YES;}- (BOOL)stopRecording{_recording=false;return YES;}
- (BOOL)initializeWithDelegate:(id<LKRTCAudioDeviceDelegate>)delegate {
    if(_initialized)return YES;_delegate=delegate;
    audio_convert_info info={};info.format=AUDIO_FORMAT_16BIT;info.speakers=SPEAKERS_STEREO;info.samples_per_sec=48000;
    _connected=audio_output_connect(obs_get_audio(),4+_slot,&info,returnAudio,&_ring);
    if(!_connected){_delegate=nil;return NO;}
    _initialized=true;_timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,_queue);
    __weak DanteGuestAudioDevice *weak=self;
    dispatch_source_set_timer(_timer,dispatch_time(DISPATCH_TIME_NOW,0),10*NSEC_PER_MSEC,NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_timer,^{[weak pump];});dispatch_resume(_timer);return YES;
}
- (void)pump {
    @autoreleasepool {
        auto delegate=_delegate;if(!delegate)return;
        int16_t samples[960]={};AudioBufferList list={};list.mNumberBuffers=1;list.mBuffers[0]={2,sizeof(samples),samples};
        AudioTimeStamp time={};time.mFlags=kAudioTimeStampHostTimeValid;time.mHostTime=mach_absolute_time();AudioUnitRenderActionFlags flags=0;
        if(_playing.load())delegate.getPlayoutData(&flags,&time,0,480,&list); // Drives per-track PCM renderers; never plays to speakers itself.
        if(_recording.load()){
            _ring.pop(samples,960);flags=0;const int16_t *input=samples;
            // M150's direct inputData path counts frames as samples for stereo.
            // The supported renderBlock path correctly uses frames * channels.
            delegate.deliverRecordedData(&flags,&time,0,480,nullptr,nullptr,^(AudioUnitRenderActionFlags*,const AudioTimeStamp*,NSInteger,UInt32,AudioBufferList *destination,void*){
                if(destination->mNumberBuffers!=1||destination->mBuffers[0].mDataByteSize!=1920)return (OSStatus)-50;
                memcpy(destination->mBuffers[0].mData,input,1920);return (OSStatus)noErr;
            });
        }
    }
}
- (BOOL)terminateDevice{[self disconnect];return YES;}
- (NSDictionary*)diagnostics{return @{@"playing":@(_playing.load()),@"recording":@(_recording.load()),@"samplesReceived":@(_ring.written.load()),@"samplesRead":@(_ring.read.load()),@"returnPeak":@(_ring.peak.load())};}
- (void)disconnect {
    _playing=false;_recording=false;
    if(_connected){audio_output_disconnect(obs_get_audio(),4+_slot,returnAudio,&_ring);_connected=false;}
    if(_timer){dispatch_source_cancel(_timer);_timer=nil;dispatch_sync(_queue,^{});}
    _delegate=nil;_initialized=false;
}
@end

@interface DanteGuestVideoSink:NSObject<LKRTCVideoRenderer>{obs_source_t *_source;std::atomic<bool> _enabled;std::atomic<uint64_t> _frames;}
- (instancetype)initWithSource:(obs_source_t*)source;
- (void)setEnabled:(BOOL)enabled;
- (uint64_t)frames;
@end
@implementation DanteGuestVideoSink
- (instancetype)initWithSource:(obs_source_t*)source{if((self=[super init])){_source=obs_source_get_ref(source);_enabled=true;_frames=0;}return self;}
- (void)setEnabled:(BOOL)enabled{_enabled=enabled;if(!enabled)obs_source_output_video(_source,nullptr);}
- (void)dealloc{obs_source_release(_source);}
- (void)setSize:(CGSize)size{}
- (uint64_t)frames{return _frames.load(std::memory_order_relaxed);}
- (void)renderFrame:(LKRTCVideoFrame*)frame {
    if(!_enabled.load())return;
    if(!frame){obs_source_output_video(_source,nullptr);return;}
    if(frame.width<=0||frame.height<=0||frame.width>3840||frame.height>2160)return;
    id<LKRTCI420Buffer> b=[frame.buffer toI420];if(!b)return;
    obs_source_frame f={};f.width=b.width;f.height=b.height;f.format=VIDEO_FORMAT_I420;
    f.data[0]=(uint8_t*)b.dataY;f.data[1]=(uint8_t*)b.dataU;f.data[2]=(uint8_t*)b.dataV;
    f.linesize[0]=b.strideY;f.linesize[1]=b.strideU;f.linesize[2]=b.strideV;f.timestamp=os_gettime_ns();f.full_range=false;
    video_format_get_parameters(VIDEO_CS_709,VIDEO_RANGE_PARTIAL,f.color_matrix,f.color_range_min,f.color_range_max);
    obs_source_output_video(_source,&f); // libobs copies the borrowed planes before returning.
    _frames.fetch_add(1,std::memory_order_relaxed);
}
@end
@interface DanteGuestAudioSink:NSObject<LKRTCAudioRenderer>{obs_source_t *_source;}
- (instancetype)initWithSource:(obs_source_t*)source;
@end
@implementation DanteGuestAudioSink
- (instancetype)initWithSource:(obs_source_t*)source{if((self=[super init]))_source=obs_source_get_ref(source);return self;}
- (void)dealloc{obs_source_release(_source);}
- (void)renderPCMBuffer:(AVAudioPCMBuffer*)pcm {
    if(pcm.frameLength==0||pcm.format.channelCount>2)return;
    obs_source_audio a={};a.frames=pcm.frameLength;a.samples_per_sec=pcm.format.sampleRate;
    a.speakers=pcm.format.channelCount==2?SPEAKERS_STEREO:SPEAKERS_MONO;a.timestamp=os_gettime_ns();
    if(pcm.format.commonFormat==AVAudioPCMFormatFloat32)a.format=pcm.format.isInterleaved?AUDIO_FORMAT_FLOAT:AUDIO_FORMAT_FLOAT_PLANAR;
    else if(pcm.format.commonFormat==AVAudioPCMFormatInt16)a.format=pcm.format.isInterleaved?AUDIO_FORMAT_16BIT:AUDIO_FORMAT_16BIT_PLANAR;
    else return;
    const AudioBufferList *list=pcm.audioBufferList;for(UInt32 i=0;i<list->mNumberBuffers&&i<MAX_AV_PLANES;++i)a.data[i]=(uint8_t*)list->mBuffers[i].mData;
    obs_source_output_audio(_source,&a);
}
@end

// Independent, bounded program return. libobs performs one downscale into I420;
// each copied frame is owned by WebRTC after this callback returns. No frame queue.
@interface DanteGuestProgram:NSObject {
    LKRTCVideoSource *_source; LKRTCVideoCapturer *_capturer;
    video_t *_video; uint32_t _width,_height; std::atomic<uint64_t> _frames;
}
- (instancetype)initWithSource:(LKRTCVideoSource*)source;
- (BOOL)start;
- (void)stop;
- (void)frame:(video_data*)frame;
- (uint64_t)frames;
@end
static void programFrame(void *raw,video_data *frame){[(__bridge DanteGuestProgram*)raw frame:frame];}
@implementation DanteGuestProgram
- (instancetype)initWithSource:(LKRTCVideoSource*)source {if((self=[super init])){_source=source;_capturer=[[LKRTCVideoCapturer alloc]initWithDelegate:source];}return self;}
- (BOOL)start {
    if(_video)return YES;obs_video_info info={};if(!obs_get_video_info(&info))return NO;
    double scale=std::min(1.0,std::min(960.0/info.output_width,540.0/info.output_height));
    _width=std::max(2u,(uint32_t)(info.output_width*scale)&~1u);_height=std::max(2u,(uint32_t)(info.output_height*scale)&~1u);
    video_scale_info conversion={};conversion.format=VIDEO_FORMAT_I420;conversion.width=_width;conversion.height=_height;
    conversion.range=VIDEO_RANGE_PARTIAL;conversion.colorspace=VIDEO_CS_709;
    video_t *video=obs_get_video();uint32_t divisor=std::max(1u,(uint32_t)std::ceil(double(info.fps_num)/info.fps_den/15.0));
    if(!video)return NO;
    obs_add_raw_video_callback2(&conversion,divisor,programFrame,(__bridge void*)self);
    _video=video;return YES;
}
- (void)frame:(video_data*)frame {@autoreleasepool {
    LKRTCMutableI420Buffer *buffer=[[LKRTCMutableI420Buffer alloc]initWithWidth:_width height:_height];
    for(uint32_t y=0;y<_height;y++)memcpy(buffer.mutableDataY+y*buffer.strideY,frame->data[0]+y*frame->linesize[0],_width);
    for(uint32_t y=0;y<_height/2;y++){
        memcpy(buffer.mutableDataU+y*buffer.strideU,frame->data[1]+y*frame->linesize[1],_width/2);
        memcpy(buffer.mutableDataV+y*buffer.strideV,frame->data[2]+y*frame->linesize[2],_width/2);
    }
    [_source capturer:_capturer didCaptureVideoFrame:[[LKRTCVideoFrame alloc]initWithBuffer:buffer rotation:LKRTCVideoRotation_0 timeStampNs:frame->timestamp]];
    _frames.fetch_add(1,std::memory_order_relaxed);
}}
- (uint64_t)frames{return _frames.load(std::memory_order_relaxed);}
- (void)stop{if(_video){obs_remove_raw_video_callback(programFrame,(__bridge void*)self);_video=nullptr;}}
- (void)dealloc{NSAssert(!_video,@"Stop program return before releasing it");}
@end

@interface DanteGuestPeer()<LKRTCPeerConnectionDelegate> {
    LKRTCPeerConnectionFactory *_factory;LKRTCPeerConnection *_peer;DanteGuestAudioDevice *_device;
    DanteGuestVideoSink *_cameraSink,*_screenSink;DanteGuestAudioSink *_audioSink;
    LKRTCVideoTrack *_cameraTrack,*_screenTrack;LKRTCAudioTrack *_audioTrack;
    LKRTCVideoSource *_programSource;DanteGuestProgram *_program;
    obs_source_t *_camera,*_screen,*_microphone;bool _closed,_answerReady;
    void (^_completion)(NSString*,NSString*);NSString *_connectionStatus;
    NSMutableArray<NSDictionary*> *_localCandidates;
    NSMutableSet<NSString*> *_remoteCandidates;
    NSUInteger _candidateErrors;
}
@end
@implementation DanteGuestPeer
- (instancetype)initWithCamera:(NSString*)camera screen:(NSString*)screen microphone:(NSString*)microphone slot:(NSInteger)slot iceJSON:(NSString*)iceJSON {
    if(!(self=[super init]))return nil;if(slot<0||slot>1){_closed=true;return nil;}
    LKRTCInitializeSSL();_connectionStatus=@"Aguardando conexão";
    _localCandidates=[NSMutableArray array];_remoteCandidates=[NSMutableSet set];
    auto source=[](NSString *name,const char *type){auto *s=obs_get_source_by_name(name.UTF8String);if(s&&strcmp(obs_source_get_unversioned_id(s),type)){obs_source_release(s);return (obs_source_t*)nullptr;}return s?:obs_source_create(type,name.UTF8String,nullptr,nullptr);};
    _camera=source(camera,"dante_guest_video");_screen=source(screen,"dante_guest_video");_microphone=source(microphone,"dante_guest_audio");
    if(!_camera||!_screen||!_microphone){[self close];return nil;}
    obs_source_set_audio_mixers(_microphone,63&~(1<<(4+slot)));
    auto *guestSettings=obs_source_get_settings(_microphone);obs_data_set_int(guestSettings,"return_slot",slot);obs_source_update(_microphone,guestSettings);obs_data_release(guestSettings);
    _cameraSink=[[DanteGuestVideoSink alloc]initWithSource:_camera];_screenSink=[[DanteGuestVideoSink alloc]initWithSource:_screen];_audioSink=[[DanteGuestAudioSink alloc]initWithSource:_microphone];
    _device=[[DanteGuestAudioDevice alloc]initWithSlot:slot];
    _factory=[[LKRTCPeerConnectionFactory alloc]initWithEncoderFactory:[[LKRTCDefaultVideoEncoderFactory alloc]init] decoderFactory:[[LKRTCDefaultVideoDecoderFactory alloc]init] audioDevice:_device];
    LKRTCConfiguration *cfg=[LKRTCConfiguration new];cfg.sdpSemantics=LKRTCSdpSemanticsUnifiedPlan;
    NSMutableArray *servers=[NSMutableArray array];NSArray *ice=[NSJSONSerialization JSONObjectWithData:[iceJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    for(NSDictionary *entry in ice){NSArray *urls=[entry[@"urls"] isKindOfClass:NSString.class]?@[entry[@"urls"]]:entry[@"urls"];if([urls isKindOfClass:NSArray.class]) [servers addObject:[[LKRTCIceServer alloc]initWithURLStrings:urls username:entry[@"username"] credential:entry[@"credential"]]];}
    cfg.iceServers=servers;
    _peer=[_factory peerConnectionWithConfiguration:cfg constraints:[[LKRTCMediaConstraints alloc]initWithMandatoryConstraints:nil optionalConstraints:nil] delegate:self];
    if(!_peer){[self close];return nil;}return self;
}
- (NSString*)connectionStatus{return _connectionStatus?:@"Desconectado";}
- (NSArray<NSDictionary*>*)localCandidates{return [_localCandidates copy]?:@[];}
- (void)addRemoteCandidate:(NSString*)candidate mid:(NSString*)mid line:(int)line {
    if(_closed||_remoteCandidates.count>=64||candidate.length>1024||![candidate hasPrefix:@"candidate:"]||line<0||line>2)return;
    NSString *key=[NSString stringWithFormat:@"%d|%@|%@",line,mid,candidate];
    if([_remoteCandidates containsObject:key])return;[_remoteCandidates addObject:key];
    __weak DanteGuestPeer *weak=self;
    [_peer addIceCandidate:[[LKRTCIceCandidate alloc]initWithSdp:candidate sdpMLineIndex:line sdpMid:mid] completionHandler:^(NSError *error){
        if(error)dispatch_async(dispatch_get_main_queue(),^{DanteGuestPeer *s=weak;if(s&&!s->_closed)s->_candidateErrors++;});
    }];
}
- (NSArray<NSString*>*)sourceNames { return _closed ? @[] : @[[NSString stringWithUTF8String:obs_source_get_name(_camera)], [NSString stringWithUTF8String:obs_source_get_name(_screen)], [NSString stringWithUTF8String:obs_source_get_name(_microphone)]]; }
- (NSDictionary*)mediaDiagnostics {
    NSMutableDictionary *result=[([_device diagnostics]?:@{}) mutableCopy];
    result[@"localCandidateCount"]=@(_localCandidates.count);result[@"remoteCandidateCount"]=@(_remoteCandidates.count);
    result[@"programFrames"]=@([_program frames]);
    result[@"cameraFrames"]=@([_cameraSink frames]);result[@"screenFrames"]=@([_screenSink frames]);
    result[@"candidateErrors"]=@(_candidateErrors);result[@"iceGatheringState"]=@(_peer.iceGatheringState);
    return result;
}
- (void)setCameraEnabled:(BOOL)camera screenEnabled:(BOOL)screen {if(!_closed){[_cameraSink setEnabled:camera];[_screenSink setEnabled:screen];}}
- (void)answerOffer:(NSString*)sdp completion:(void(^)(NSString*,NSString*))completion {
    if(_closed||_completion){completion(nil,@"Convite ocupado ou encerrado.");return;}_completion=[completion copy];_answerReady=false;
    __weak DanteGuestPeer *weak=self;
    [_peer setRemoteDescription:[[LKRTCSessionDescription alloc]initWithType:LKRTCSdpTypeOffer sdp:sdp] completionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        DanteGuestPeer *s=weak;if(!s||s->_closed)return;if(error){[s finish:nil error:@"Oferta WebRTC inválida."];return;}
        for(LKRTCRtpTransceiver *t in s->_peer.transceivers)[s attachReceiver:t];
        if(!s->_peer.senders.count||!s->_peer.senders.firstObject.track){
            LKRTCAudioTrack *returnTrack=[s->_factory audioTrackWithTrackId:@"dante-return"];
            [returnTrack setAudioProcessingOptions:[LKRTCAudioProcessingOptions rawOptions]];
            [s->_peer addTrack:returnTrack streamIds:@[@"dante-return"]];
        }
        if(!s->_programSource){
            s->_programSource=[s->_factory videoSource];
            LKRTCVideoTrack *track=[s->_factory videoTrackWithSource:s->_programSource trackId:@"dante-program"];
            [s->_peer addTrack:track streamIds:@[@"dante-program"]];
            s->_program=[[DanteGuestProgram alloc]initWithSource:s->_programSource];
        }
        [s->_peer answerForConstraints:[[LKRTCMediaConstraints alloc]initWithMandatoryConstraints:nil optionalConstraints:nil] completionHandler:^(LKRTCSessionDescription *answer,NSError *err){dispatch_async(dispatch_get_main_queue(),^{
            DanteGuestPeer *p=weak;if(!p||p->_closed)return;if(err||!answer){[p finish:nil error:@"Não foi possível negociar a mídia."];return;}
            [p->_peer setLocalDescription:answer completionHandler:^(NSError *localError){dispatch_async(dispatch_get_main_queue(),^{DanteGuestPeer *q=weak;if(!q||q->_closed)return;if(localError){[q finish:nil error:@"Não foi possível preparar a resposta."];return;}q->_answerReady=true;[q finish:q->_peer.localDescription.sdp error:nil];});}];
        });}];
    });}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{DanteGuestPeer *s=weak;if(s&&!s->_closed&&s->_completion)[s finish:nil error:@"A negociação demorou demais. Tente reconectar."];});
}
- (void)finish:(NSString*)answer error:(NSString*)error {if(_completion){auto block=_completion;_completion=nil;block(answer,error);}}
- (void)close {
    if(_closed)return;_closed=true;[self finish:nil error:@"Convite encerrado."];
    [_cameraTrack removeRenderer:_cameraSink];[_screenTrack removeRenderer:_screenSink];[_audioTrack removeRenderer:_audioSink];
    [_program stop];_program=nil;_programSource=nil;
    _peer.delegate=nil;[_device disconnect];[_peer close];_peer=nil;_factory=nil;
    _cameraTrack=nil;_screenTrack=nil;_audioTrack=nil;_cameraSink=nil;_screenSink=nil;_audioSink=nil;
    if(_camera)obs_source_output_video(_camera,nullptr);if(_screen)obs_source_output_video(_screen,nullptr);
    obs_source_release(_camera);obs_source_release(_screen);obs_source_release(_microphone);_camera=_screen=_microphone=nullptr;
    _connectionStatus=@"Desconectado";
}
- (void)dealloc {NSAssert(_closed,@"Guest must close on main thread before engine teardown");}
- (void)peerConnection:(LKRTCPeerConnection*)pc didChangeSignalingState:(LKRTCSignalingState)state{}
- (void)peerConnection:(LKRTCPeerConnection*)pc didAddStream:(LKRTCMediaStream*)stream{}
- (void)peerConnection:(LKRTCPeerConnection*)pc didRemoveStream:(LKRTCMediaStream*)stream{}
- (void)peerConnectionShouldNegotiate:(LKRTCPeerConnection*)pc{}
- (void)peerConnection:(LKRTCPeerConnection*)pc didGenerateIceCandidate:(LKRTCIceCandidate*)candidate {
    dispatch_async(dispatch_get_main_queue(),^{if(self->_closed||self->_localCandidates.count>=64)return;
        [self->_localCandidates addObject:@{@"candidate":candidate.sdp,@"sdpMid":candidate.sdpMid?:@"0",@"sdpMLineIndex":@(candidate.sdpMLineIndex)}];
    });
}
- (void)peerConnection:(LKRTCPeerConnection*)pc didRemoveIceCandidates:(NSArray<LKRTCIceCandidate*>*)candidates{}
- (void)peerConnection:(LKRTCPeerConnection*)pc didOpenDataChannel:(LKRTCDataChannel*)channel{}
- (void)peerConnection:(LKRTCPeerConnection*)pc didChangeIceConnectionState:(LKRTCIceConnectionState)state{}
- (void)peerConnection:(LKRTCPeerConnection*)pc didChangeIceGatheringState:(LKRTCIceGatheringState)state {
    if(state==LKRTCIceGatheringStateComplete)dispatch_async(dispatch_get_main_queue(),^{if(!self->_closed&&self->_answerReady)[self finish:self->_peer.localDescription.sdp error:nil];});
}
- (void)peerConnection:(LKRTCPeerConnection*)pc didChangeConnectionState:(LKRTCPeerConnectionState)state {
    dispatch_async(dispatch_get_main_queue(),^{if(self->_closed)return;
        self->_connectionStatus=state==LKRTCPeerConnectionStateConnected?@"Conectado":state==LKRTCPeerConnectionStateConnecting?@"Procurando caminho de conexão":state==LKRTCPeerConnectionStateFailed?@"Não foi possível conectar pela rede atual":@"Desconectado";
        if(state==LKRTCPeerConnectionStateConnected)[self->_program start];
        if(state==LKRTCPeerConnectionStateDisconnected||state==LKRTCPeerConnectionStateFailed){obs_source_output_video(self->_camera,nullptr);obs_source_output_video(self->_screen,nullptr);}
    });
}
- (void)peerConnection:(LKRTCPeerConnection*)pc didStartReceivingOnTransceiver:(LKRTCRtpTransceiver*)transceiver {
    dispatch_async(dispatch_get_main_queue(),^{[self attachReceiver:transceiver];});
}
- (void)attachReceiver:(LKRTCRtpTransceiver*)transceiver {
    if(_closed)return;LKRTCMediaStreamTrack *track=transceiver.receiver.track;
        if([track isKindOfClass:LKRTCAudioTrack.class]){[self->_audioTrack removeRenderer:self->_audioSink];self->_audioTrack=(LKRTCAudioTrack*)track;[self->_audioTrack addRenderer:self->_audioSink];}
        else if([track isKindOfClass:LKRTCVideoTrack.class]){if([transceiver.mid isEqual:@"0"]){[self->_cameraTrack removeRenderer:self->_cameraSink];self->_cameraTrack=(LKRTCVideoTrack*)track;[self->_cameraTrack addRenderer:self->_cameraSink];}
            else if([transceiver.mid isEqual:@"2"]){[self->_screenTrack removeRenderer:self->_screenSink];self->_screenTrack=(LKRTCVideoTrack*)track;[self->_screenTrack addRenderer:self->_screenSink];}}
}
@end
