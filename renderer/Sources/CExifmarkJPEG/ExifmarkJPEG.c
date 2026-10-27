#include "ExifmarkJPEG.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <errno.h>
#include <jpeglib.h>

typedef struct {
    struct jpeg_error_mgr manager;
    jmp_buf jump;
    char *message;
    size_t capacity;
} JPEGError;

/* Heap storage remains defined after a libjpeg error longjmps to the caller. */
typedef struct {
    JPEGError error;
    struct jpeg_decompress_struct photo, canvas;
    struct jpeg_compress_struct encoder, writer;
    FILE *input, *output;
    unsigned char *canvas_data;
    unsigned long canvas_size;
} JPEGState;

static void fail(JPEGState *state, const char *message) {
    if (state->error.capacity) snprintf(state->error.message, state->error.capacity, "%s", message);
    longjmp(state->error.jump, 1);
}

static void jpeg_error(j_common_ptr codec) {
    JPEGError *error = (JPEGError *)codec->err;
    char message[JMSG_LENGTH_MAX];
    (*codec->err->format_message)(codec, message);
    if (error->capacity) snprintf(error->message, error->capacity, "%s", message);
    longjmp(error->jump, 1);
}

static void jpeg_message(j_common_ptr codec, int level) {
    /* Reject truncated/corrupt input before missing photo blocks are synthesized. */
    if (level < 0) jpeg_error(codec);
}

static JPEGState *create_state(char *message, size_t capacity) {
    if (capacity) message[0] = 0;
    JPEGState *state = calloc(1, sizeof(*state));
    if (!state) {
        if (capacity) snprintf(message, capacity, "Insufficient memory for JPEG composition.");
        return NULL;
    }
    jpeg_std_error(&state->error.manager);
    state->error.manager.error_exit = jpeg_error;
    state->error.manager.emit_message = jpeg_message;
    state->error.message = message;
    state->error.capacity = capacity;
    state->photo.err = state->canvas.err = state->encoder.err = state->writer.err = &state->error.manager;
    return state;
}

static void destroy_state(JPEGState *state) {
    if (state->writer.mem) jpeg_destroy_compress(&state->writer);
    if (state->encoder.mem) jpeg_destroy_compress(&state->encoder);
    if (state->canvas.mem) jpeg_destroy_decompress(&state->canvas);
    if (state->photo.mem) jpeg_destroy_decompress(&state->photo);
    if (state->input) fclose(state->input);
    if (state->output) fclose(state->output);
    free(state->canvas_data);
    free(state);
}

static void read_photo(JPEGState *state, const char *path, int markers) {
    state->input = fopen(path, "rb");
    if (!state->input) fail(state, strerror(errno));
    jpeg_create_decompress(&state->photo);
    jpeg_stdio_src(&state->photo, state->input);
    if (markers) {
        for (int i = 0; i < 16; ++i) jpeg_save_markers(&state->photo, JPEG_APP0 + i, 0xffff);
        jpeg_save_markers(&state->photo, JPEG_COM, 0xffff);
    }
    jpeg_read_header(&state->photo, TRUE);
    if (state->photo.data_precision != 8 ||
        (state->photo.jpeg_color_space != JCS_YCbCr && state->photo.jpeg_color_space != JCS_RGB &&
         state->photo.jpeg_color_space != JCS_GRAYSCALE))
        fail(state, "Coefficient composition requires an 8-bit RGB or grayscale JPEG.");
}

static void set_dimensions(j_compress_ptr codec, int width, int height) {
    codec->image_width = width;
    codec->image_height = height;
#if JPEG_LIB_VERSION >= 70
    codec->jpeg_width = width;
    codec->jpeg_height = height;
#endif
}

int exifmark_jpeg_read_info(const char *input, ExifmarkJPEGInfo *info,
                            char *error, size_t error_size) {
    JPEGState *state = create_state(error, error_size);
    if (!state) return 0;
    if (setjmp(state->error.jump)) { destroy_state(state); return 0; }
    read_photo(state, input, 0);
    info->width = (int)state->photo.image_width;
    info->height = (int)state->photo.image_height;
    info->mcu_width = state->photo.max_h_samp_factor * DCTSIZE;
    info->mcu_height = state->photo.max_v_samp_factor * DCTSIZE;
    destroy_state(state);
    return 1;
}

