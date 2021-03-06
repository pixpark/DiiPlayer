/*
 *  Copyright 2016 The WebRTC Project Authors. All rights reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#import "webrtc/modules/audio_device/ios/voice_processing_audio_unit.h"

#include "webrtc/base/checks.h"

#import "WebRTC/RTCLogging.h"
#import "webrtc/modules/audio_device/ios/objc/RTCAudioSessionConfiguration.h"

#if !defined(NDEBUG)
static void LogStreamDescription(AudioStreamBasicDescription description) {
  char formatIdString[5];
  UInt32 formatId = CFSwapInt32HostToBig(description.mFormatID);
  bcopy(&formatId, formatIdString, 4);
  formatIdString[4] = '\0';
  RTCLog(@"AudioStreamBasicDescription: {\n"
          "  mSampleRate: %.2f\n"
          "  formatIDString: %s\n"
          "  mFormatFlags: 0x%X\n"
          "  mBytesPerPacket: %u\n"
          "  mFramesPerPacket: %u\n"
          "  mBytesPerFrame: %u\n"
          "  mChannelsPerFrame: %u\n"
          "  mBitsPerChannel: %u\n"
          "  mReserved: %u\n}",
         description.mSampleRate, formatIdString,
         static_cast<unsigned int>(description.mFormatFlags),
         static_cast<unsigned int>(description.mBytesPerPacket),
         static_cast<unsigned int>(description.mFramesPerPacket),
         static_cast<unsigned int>(description.mBytesPerFrame),
         static_cast<unsigned int>(description.mChannelsPerFrame),
         static_cast<unsigned int>(description.mBitsPerChannel),
         static_cast<unsigned int>(description.mReserved));
}
#endif

namespace dii_media_kit {

// Calls to AudioUnitInitialize() can fail if called back-to-back on different
// ADM instances. A fall-back solution is to allow multiple sequential calls
// with as small delay between each. This factor sets the max number of allowed
// initialization attempts.
static const int kMaxNumberOfAudioUnitInitializeAttempts = 5;
// A VP I/O unit's bus 1 connects to input hardware (microphone).
static const AudioUnitElement kInputBus = 1;
// A VP I/O unit's bus 0 connects to output hardware (speaker).
static const AudioUnitElement kOutputBus = 0;

VoiceProcessingAudioUnit::VoiceProcessingAudioUnit(
    VoiceProcessingAudioUnitObserver* observer)
    : observer_(observer), vpio_unit_(nullptr), state_(kInitRequired) {
  RTC_DCHECK(observer);
}

VoiceProcessingAudioUnit::~VoiceProcessingAudioUnit() {
  DisposeAudioUnit();
}

const UInt32 VoiceProcessingAudioUnit::kBytesPerSample = 2;

bool VoiceProcessingAudioUnit::Init() {
  RTC_DCHECK_EQ(state_, kInitRequired);

  // Create an audio component description to identify the Voice Processing
  // I/O audio unit.
  AudioComponentDescription vpio_unit_description;
  vpio_unit_description.componentType = kAudioUnitType_Output;
    vpio_unit_description.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    //kAudioUnitSubType_RemoteIO;//kAudioUnitSubType_VoiceProcessingIO;
  vpio_unit_description.componentManufacturer = kAudioUnitManufacturer_Apple;
  vpio_unit_description.componentFlags = 0;
  vpio_unit_description.componentFlagsMask = 0;
  //  AVAudioSessionCategoryOptionMixWithOthers;

  // Obtain an audio unit instance given the description.
  AudioComponent found_vpio_unit_ref =
      AudioComponentFindNext(nullptr, &vpio_unit_description);

  // Create a Voice Processing IO audio unit.
  OSStatus result = noErr;
  result = AudioComponentInstanceNew(found_vpio_unit_ref, &vpio_unit_);
  if (result != noErr) {
    vpio_unit_ = nullptr;
    RTCLogError(@"AudioComponentInstanceNew failed. Error=%ld.", (long)result);
    return false;
  }
    
  Boolean enable_record = NO;
  // Enable input on the input scope of the input element.
  if(enable_record) {
      UInt32 enable_input = 0;
      result = AudioUnitSetProperty(vpio_unit_, kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input, kInputBus, &enable_input,
                                    sizeof(enable_input));
      if (result != noErr) {
          DisposeAudioUnit();
          RTCLogError(@"Failed to enable input on input scope of input element. "
                      "Error=%ld.",
                      (long)result);
          return false;
      }
  }

  // Enable output on the output scope of the output element.
  UInt32 enable_output = 1;
  result = AudioUnitSetProperty(vpio_unit_, kAudioOutputUnitProperty_EnableIO,
                                kAudioUnitScope_Output, kOutputBus,
                                &enable_output, sizeof(enable_output));
  if (result != noErr) {
    DisposeAudioUnit();
    RTCLogError(@"Failed to enable output on output scope of output element. "
                 "Error=%ld.",
                (long)result);
    return false;
  }

  // Specify the callback function that provides audio samples to the audio
  // unit.
  AURenderCallbackStruct render_callback;
  render_callback.inputProc = OnGetPlayoutData;
  render_callback.inputProcRefCon = this;
  result = AudioUnitSetProperty(
      vpio_unit_, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
      kOutputBus, &render_callback, sizeof(render_callback));
  if (result != noErr) {
    DisposeAudioUnit();
    RTCLogError(@"Failed to specify the render callback on the output bus. "
                 "Error=%ld.",
                (long)result);
    return false;
  }

  // Disable AU buffer allocation for the recorder, we allocate our own.
  // TODO(henrika): not sure that it actually saves resource to make this call.
  UInt32 flag = 0;
  result = AudioUnitSetProperty(
      vpio_unit_, kAudioUnitProperty_ShouldAllocateBuffer,
      kAudioUnitScope_Output, kInputBus, &flag, sizeof(flag));
  if (result != noErr) {
    DisposeAudioUnit();
    RTCLogError(@"Failed to disable buffer allocation on the input bus. "
                 "Error=%ld.",
                (long)result);
    return false;
  }

  // Specify the callback to be called by the I/O thread to us when input audio
  // is available. The recorded samples can then be obtained by calling the
  // AudioUnitRender() method.
  if(enable_record) {
      AURenderCallbackStruct input_callback;
      input_callback.inputProc = OnDeliverRecordedData;
      input_callback.inputProcRefCon = this;
      result = AudioUnitSetProperty(vpio_unit_,
                                      kAudioOutputUnitProperty_SetInputCallback,
                                      kAudioUnitScope_Global, kInputBus,
                                      &input_callback, sizeof(input_callback));
      if (result != noErr) {
            DisposeAudioUnit();
            RTCLogError(@"Failed to specify the input callback on the input bus. "
                        "Error=%ld.",
                        (long)result);
            return false;
      }
  }
  

  state_ = kUninitialized;
  return true;
}

VoiceProcessingAudioUnit::State VoiceProcessingAudioUnit::GetState() const {
  return state_;
}

bool VoiceProcessingAudioUnit::Initialize(Float64 sample_rate) {
  RTC_DCHECK_GE(state_, kUninitialized);
  RTCLog(@"Initializing audio unit with sample rate: %f", sample_rate);

  OSStatus result = noErr;
  AudioStreamBasicDescription format = GetFormat(sample_rate);
  UInt32 size = sizeof(format);
#if !defined(NDEBUG)
  LogStreamDescription(format);
#endif

  // Set the format on the output scope of the input element/bus.
  result =
      AudioUnitSetProperty(vpio_unit_, kAudioUnitProperty_StreamFormat,
                           kAudioUnitScope_Output, kInputBus, &format, size);
  if (result != noErr) {
    RTCLogError(@"Failed to set format on output scope of input bus. "
                 "Error=%ld.",
                (long)result);
    return false;
  }

  // Set the format on the input scope of the output element/bus.
  result =
      AudioUnitSetProperty(vpio_unit_, kAudioUnitProperty_StreamFormat,
                           kAudioUnitScope_Input, kOutputBus, &format, size);
  if (result != noErr) {
    RTCLogError(@"Failed to set format on input scope of output bus. "
                 "Error=%ld.",
                (long)result);
    return false;
  }

  // Initialize the Voice Processing I/O unit instance.
  // Calls to AudioUnitInitialize() can fail if called back-to-back on
  // different ADM instances. The error message in this case is -66635 which is
  // undocumented. Tests have shown that calling AudioUnitInitialize a second
  // time, after a short sleep, avoids this issue.
  // See webrtc:5166 for details.
  int failed_initalize_attempts = 0;
  result = AudioUnitInitialize(vpio_unit_);
  while (result != noErr) {
    RTCLogError(@"Failed to initialize the Voice Processing I/O unit. "
                 "Error=%ld.",
                (long)result);
    ++failed_initalize_attempts;
    if (failed_initalize_attempts == kMaxNumberOfAudioUnitInitializeAttempts) {
      // Max number of initialization attempts exceeded, hence abort.
      RTCLogError(@"Too many initialization attempts.");
      return false;
    }
    RTCLog(@"Pause 100ms and try audio unit initialization again...");
    [NSThread sleepForTimeInterval:0.1f];
    result = AudioUnitInitialize(vpio_unit_);
  }
  if (result == noErr) {
    RTCLog(@"Voice Processing I/O unit is now initialized.");
  }
  state_ = kInitialized;
  return true;
}

bool VoiceProcessingAudioUnit::Start() {
  RTC_DCHECK_GE(state_, kUninitialized);
  RTCLog(@"Starting audio unit.");

  OSStatus result = AudioOutputUnitStart(vpio_unit_);
  if (result != noErr) {
    RTCLogError(@"Failed to start audio unit. Error=%ld", (long)result);
    return false;
  } else {
    RTCLog(@"Started audio unit");
  }
  state_ = kStarted;
  return true;
}

bool VoiceProcessingAudioUnit::Stop() {
  RTC_DCHECK_GE(state_, kUninitialized);
  RTCLog(@"Stopping audio unit.");

  OSStatus result = AudioOutputUnitStop(vpio_unit_);
  if (result != noErr) {
    RTCLogError(@"Failed to stop audio unit. Error=%ld", (long)result);
    return false;
  } else {
    RTCLog(@"Stopped audio unit");
  }

  state_ = kInitialized;
  return true;
}

bool VoiceProcessingAudioUnit::Uninitialize() {
  RTC_DCHECK_GE(state_, kUninitialized);
  RTCLog(@"Unintializing audio unit.");

  OSStatus result = AudioUnitUninitialize(vpio_unit_);
  if (result != noErr) {
    RTCLogError(@"Failed to uninitialize audio unit. Error=%ld", (long)result);
    return false;
  } else {
    RTCLog(@"Uninitialized audio unit.");
  }

  state_ = kUninitialized;
  return true;
}

OSStatus VoiceProcessingAudioUnit::Render(AudioUnitRenderActionFlags* flags,
                                          const AudioTimeStamp* time_stamp,
                                          UInt32 output_bus_number,
                                          UInt32 num_frames,
                                          AudioBufferList* io_data) {
  RTC_DCHECK(vpio_unit_) << "Init() not called.";

  OSStatus result = AudioUnitRender(vpio_unit_, flags, time_stamp,
                                    output_bus_number, num_frames, io_data);
  if (result != noErr) {
    RTCLogError(@"Failed to render audio unit. Error=%ld", (long)result);
  }
  return result;
}

OSStatus VoiceProcessingAudioUnit::OnGetPlayoutData(
    void* in_ref_con,
    AudioUnitRenderActionFlags* flags,
    const AudioTimeStamp* time_stamp,
    UInt32 bus_number,
    UInt32 num_frames,
    AudioBufferList* io_data) {
  VoiceProcessingAudioUnit* audio_unit =
      static_cast<VoiceProcessingAudioUnit*>(in_ref_con);
  return audio_unit->NotifyGetPlayoutData(flags, time_stamp, bus_number,
                                          num_frames, io_data);
}

OSStatus VoiceProcessingAudioUnit::OnDeliverRecordedData(
    void* in_ref_con,
    AudioUnitRenderActionFlags* flags,
    const AudioTimeStamp* time_stamp,
    UInt32 bus_number,
    UInt32 num_frames,
    AudioBufferList* io_data) {
  VoiceProcessingAudioUnit* audio_unit =
      static_cast<VoiceProcessingAudioUnit*>(in_ref_con);
  return audio_unit->NotifyDeliverRecordedData(flags, time_stamp, bus_number,
                                               num_frames, io_data);
}

OSStatus VoiceProcessingAudioUnit::NotifyGetPlayoutData(
    AudioUnitRenderActionFlags* flags,
    const AudioTimeStamp* time_stamp,
    UInt32 bus_number,
    UInt32 num_frames,
    AudioBufferList* io_data) {
  return observer_->OnGetPlayoutData(flags, time_stamp, bus_number, num_frames,
                                     io_data);
}

OSStatus VoiceProcessingAudioUnit::NotifyDeliverRecordedData(
    AudioUnitRenderActionFlags* flags,
    const AudioTimeStamp* time_stamp,
    UInt32 bus_number,
    UInt32 num_frames,
    AudioBufferList* io_data) {
  return observer_->OnDeliverRecordedData(flags, time_stamp, bus_number,
                                          num_frames, io_data);
}

AudioStreamBasicDescription VoiceProcessingAudioUnit::GetFormat(
    Float64 sample_rate) const {
  // Set the application formats for input and output:
  // - use same format in both directions
  // - avoid resampling in the I/O unit by using the hardware sample rate
  // - linear PCM => noncompressed audio data format with one frame per packet
  // - no need to specify interleaving since only mono is supported
  AudioStreamBasicDescription format = {0};
  RTC_DCHECK_EQ(1, kRTCAudioSessionPreferredNumberOfChannels);
  format.mSampleRate = sample_rate;
  format.mFormatID = kAudioFormatLinearPCM;
  format.mFormatFlags =
      kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  format.mBytesPerPacket = kBytesPerSample;
  format.mFramesPerPacket = 1;  // uncompressed.
  format.mBytesPerFrame = kBytesPerSample;
  format.mChannelsPerFrame = kRTCAudioSessionPreferredNumberOfChannels;
  format.mBitsPerChannel = 8 * kBytesPerSample;
  return format;
}

void VoiceProcessingAudioUnit::DisposeAudioUnit() {
  if (vpio_unit_) {
    switch (state_) {
      case kStarted:
        Stop();
        // Fall through.
        FALLTHROUGH();
      case kInitialized:
        Uninitialize();
        break;
      case kUninitialized:
        FALLTHROUGH();
      case kInitRequired:
        break;
    }

    RTCLog(@"Disposing audio unit.");
    OSStatus result = AudioComponentInstanceDispose(vpio_unit_);
    if (result != noErr) {
      RTCLogError(@"AudioComponentInstanceDispose failed. Error=%ld.",
                  (long)result);
    }
    vpio_unit_ = nullptr;
  }
}

}  // namespace dii_media_kit
