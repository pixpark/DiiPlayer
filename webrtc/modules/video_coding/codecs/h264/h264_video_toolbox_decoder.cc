/*
 *  Copyright (c) 2015 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 *
 */

#include "webrtc/modules/video_coding/codecs/h264/h264_video_toolbox_decoder.h"

#if defined(WEBRTC_VIDEO_TOOLBOX_SUPPORTED)

#include <memory>

#if defined(WEBRTC_IOS)
#include "RTCUIApplication.h"
#endif
#include "libyuv/convert.h"
#include "webrtc/base/checks.h"
#include "webrtc/base/timeutils.h"
#include "webrtc/base/logging.h"
#include "webrtc/common_video/include/corevideo_frame_buffer.h"
#include "webrtc/modules/video_coding/codecs/h264/h264_video_toolbox_nalu.h"
#include "webrtc/video_frame.h"

namespace eclive_internal {

static const int64_t kMsPerSec = 1000;

// Convenience function for creating a dictionary.
inline CFDictionaryRef CreateCFDictionary(CFTypeRef* keys,
                                          CFTypeRef* values,
                                          size_t size) {
  return CFDictionaryCreate(nullptr, keys, values, size,
                            &kCFTypeDictionaryKeyCallBacks,
                            &kCFTypeDictionaryValueCallBacks);
}

// Struct that we pass to the decoder per frame to decode. We receive it again
// in the decoder callback.
struct FrameDecodeParams {
  FrameDecodeParams(dii_media_kit::DecodedImageCallback* cb, int64_t ts)
      : callback(cb), timestamp(ts) {}
  dii_media_kit::DecodedImageCallback* callback;
  int64_t timestamp;
};

// On decode we receive a CVPixelBuffer, which we need to convert to a frame
// buffer for use in the rest of WebRTC. Unfortunately this involves a frame
// copy.
// TODO(tkchin): Stuff CVPixelBuffer into a TextureBuffer and pass that along
// instead once the pipeline supports it.
dii_rtc::scoped_refptr<dii_media_kit::VideoFrameBuffer> VideoFrameBufferForPixelBuffer(
                                                                            CVPixelBufferRef pixel_buffer) {
    RTC_DCHECK(pixel_buffer);
    RTC_DCHECK(CVPixelBufferGetPixelFormatType(pixel_buffer) ==
               kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
    size_t width = CVPixelBufferGetWidthOfPlane(pixel_buffer, 0);
    size_t height = CVPixelBufferGetHeightOfPlane(pixel_buffer, 0);
    // TODO(tkchin): Use a frame buffer pool.
    dii_rtc::scoped_refptr<dii_media_kit::VideoFrameBuffer> buffer =
    new dii_rtc::RefCountedObject<dii_media_kit::I420Buffer>(width, height);
    CVPixelBufferLockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
    const uint8_t* src_y = reinterpret_cast<const uint8_t*>(
                                                            CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 0));
    int src_y_stride = CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer, 0);
    const uint8_t* src_uv = reinterpret_cast<const uint8_t*>(
                                                             CVPixelBufferGetBaseAddressOfPlane(pixel_buffer, 1));
    int src_uv_stride = CVPixelBufferGetBytesPerRowOfPlane(pixel_buffer, 1);
    int ret = dii_libyuv::NV12ToI420(
                                 src_y, src_y_stride, src_uv, src_uv_stride,
                                 buffer->MutableDataY(), buffer->StrideY(),
                                 buffer->MutableDataU(), buffer->StrideU(),
                                 buffer->MutableDataV(), buffer->StrideV(),
                                 width, height);
    CVPixelBufferUnlockBaseAddress(pixel_buffer, kCVPixelBufferLock_ReadOnly);
    if (ret) {
        LOG(LS_ERROR) << "Error converting NV12 to I420: " << ret;
        return nullptr;
    }
    return buffer;
}
    
