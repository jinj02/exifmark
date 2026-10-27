#ifndef EXIFMARK_JPEG_H
#define EXIFMARK_JPEG_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    int width;
    int height;
    int mcu_width;
    int mcu_height;
} ExifmarkJPEGInfo;

int exifmark_jpeg_read_info(const char *input, ExifmarkJPEGInfo *info,
                            char *error, size_t error_size);

/* RGBX contains the new canvas regions in the JPEG's stored orientation.
 * All original quantized coefficients are copied at the aligned photo offset.
 * The source quantization tables and component sampling are never rescaled.
 */
int exifmark_jpeg_compose(const char *input, const char *output,
                          const uint8_t *rgbx, int width, int height, size_t stride,
                          int photo_x, int photo_y, char *error, size_t error_size);

#endif
