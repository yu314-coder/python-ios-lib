#ifndef OFORT_FIXED_FORM_H
#define OFORT_FIXED_FORM_H

typedef struct {
    int fixed_line_length; /* default 72; <=0 means unlimited */
    int preserve_comments;
    int tab_form;
} OfortFixedFormOptions;

char *ofort_fixed_to_free(const char *source,
                          const char *filename,
                          const OfortFixedFormOptions *options,
                          char **error_message);

#endif