// This is the callback function that VideoToolbox calls when decode is
// complete.
void VTDecompressionOutputCallback(void* decoder,
                                   void* params,
                                   OSStatus status,
                                   VTDecodeInfoFlags info_flags,
                                   CVImageBufferRef image_buffer,
                                   CMTime timestamp,
                                   CMTime duration) {
  std::unique_ptr<FrameDecodeParams> decode_params(
      reinterpret_cast<FrameDecodeParams*>(params));
  if (status != noErr) {
    LOG(LS_ERROR) << "Failed to decode frame. Status: " << status;
    return;
  }
  // TODO(tkchin): Handle CVO properly.
//* Fix bug: when android camera has rotate, ios crash
//  dii_rtc::scoped_refptr<dii_media_kit::VideoFrameBuffer> buffer =
//      new dii_rtc::RefCountedObject<dii_media_kit::CoreVideoFrameBuffer>(image_buffer);
dii_rtc::scoped_refptr<dii_media_kit::VideoFrameBuffer> buffer =
    VideoFrameBufferForPixelBuffer(image_buffer);

    int64_t render_ts = 0;
    if(timestamp.value != 0) {
        render_ts =  CMTimeGetSeconds(timestamp)*kMsPerSec;
    } else {
        render_ts = dii_rtc::Time();
    }
    dii_media_kit::VideoFrame decoded_frame(buffer, static_cast<uint32_t>(decode_params->timestamp),
                                   render_ts,
                                   dii_media_kit::kVideoRotation_0);
    decode_params->callback->Decoded(decoded_frame);
}

}  // namespace internal

