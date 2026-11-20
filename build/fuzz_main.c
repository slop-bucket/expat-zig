#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
  if (argc <= 1) {
    const uint8_t empty = 0;
    LLVMFuzzerTestOneInput(&empty, 0);
    return 0;
  }
  for (int i = 1; i < argc; ++i) {
    FILE *f = fopen(argv[i], "rb");
    if (!f) {
      perror(argv[i]);
      return 1;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
      fclose(f);
      return 1;
    }
    long len = ftell(f);
    if (len < 0) {
      fclose(f);
      return 1;
    }
    rewind(f);
    uint8_t *buf = len > 0 ? malloc((size_t)len) : NULL;
    if (len > 0 && !buf) {
      fclose(f);
      return 1;
    }
    size_t n = len > 0 ? fread(buf, 1, (size_t)len, f) : 0;
    fclose(f);
    LLVMFuzzerTestOneInput(buf ? buf : (const uint8_t *)"", n);
    free(buf);
  }
  return 0;
}
