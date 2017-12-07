/**
 * Dump the width of Unicode code points as determined by wcwidth(3). Each line
 * of output consists of three numbers. From left to right, the numbers
 * represent the width, the first value in a range of code points that have
 * that width and the last value in the range.
 *
 * Author: Eric Pruitt (https://www.codevat.com)
 * License: 2-Clause BSD (http://opensource.org/licenses/BSD-2-Clause)
 * Make: c99 -o $@ $?
 */
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif

#include <locale.h>
#include <stdio.h>
#include <wchar.h>

#define IS_BOUNDARY(x) ( \
    /* Some of these values are redundant but simplifying the expression */ \
    /* would make the intent / purpose of these less clear. */ \
    (/* First character composed of 2 bytes in UTF-8: */ (x) == 0x80) || \
    (/* First character composed of 3 bytes in UTF-8: */ (x) == 0x800) || \
    (/* First character composed of 4 bytes in UTF-8: */ (x) == 0x10000) || \
    (/* Last Unicode code point: */ (x) == 0x10FFFF) || \
    \
    (/* Surrogates: */ (x) == 0xD800 || ((x) - 1) == 0xDFFF) || \
    (/* Private Use Area (PUA): */ (x) == 0xE000 || ((x) - 1) == 0xF8FF) || \
    (/* Supplemental PUA A: */ (x) == 0xF0000 || ((x) - 1) == 0xFFFFD) || \
    (/* Supplemental PUA B: */ (x) == 0x100000 || ((x) - 1) == 0x10FFFD) \
)

int main()
{
    int width;

    int previous_width = 0;

    setlocale(LC_ALL, "C.UTF-8");

    for (wchar_t i = 0, start = 0, end = 0; i <= 0x10FFFF; i++) {
        width = wcwidth(i);

        if (!i || width != previous_width || IS_BOUNDARY(i)) {
            if (i && printf("%d %d %d\n", previous_width, start, end) < 0) {
                perror("printf");
                return 1;
            }

            start = i;
            previous_width = width;
        }

        end = i;
    }

    return 0;
}
