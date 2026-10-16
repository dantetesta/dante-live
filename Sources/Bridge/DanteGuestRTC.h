#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Control methods are main-thread only. Media callbacks own retained OBS sources;
/// they never access dante_engine. Close peers before engine teardown.
__attribute__((swift_attr("@MainActor")))
@interface DanteGuestPeer : NSObject
- (nullable instancetype)initWithCamera:(NSString *)camera screen:(NSString *)screen microphone:(NSString *)microphone slot:(NSInteger)slot iceJSON:(NSString *)iceJSON;
@property(nonatomic, readonly) NSString *connectionStatus;
@property(nonatomic, readonly) NSDictionary *mediaDiagnostics;
@property(nonatomic, readonly) NSArray<NSString *> *sourceNames;
- (void)setCameraEnabled:(BOOL)camera screenEnabled:(BOOL)screen;
- (void)answerOffer:(NSString *)sdp completion:(void (^)(NSString * _Nullable answer, NSString * _Nullable error))completion;
- (void)close;
@end
void dante_register_guest_sources(void);
NS_ASSUME_NONNULL_END