int exifmark_jpeg_compose(const char *input, const char *output,
                          const uint8_t *rgbx, int width, int height, size_t stride,
                          int photo_x, int photo_y, char *error, size_t error_size) {
    JPEGState *state = create_state(error, error_size);
    if (!state) return 0;
    if (setjmp(state->error.jump)) { destroy_state(state); return 0; }
    read_photo(state, input, 1);
    struct jpeg_decompress_struct *photo = &state->photo, *canvas = &state->canvas;
    int mcu_width = photo->max_h_samp_factor * DCTSIZE;
    int mcu_height = photo->max_v_samp_factor * DCTSIZE;
    if (!rgbx || width <= 0 || height <= 0 || width > JPEG_MAX_DIMENSION || height > JPEG_MAX_DIMENSION ||
        stride < (size_t)width * 4 || photo_x < 0 || photo_y < 0 ||
        photo_x % mcu_width || photo_y % mcu_height ||
        (size_t)photo_x + photo->image_width > (size_t)width ||
        (size_t)photo_y + photo->image_height > (size_t)height)
        fail(state, "Invalid JPEG canvas or unaligned photo offset.");
    jvirt_barray_ptr *photo_blocks = jpeg_read_coefficients(photo);

    /* Compress only the drawn border/footer canvas with the exact upstream tables.
     * jpeg_set_quality() and jpegtran's quantization-table reconciliation are unused.
     */
    jpeg_create_compress(&state->encoder);
    jpeg_mem_dest(&state->encoder, &state->canvas_data, &state->canvas_size);
    jpeg_copy_critical_parameters(photo, &state->encoder);
    set_dimensions(&state->encoder, width, height);
    state->encoder.in_color_space = JCS_EXT_RGBX;
    state->encoder.input_components = 4;
    state->encoder.optimize_coding = TRUE;
    jpeg_start_compress(&state->encoder, TRUE);
    while (state->encoder.next_scanline < state->encoder.image_height) {
        JSAMPROW row = (JSAMPROW)(rgbx + state->encoder.next_scanline * stride);
        jpeg_write_scanlines(&state->encoder, &row, 1);
    }
    jpeg_finish_compress(&state->encoder);
    jpeg_destroy_compress(&state->encoder);

    jpeg_create_decompress(canvas);
    jpeg_mem_src(canvas, state->canvas_data, state->canvas_size);
    jpeg_read_header(canvas, TRUE);
    jvirt_barray_ptr *canvas_blocks = jpeg_read_coefficients(canvas);
    for (int ci = 0; ci < photo->num_components; ++ci) {
        jpeg_component_info *component = &photo->comp_info[ci];
        JDIMENSION x = photo_x / mcu_width * component->h_samp_factor;
        JDIMENSION y = photo_y / mcu_height * component->v_samp_factor;
        for (JDIMENSION row = 0; row < component->height_in_blocks; ++row) {
            JBLOCKARRAY source = (*photo->mem->access_virt_barray)(
                (j_common_ptr)photo, photo_blocks[ci], row, 1, FALSE);
            JBLOCKARRAY target = (*canvas->mem->access_virt_barray)(
                (j_common_ptr)canvas, canvas_blocks[ci], y + row, 1, TRUE);
            memcpy(target[0] + x, source[0], component->width_in_blocks * sizeof(JBLOCK));
        }
    }

    state->output = fopen(output, "wb");
    if (!state->output) fail(state, strerror(errno));
    jpeg_create_compress(&state->writer);
    jpeg_stdio_dest(&state->writer, state->output);
    jpeg_copy_critical_parameters(photo, &state->writer);
    set_dimensions(&state->writer, width, height);
    state->writer.optimize_coding = TRUE;
    if (photo->progressive_mode) jpeg_simple_progression(&state->writer);
    jpeg_write_coefficients(&state->writer, canvas_blocks);
    for (jpeg_saved_marker_ptr marker = photo->marker_list; marker; marker = marker->next) {
        if (state->writer.write_JFIF_header && marker->marker == JPEG_APP0 && marker->data_length >= 5 &&
            memcmp(marker->data, "JFIF\0", 5) == 0) continue;
        if (state->writer.write_Adobe_marker && marker->marker == JPEG_APP0 + 14 && marker->data_length >= 5 &&
            memcmp(marker->data, "Adobe", 5) == 0) continue;
        jpeg_write_marker(&state->writer, marker->marker, marker->data, marker->data_length);
    }
    jpeg_finish_compress(&state->writer);
    jpeg_finish_decompress(canvas);
    jpeg_finish_decompress(photo);
    int close_result = fclose(state->output);
    state->output = NULL;
    if (close_result) fail(state, strerror(errno));
    destroy_state(state);
    return 1;
}
