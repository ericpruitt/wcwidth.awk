/**
 * Read data from standard input and write the result of calling wcswidth(3) on
 * each line to standard output.
 *
 * Author: Eric Pruitt (https://www.codevat.com)
 * License: 2-Clause BSD (http://opensource.org/licenses/BSD-2-Clause)
 * Make: c99 -o $@ $?
 */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif

#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include <limits.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

int main(int argc, char **argv)
{
    size_t count;
    ssize_t length;
    char *line;
    int width;

    wchar_t runes[LINE_MAX];
    size_t sizeof_line = LINE_MAX;

    if (argc > 1) {
        fprintf(stderr, "Usage: %s < FILENAME\n", argv[0]);
        return 1;
    }

    if (!setlocale(LC_ALL, "C.UTF-8")) {
        perror("setlocale failed");
        return 1;
    }

    if (!(line = malloc(sizeof_line))) {
        perror("malloc");
        return 1;
    }

    while ((length = getline(&line, &sizeof_line, stdin)) >= 0) {
        width = -1;

        if ((count = mbstowcs(runes, line, sizeof(runes))) != (size_t) -1) {
            width = wcswidth(runes, count - 1);
        }

        if (printf("%i\n", width) < 0) {
            perror("printf");
            return 1;
        }
    }

    if (ferror(stdin)) {
        perror("getline");
        return 1;
    }

    return 0;
}