namespace dii_media_kit {

H264VideoToolboxDecoder::H264VideoToolboxDecoder()
    : callback_(nullptr),
      video_format_(nullptr),
      decompression_session_(nullptr) {}

H264VideoToolboxDecoder::~H264VideoToolboxDecoder() {
  DestroyDecompressionSession();
  SetVideoFormat(nullptr);
}

int H264VideoToolboxDecoder::InitDecode(const VideoCodec* video_codec,
                                        int number_of_cores) {
  return WEBRTC_VIDEO_CODEC_OK;
}


// Do decode image.
int H264VideoToolboxDecoder::Decode(
    const EncodedImage& input_image,
    bool missing_frames,
    const RTPFragmentationHeader* fragmentation,
    const CodecSpecificInfo* codec_specific_info,
    int64_t render_time_ms) {
  RTC_DCHECK(input_image._buffer);

#if defined(WEBRTC_IOS)
  if (!RTCIsUIApplicationActive()) {
    // Ignore all decode requests when app isn't active. In this state, the
    // hardware decoder has been invalidated by the OS.
    // Reset video format so that we won't process frames until the next
    // keyframe.
    SetVideoFormat(nullptr);
    return WEBRTC_VIDEO_CODEC_NO_OUTPUT;
  }
#endif
  CMVideoFormatDescriptionRef input_format = nullptr;
  if (H264AnnexBBufferHasVideoFormatDescription(input_image._buffer,
                                                input_image._length)) {
    input_format = CreateVideoFormatDescription(input_image._buffer,
                                                input_image._length);
    if (input_format) {
      // Check if the video format has changed, and reinitialize decoder if
      // needed.
      if (!CMFormatDescriptionEqual(input_format, video_format_)) {
        SetVideoFormat(input_format);
        ResetDecompressionSession();
      }
      CFRelease(input_format);
    }
  }
  if (!video_format_) {
    // We received a frame but we don't have format information so we can't
    // decode it.
    // This can happen after backgrounding. We need to wait for the next
    // sps/pps before we can resume so we request a keyframe by returning an
    // error.
      //    TODO(devzhaoyou ): LOG(LS_WARNING) << "Missing video format. Frame with sps/pps required.";
    return WEBRTC_VIDEO_CODEC_ERROR;
  }
  CMSampleBufferRef sample_buffer = nullptr;
  if (!H264AnnexBBufferToCMSampleBuffer(input_image._buffer,
                                        input_image._length, video_format_,
                                        &sample_buffer)) {
    return WEBRTC_VIDEO_CODEC_ERROR;
  }
  RTC_DCHECK(sample_buffer);
  VTDecodeFrameFlags decode_flags =
      kVTDecodeFrame_EnableAsynchronousDecompression;
  std::unique_ptr<eclive_internal::FrameDecodeParams> frame_decode_params;
  frame_decode_params.reset(
      new eclive_internal::FrameDecodeParams(callback_, input_image._timeStamp));
  
  //do decode image.
  OSStatus status = VTDecompressionSessionDecodeFrame(
      decompression_session_, sample_buffer, decode_flags,
      frame_decode_params.release(), nullptr);
#if defined(WEBRTC_IOS)
  // Re-initialize the decoder if we have an invalid session while the app is
  // active and retry the decode request.
  if (status == kVTInvalidSessionErr &&
      ResetDecompressionSession() == WEBRTC_VIDEO_CODEC_OK) {
    frame_decode_params.reset(
        new eclive_internal::FrameDecodeParams(callback_, input_image._timeStamp));
    status = VTDecompressionSessionDecodeFrame(
        decompression_session_, sample_buffer, decode_flags,
        frame_decode_params.release(), nullptr);
  }
#endif
  CFRelease(sample_buffer);
  if (status != noErr) {
    LOG(LS_ERROR) << "Failed to decode frame with code: " << status;
    return WEBRTC_VIDEO_CODEC_ERROR;
  }
  return WEBRTC_VIDEO_CODEC_OK;
}

int H264VideoToolboxDecoder::RegisterDecodeCompleteCallback(
    DecodedImageCallback* callback) {
  RTC_DCHECK(!callback_);
  callback_ = callback;
  return WEBRTC_VIDEO_CODEC_OK;
}

int H264VideoToolboxDecoder::Release() {
  // Need to invalidate the session so that callbacks no longer occur and it
  // is safe to null out the callback.
  DestroyDecompressionSession();
  SetVideoFormat(nullptr);
  callback_ = nullptr;
  return WEBRTC_VIDEO_CODEC_OK;
}

// create and config decode session.
int H264VideoToolboxDecoder::ResetDecompressionSession() {
  DestroyDecompressionSession();

  // Need to wait for the first SPS to initialize decoder.
  if (!video_format_) {
    return WEBRTC_VIDEO_CODEC_OK;
  }

  // Set keys for OpenGL and IOSurface compatibilty, which makes the encoder
  // create pixel buffers with GPU backed memory. The intent here is to pass
  // the pixel buffers directly so we avoid a texture upload later during
  // rendering. This currently is moot because we are converting back to an
  // I420 frame after decode, but eventually we will be able to plumb
  // CVPixelBuffers directly to the renderer.
  // TODO(tkchin): Maybe only set OpenGL/IOSurface keys if we know that that
  // we can pass CVPixelBuffers as native handles in decoder output.
  static size_t const attributes_size = 3;
  CFTypeRef keys[attributes_size] = {
#if defined(WEBRTC_IOS)
    kCVPixelBufferOpenGLESCompatibilityKey,
#elif defined(WEBRTC_MAC)
    kCVPixelBufferOpenGLCompatibilityKey,
#endif
    kCVPixelBufferIOSurfacePropertiesKey,
    kCVPixelBufferPixelFormatTypeKey
  };
  CFDictionaryRef io_surface_value =
      eclive_internal::CreateCFDictionary(nullptr, nullptr, 0);
  int64_t nv12type = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
  CFNumberRef pixel_format =
      CFNumberCreate(nullptr, kCFNumberLongType, &nv12type);
  CFTypeRef values[attributes_size] = {kCFBooleanTrue, io_surface_value,
                                       pixel_format};
  CFDictionaryRef attributes =
      eclive_internal::CreateCFDictionary(keys, values, attributes_size);
  if (io_surface_value) {
    CFRelease(io_surface_value);
    io_surface_value = nullptr;
  }
  if (pixel_format) {
    CFRelease(pixel_format);
    pixel_format = nullptr;
  }
    
  VTDecompressionOutputCallbackRecord record = {
      eclive_internal::VTDecompressionOutputCallback, this,
  };
  
  // create decode session
  OSStatus status =
      VTDecompressionSessionCreate(nullptr, video_format_, nullptr, attributes,
                                   &record, &decompression_session_);
  CFRelease(attributes);
  if (status != noErr) {
    DestroyDecompressionSession();
    return WEBRTC_VIDEO_CODEC_ERROR;
  }
    
  // config session
  ConfigureDecompressionSession();

  return WEBRTC_VIDEO_CODEC_OK;
}

void H264VideoToolboxDecoder::ConfigureDecompressionSession() {
  RTC_DCHECK(decompression_session_);
#if defined(WEBRTC_IOS)
  VTSessionSetProperty(decompression_session_,
                       kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
#endif
}

void H264VideoToolboxDecoder::DestroyDecompressionSession() {
  if (decompression_session_) {
    VTDecompressionSessionInvalidate(decompression_session_);
    CFRelease(decompression_session_);
    decompression_session_ = nullptr;
  }
}

void H264VideoToolboxDecoder::SetVideoFormat(
    CMVideoFormatDescriptionRef video_format) {
  if (video_format_ == video_format) {
    return;
  }
  if (video_format_) {
    CFRelease(video_format_);
  }
  video_format_ = video_format;
  if (video_format_) {
    CFRetain(video_format_);
  }
}

const char* H264VideoToolboxDecoder::ImplementationName() const {
  return "VideoToolbox";
}

}  // namespace dii_media_kit

#endif  // defined(WEBRTC_VIDEO_TOOLBOX_SUPPORTED)
