/* Independent libjpeg inspection of every original photo block, including partial MCUs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>

#define REQUIRE(condition) do { if (!(condition)) { \
    fprintf(stderr, "Coefficient check failed at line %d: %s\n", __LINE__, #condition); exit(1); \
} } while (0)

int main(int argc, char **argv) {
    REQUIRE(argc == 5);
    struct jpeg_decompress_struct source = {0}, output = {0};
    struct jpeg_error_mgr source_error, output_error;
    source.err = jpeg_std_error(&source_error);
    output.err = jpeg_std_error(&output_error);
    jpeg_create_decompress(&source);
    jpeg_create_decompress(&output);
    FILE *input_file = fopen(argv[1], "rb"), *output_file = fopen(argv[2], "rb");
    REQUIRE(input_file && output_file);
    jpeg_stdio_src(&source, input_file);
    jpeg_stdio_src(&output, output_file);
    jpeg_read_header(&source, TRUE);
    jpeg_read_header(&output, TRUE);
    REQUIRE(source.num_components == output.num_components);
    REQUIRE(source.jpeg_color_space == output.jpeg_color_space);
    REQUIRE(source.progressive_mode == output.progressive_mode);
    for (int t = 0; t < NUM_QUANT_TBLS; ++t) {
        REQUIRE((source.quant_tbl_ptrs[t] == NULL) == (output.quant_tbl_ptrs[t] == NULL));
        if (source.quant_tbl_ptrs[t])
            REQUIRE(memcmp(source.quant_tbl_ptrs[t]->quantval, output.quant_tbl_ptrs[t]->quantval,
                           sizeof(source.quant_tbl_ptrs[t]->quantval)) == 0);
    }
    int x = atoi(argv[3]), y = atoi(argv[4]);
    int mcu_width = source.max_h_samp_factor * DCTSIZE, mcu_height = source.max_v_samp_factor * DCTSIZE;
    REQUIRE(x >= 0 && y >= 0 && x % mcu_width == 0 && y % mcu_height == 0);
    jvirt_barray_ptr *before = jpeg_read_coefficients(&source), *after = jpeg_read_coefficients(&output);
    unsigned long blocks = 0;
    for (int c = 0; c < source.num_components; ++c) {
        jpeg_component_info *a = &source.comp_info[c], *b = &output.comp_info[c];
        REQUIRE(a->h_samp_factor == b->h_samp_factor && a->v_samp_factor == b->v_samp_factor);
        REQUIRE(a->quant_tbl_no == b->quant_tbl_no);
        JDIMENSION offset_x = x / mcu_width * a->h_samp_factor;
        JDIMENSION offset_y = y / mcu_height * a->v_samp_factor;
        REQUIRE(offset_x + a->width_in_blocks <= b->width_in_blocks);
        REQUIRE(offset_y + a->height_in_blocks <= b->height_in_blocks);
        for (JDIMENSION row = 0; row < a->height_in_blocks; ++row) {
            JBLOCKARRAY original = (*source.mem->access_virt_barray)((j_common_ptr)&source, before[c], row, 1, FALSE);
            JBLOCKARRAY composed = (*output.mem->access_virt_barray)((j_common_ptr)&output, after[c], offset_y + row, 1, FALSE);
            REQUIRE(memcmp(original[0], composed[0] + offset_x, a->width_in_blocks * sizeof(JBLOCK)) == 0);
            blocks += a->width_in_blocks;
        }
    }
    printf("%lu photo blocks preserved\n", blocks);
    jpeg_destroy_decompress(&source);
    jpeg_destroy_decompress(&output);
    fclose(input_file);
    fclose(output_file);
    return 0;
}
