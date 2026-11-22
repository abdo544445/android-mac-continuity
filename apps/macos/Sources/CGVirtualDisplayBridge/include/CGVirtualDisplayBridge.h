//
//  CGVirtualDisplayBridge.h
//  Adapted from DeskPad (https://github.com/Stengo/DeskPad, MIT License)
//  Safe dynamic Objective-C bridge for macOS CGVirtualDisplay API.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface ContinuityVirtualDisplayModeSpec : NSObject
@property (nonatomic, assign) NSUInteger width;
@property (nonatomic, assign) NSUInteger height;
@property (nonatomic, assign) double refreshRate;

- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate;
@end

@interface ContinuityVirtualDisplayBridge : NSObject

@property (nonatomic, readonly) CGDirectDisplayID displayID;
@property (nonatomic, readonly) BOOL isActive;
@property (nonatomic, readonly, copy) NSString *displayName;

+ (BOOL)isSupported;

- (nullable instancetype)initWithName:(NSString *)name
                        maxPixelsWide:(uint32_t)maxWide
                        maxPixelsHigh:(uint32_t)maxHigh
                    sizeInMillimeters:(CGSize)sizeInMM
                             vendorID:(uint32_t)vendorID
                            productID:(uint32_t)productID
                            serialNum:(uint32_t)serialNum
                   terminationHandler:(nullable void (^)(void))terminationHandler;

- (BOOL)applyModes:(NSArray<ContinuityVirtualDisplayModeSpec *> *)modes hiDPI:(BOOL)hiDPI;
- (void)destroy;

@end

NS_ASSUME_NONNULL_END
