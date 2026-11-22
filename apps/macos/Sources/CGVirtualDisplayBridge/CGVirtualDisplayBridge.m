//
//  CGVirtualDisplayBridge.m
//  Adapted from DeskPad (https://github.com/Stengo/DeskPad, MIT License)
//

#import "CGVirtualDisplayBridge.h"
#import <objc/runtime.h>

@interface CGVirtualDisplayMode : NSObject
@property (readonly, nonatomic) CGFloat refreshRate;
@property (readonly, nonatomic) NSUInteger width;
@property (readonly, nonatomic) NSUInteger height;
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
- (instancetype)init;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) dispatch_queue_t queue;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (copy, nonatomic) void (^terminationHandler)(id, id);
- (instancetype)init;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) CGDirectDisplayID displayID;
@property (readonly, nonatomic) NSString *name;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

@implementation ContinuityVirtualDisplayModeSpec

- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)refreshRate {
    self = [super init];
    if (self) {
        _width = width;
        _height = height;
        _refreshRate = refreshRate;
    }
    return self;
}

@end

@interface ContinuityVirtualDisplayBridge ()
@property (nonatomic, strong, nullable) id virtualDisplay;
@property (nonatomic, assign, readwrite) CGDirectDisplayID displayID;
@property (nonatomic, copy, readwrite) NSString *displayName;
@end

@implementation ContinuityVirtualDisplayBridge

+ (BOOL)isSupported {
    return NSClassFromString(@"CGVirtualDisplay") != nil &&
           NSClassFromString(@"CGVirtualDisplayDescriptor") != nil &&
           NSClassFromString(@"CGVirtualDisplaySettings") != nil &&
           NSClassFromString(@"CGVirtualDisplayMode") != nil;
}

- (nullable instancetype)initWithName:(NSString *)name
                        maxPixelsWide:(uint32_t)maxWide
                        maxPixelsHigh:(uint32_t)maxHigh
                    sizeInMillimeters:(CGSize)sizeInMM
                             vendorID:(uint32_t)vendorID
                            productID:(uint32_t)productID
                            serialNum:(uint32_t)serialNum
                   terminationHandler:(nullable void (^)(void))terminationHandler {
    self = [super init];
    if (!self) return nil;

    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    if (!descriptorClass || !displayClass) {
        return nil;
    }

    id descriptor = [[descriptorClass alloc] init];
    if (!descriptor) return nil;

    if ([descriptor respondsToSelector:@selector(setDispatchQueue:)]) {
        [descriptor setDispatchQueue:dispatch_get_main_queue()];
    } else if ([descriptor respondsToSelector:@selector(setQueue:)]) {
        [descriptor setQueue:dispatch_get_main_queue()];
    }

    [descriptor setName:name];
    [descriptor setMaxPixelsWide:maxWide];
    [descriptor setMaxPixelsHigh:maxHigh];
    [descriptor setSizeInMillimeters:sizeInMM];
    [descriptor setVendorID:vendorID];
    [descriptor setProductID:productID];
    [descriptor setSerialNum:serialNum];

    if (terminationHandler) {
        __weak typeof(self) weakSelf = self;
        [descriptor setTerminationHandler:^(id displayObj, id errorObj) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.displayID = kCGNullDirectDisplay;
                weakSelf.virtualDisplay = nil;
                terminationHandler();
            });
        }];
    }

    id display = [[displayClass alloc] initWithDescriptor:descriptor];
    if (!display) {
        return nil;
    }

    _virtualDisplay = display;
    _displayID = [display displayID];
    _displayName = [name copy];

    if (_displayID == kCGNullDirectDisplay) {
        _virtualDisplay = nil;
        return nil;
    }

    return self;
}

- (BOOL)isActive {
    return self.virtualDisplay != nil && self.displayID != kCGNullDirectDisplay;
}

- (BOOL)applyModes:(NSArray<ContinuityVirtualDisplayModeSpec *> *)modes hiDPI:(BOOL)hiDPI {
    if (!self.virtualDisplay) return NO;

    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!settingsClass || !modeClass) return NO;

    id settings = [[settingsClass alloc] init];
    [settings setHiDPI:hiDPI ? 1 : 0];

    NSMutableArray *cgModes = [NSMutableArray arrayWithCapacity:modes.count];
    for (ContinuityVirtualDisplayModeSpec *spec in modes) {
        id mode = [[modeClass alloc] initWithWidth:spec.width
                                            height:spec.height
                                       refreshRate:(CGFloat)spec.refreshRate];
        if (mode) {
            [cgModes addObject:mode];
        }
    }
    [settings setModes:cgModes];

    return [self.virtualDisplay applySettings:settings];
}

- (void)destroy {
    self.virtualDisplay = nil;
    self.displayID = kCGNullDirectDisplay;
}

@end
