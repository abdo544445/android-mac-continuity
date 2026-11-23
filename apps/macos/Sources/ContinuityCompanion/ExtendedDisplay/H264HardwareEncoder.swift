import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Hardware-accelerated Apple VideoToolbox H.264 real-time encoder for Mac Extended Display.
/// Produces zero-B-frame Annex-B NAL units (with SPS/PPS prepended on every IDR keyframe)
/// and Display P3 / Rec.709 color signaling for crisp text and rich color reproduction.
public final class H264HardwareEncoder: @unchecked Sendable {
    private var session: VTCompressionSession?
    private var width: Int32 = 0
    private var height: Int32 = 0
    private var fps: Int32 = 30
    private var bitrateBps: Int = 20_000_000
    private var forceNextKeyframe: Bool = true
    private var frameIndex: Int64 = 0
    private let lock = NSLock()
    private let onEncodedFrame: (Data, Bool) -> Void

    public init(width: Int, height: Int, fps: Int, bitrateBps: Int, onEncodedFrame: @escaping (Data, Bool) -> Void) {
        self.width = Int32(width)
        self.height = Int32(height)
        self.fps = Int32(max(15, fps))
        self.bitrateBps = bitrateBps
        self.onEncodedFrame = onEncodedFrame
        createSession()
    }

    deinit {
        invalidate()
    }

    public func requestKeyframe() {
        lock.lock()
        forceNextKeyframe = true
        lock.unlock()
    }

    public func invalidate() {
        lock.lock()
        let sess = session
        session = nil
        lock.unlock()
        if let sess = sess {
            VTCompressionSessionCompleteFrames(sess, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(sess)
        }
    }

    private func createSession() {
        lock.lock()
        defer { lock.unlock() }

        var newSession: VTCompressionSession?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { outputCallbackRefCon, _, status, _, sampleBuffer in
                guard status == noErr,
                      let refcon = outputCallbackRefCon,
                      let sampleBuffer = sampleBuffer else { return }
                let encoder = Unmanaged<H264HardwareEncoder>.fromOpaque(refcon).takeUnretainedValue()
                encoder.handleEncodedSampleBuffer(sampleBuffer)
            },
            refcon: refcon,
            compressionSessionOut: &newSession
        )

        guard status == noErr, let sess = newSession else {
            return
        }

        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrateBps))
        let byteLimit = NSNumber(value: max(512_000, bitrateBps / 4))
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_DataRateLimits, value: [byteLimit, NSNumber(value: 1)] as CFArray)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps * 2))
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_P3_D65)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)

        VTCompressionSessionPrepareToEncodeFrames(sess)
        self.session = sess
        self.forceNextKeyframe = true
    }

    public func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        lock.lock()
        guard let sess = session else {
            lock.unlock()
            return
        }
        let shouldForceKey = forceNextKeyframe
        forceNextKeyframe = false
        let pts = presentationTime.isValid ? presentationTime : CMTime(value: frameIndex, timescale: CMTimeScale(fps))
        frameIndex += 1
        lock.unlock()

        var properties: CFDictionary? = nil
        if shouldForceKey {
            properties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary
        }

        VTCompressionSessionEncodeFrame(
            sess,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        // Check if this frame is a keyframe (IDR)
        var isKeyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first,
           let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            isKeyframe = !notSync
        }

        var annexB = Data()
        let startCode = Data([0x00, 0x00, 0x00, 0x01])

        // Prepend SPS + PPS parameter sets before every IDR keyframe so Android MediaCodec can join/recover cleanly
        if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var spsPtr: UnsafePointer<UInt8>?
            var spsSize = 0
            var spsCount = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc, parameterSetIndex: 0,
                parameterSetPointerOut: &spsPtr, parameterSetSizeOut: &spsSize,
                parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil
            ) == noErr, let spsPtr = spsPtr, spsSize > 0 {
                annexB.append(startCode)
                annexB.append(spsPtr, count: spsSize)
            }

            var ppsPtr: UnsafePointer<UInt8>?
            var ppsSize = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc, parameterSetIndex: 1,
                parameterSetPointerOut: &ppsPtr, parameterSetSizeOut: &ppsSize,
                parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil
            ) == noErr, let ppsPtr = ppsPtr, ppsSize > 0 {
                annexB.append(startCode)
                annexB.append(ppsPtr, count: ppsSize)
            }
        }

        // Convert AVCC 4-byte length-prefixed NAL units to Annex-B 00 00 00 01 start codes
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(
            dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength, dataPointerOut: &dataPointer
        ) == noErr, let ptr = dataPointer else {
            return
        }

        var offset = 0
        let avccHeaderLen = 4
        while offset + avccHeaderLen <= totalLength {
            var nalLengthBE: UInt32 = 0
            memcpy(&nalLengthBE, ptr.advanced(by: offset), avccHeaderLen)
            let nalLength = Int(CFSwapInt32BigToHost(nalLengthBE))
            offset += avccHeaderLen
            guard nalLength > 0, offset + nalLength <= totalLength else { break }

            annexB.append(startCode)
            annexB.append(UnsafeRawPointer(ptr.advanced(by: offset)).assumingMemoryBound(to: UInt8.self), count: nalLength)
            offset += nalLength
        }

        if !annexB.isEmpty {
            onEncodedFrame(annexB, isKeyframe)
        }
    }
}
