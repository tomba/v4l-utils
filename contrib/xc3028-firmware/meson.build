xc3028_firmware_sources = files(
    'extract_head.h',
    'firmware-tool.c',
    'standards.c',
    'standards.h',
    'tuner-xc2028-types.h',
)

xc3028_firmware = executable('xc3028-firmware',
                             xc3028_firmware_sources,
                             include_directories : v4l2_utils_incdir)
