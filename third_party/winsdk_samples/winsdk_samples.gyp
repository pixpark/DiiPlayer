# Copyright (c) 2012 The devzhaoyou@dii_media project authors. All Rights Reserved.
#
# Use of this source code is governed by a BSD-style license
# that can be found in the LICENSE file in the root of the source
# tree. An additional intellectual property rights grant can be found
# in the file PATENTS.  All contributing project authors may
# be found in the AUTHORS file in the root of the source tree.

{
  'targets': [
    {
      'target_name': 'directshow_baseclasses',
      'type': 'static_library',
      'variables': {
        'baseclasses_dir%':
          'src/Samples/multimedia/directshow/baseclasses',
      },
      'defines!': [
        'NOMINMAX',
      ],
      'include_dirs': ['<(baseclasses_dir)',],
      'direct_dependent_settings': {
        'include_dirs': ['<(baseclasses_dir)',],
      },
      'sources': [
        '<(baseclasses_dir)/amextra.cpp',
        '<(baseclasses_dir)/amextra.h',
        '<(baseclasses_dir)/amfilter.cpp',
        '<(baseclasses_dir)/amfilter.h',
        '<(baseclasses_dir)/amvideo.cpp',
        '<(baseclasses_dir)/cache.h',
        '<(baseclasses_dir)/combase.cpp',
        '<(baseclasses_dir)/combase.h',
        '<(baseclasses_dir)/cprop.cpp',
        '<(baseclasses_dir)/cprop.h',
        '<(baseclasses_dir)/ctlutil.cpp',
        '<(baseclasses_dir)/ctlutil.h',
        '<(baseclasses_dir)/ddmm.cpp',
        '<(baseclasses_dir)/ddmm.h',
        '<(baseclasses_dir)/dllentry.cpp',
        '<(baseclasses_dir)/dllsetup.cpp',
        '<(baseclasses_dir)/dllsetup.h',
        '<(baseclasses_dir)/fourcc.h',
        '<(baseclasses_dir)/measure.h',
        '<(baseclasses_dir)/msgthrd.h',
        '<(baseclasses_dir)/mtype.cpp',
        '<(baseclasses_dir)/mtype.h',
        '<(baseclasses_dir)/outputq.cpp',
        '<(baseclasses_dir)/outputq.h',
        '<(baseclasses_dir)/pstream.cpp',
        '<(baseclasses_dir)/pstream.h',
        '<(baseclasses_dir)/pullpin.cpp',
        '<(baseclasses_dir)/pullpin.h',
        '<(baseclasses_dir)/refclock.cpp',
        '<(baseclasses_dir)/refclock.h',
        '<(baseclasses_dir)/reftime.h',
        '<(baseclasses_dir)/renbase.cpp',
        '<(baseclasses_dir)/renbase.h',
        '<(baseclasses_dir)/schedule.cpp',
        '<(baseclasses_dir)/seekpt.cpp',
        '<(baseclasses_dir)/seekpt.h',
        '<(baseclasses_dir)/source.cpp',
        '<(baseclasses_dir)/source.h',
        '<(baseclasses_dir)/streams.h',
        '<(baseclasses_dir)/strmctl.cpp',
        '<(baseclasses_dir)/strmctl.h',
        '<(baseclasses_dir)/sysclock.cpp',
        '<(baseclasses_dir)/sysclock.h',
        '<(baseclasses_dir)/transfrm.cpp',
        '<(baseclasses_dir)/transfrm.h',
        '<(baseclasses_dir)/transip.cpp',
        '<(baseclasses_dir)/transip.h',
        '<(baseclasses_dir)/videoctl.cpp',
        '<(baseclasses_dir)/videoctl.h',
        '<(baseclasses_dir)/vtrans.cpp',
        '<(baseclasses_dir)/vtrans.h',
        '<(baseclasses_dir)/winctrl.cpp',
        '<(baseclasses_dir)/winctrl.h',
        '<(baseclasses_dir)/winutil.cpp',
        '<(baseclasses_dir)/winutil.h',
        '<(baseclasses_dir)/wxdebug.cpp',
        '<(baseclasses_dir)/wxdebug.h',
        '<(baseclasses_dir)/wxlist.cpp',
        '<(baseclasses_dir)/wxlist.h',
        '<(baseclasses_dir)/wxutil.cpp',
        '<(baseclasses_dir)/wxutil.h',
      ],
      'conditions': [
        ['clang==1', {
          'msvs_settings': {
            'VCCLCompilerTool': {
              'AdditionalOptions': [
                # Disable warnings failing when compiling with Clang on Windows.
                # https://bugs.chromium.org/p/webrtc/issues/detail?id=5366
                '-Wno-comment',
                '-Wno-delete-non-virtual-dtor',
                '-Wno-ignored-attributes',
                '-Wno-logical-op-parentheses',
                '-Wno-non-pod-varargs',
                '-Wno-microsoft-extra-qualification',
                '-Wno-missing-braces',
                '-Wno-overloaded-virtual',
                '-Wno-parentheses',
                '-Wno-reorder',
                '-Wno-string-conversion',
                '-Wno-tautological-constant-out-of-range-compare',
                '-Wno-unused-private-field',
                '-Wno-writable-strings',
              ],
            },
          },
          'direct_dependent_settings': {
            'msvs_settings': {
              'VCCLCompilerTool': {
                'AdditionalOptions': [
                  # Disable warnings failing when compiling with Clang on Windows.
                  # https://bugs.chromium.org/p/webrtc/issues/detail?id=5366
                  '-Wno-ignored-qualifiers',
                ],
              },
            },
          },
        },],
      ],  # conditions.
    },
  ],
}
