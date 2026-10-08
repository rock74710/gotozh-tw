#ifndef GOTOZH_OPENCC_H
#define GOTOZH_OPENCC_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GotozhOpenCC GotozhOpenCC;

GotozhOpenCC *gotozh_opencc_create(const char *config_path,
                                   const char *dictionary_path);
void gotozh_opencc_destroy(GotozhOpenCC *converter);
char *gotozh_opencc_inspect(GotozhOpenCC *converter, const char *input,
                            size_t input_length, size_t *output_length);
void gotozh_opencc_free(void *buffer);
const char *gotozh_opencc_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
