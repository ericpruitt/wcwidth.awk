#!/usr/bin/awk -f

# This AWK library provides 4 functions for working with UTF-8 strings:
#
# - wcscolumns(string): Returns the number of colums needed to display a
#   string, but unlike "wcswidth" and "wcwidth" which are written to function
#   identically to their POSIX counterparts, this function always returns a
#   value greater than or equal to 0.
# - wcsexpand(string, tab_stop): Expand tabs to spaces in a wide
#   character-aware manner.
# - wcstruncate(string, columns): Returns a string truncated to span a limited
#   number of columns.
# - wcswidth(string): Returns the number of columns needed to display a string.
# - wcwidth(character): Returns the number of columns needed to display a
#   character.
#
# More detailed explanations of how these functions work can be found in
# comments immediately preceding their definitions.
#
# To minimize the likelihood of name conflicts, all global variables used by
# this code begin with "WCWIDTH_...", all internal functions begin with
# "_wcwidth_...", and all arguments / function-local variables that are not
# arguments begin with a "_". The library will work regardless of when it's
# loaded relative to the scripts that use it, but one "reference to
# uninitialized variable" warning will be generated by GAWK's linter if the
# library is loaded after its caller AND if the caller uses a library function
# in a "BEGIN" block.
#
# Author: Eric Pruitt (https://www.codevat.com)
# License: 2-Clause BSD (http://opensource.org/licenses/BSD-2-Clause)
# Project Page: https://github.com/ericpruitt/wcwidth.awk

#                                     ---

# Determine the number of columns needed to display a string. This function
# differs from the "wcswidth" function in its handling of non-printable
# characters; instead of making the function abort and immediately return -1,
# non-printable ASCII characters are ignored while all others are treated as
# having a width of 1 because they will typically be rendered as a
# single-column ".notdef" glyph
# (https://www.microsoft.com/typography/otspec/recom.htm).
#
# Arguments:
# - _str: A string of any length. In AWK interpreters that are not multi-byte
#   safe, this argument is interpreted as a UTF-8 encoded string.
#
# Returns: The number of columns needed to display the string. This value will
# always be greater than or equal to 0.
#
function wcscolumns(_str,    _length, _max, _min, _offset, _rl, _rs, _total,
  _wchar, _width) {

    _total = 0

    if (!WCWIDTH_INITIALIZED) {
        _wcwidth_initialize_library()
    }

    if (WCWIDTH_MULTIBYTE_SAFE) {
        # Optimization for Latin and whatever else I could fit on one line.
        _total = length(_str)
        gsub(/[ -~ -¬®-˿Ͱ-ͷͺ-Ϳ΄-ΊΌΎ-ΡΣ-҂Ҋ-ԯԱ-Ֆՙ-՟ա-և։֊־׀׃׆א-תװ-״]+/, "", _str)

        if (!_str) {
            return _total
        }

        # Optimization for common wide CJK characters. Based on data from
        # http://corpus.leeds.ac.uk/list.html, this covers ~95% of all
        # characters used on Chinese and Japanese sites.
        _length = length(_str)
        _total -= _length
        gsub(/[가-힣一-鿕！-｠ぁ-ゖ゛-ヿ]+/, "", _str)
        _total += (_length - length(_str)) * 2

        _offset = 1
    }

    if (!_str) {
        return _total
    }

    _rs = RSTART
    _rl = RLENGTH

    while (1) {
        if (!WCWIDTH_MULTIBYTE_SAFE) {
            # Optimization for ASCII text.
            _total += length(_str)
            sub(/^[\040-\176]+/, "", _str)

            if (!_str) {
                break
            }

            _total -= length(_str)

            # Optimization for a subset of the "Latin and whatever" characters
            # mentioned above. Experimenting showed that performance in MAWK
            # eventually begins drop off rapidly for the French corpus as the
            # regex complexity increases.
            if (match(_str, "^([\303-\313][\200-\277][ -~]*)+")) {
                _wchar = substr(_str, RSTART, RLENGTH)
                _total += gsub(/[^ -~]/, "", _wchar) / 2 + length(_wchar)

                if (RLENGTH == length(_str)) {
                    break
                }

                _str = substr(_str, RSTART + RLENGTH)
            }

            # Optimization for common wide CJK characters. The regular
            # expression used here covers the exact same range as the regex for
            # multi-byte safe interpreters.
            if (match(_str, WCWIDTH_WIDE_CJK_RUNES_REGEX)) {
                _wchar = substr(_str, RSTART, RLENGTH)
                _total += gsub(/[^ -~]/, "", _wchar) / 3 * 2 + length(_wchar)

                if (RLENGTH == length(_str)) {
                    break
                }

                _str = substr(_str, RSTART + RLENGTH)
            }

            match(_str, WCWIDTH_UTF8_ANCHORED_RUNE_REGEX)
            _wchar = substr(_str, RSTART, RLENGTH)
            _str = RLENGTH == length(_str) ? "" : substr(_str, RLENGTH + 1)
        } else if (_offset > length(_str)) {
            break
        } else {
            _wchar = substr(_str, _offset++, 1)
        }

        if (_wchar in WCWIDTH_CACHE) {
            _width = WCWIDTH_CACHE[_wchar]
        } else if (!WCWIDTH_TABLE_LENGTH) {
            _width = _wcwidth_unpack_data(_wchar)
        } else {
            # Do a binary search to find the width of the character.
            _min = 0
            _max = WCWIDTH_TABLE_LENGTH - 1
            _width = -1

            do {
                if (_wchar < WCWIDTH_RANGE_START[WCWIDTH_SEARCH_CURSOR]) {
                    _max = WCWIDTH_SEARCH_CURSOR - 1
                } else if (_wchar > WCWIDTH_RANGE_END[WCWIDTH_SEARCH_CURSOR]) {
                    _min = WCWIDTH_SEARCH_CURSOR + 1
                } else {
                    _width = WCWIDTH_RANGE_WIDTH[WCWIDTH_SEARCH_CURSOR]
                    break
                }
                WCWIDTH_SEARCH_CURSOR = int((_min + _max) / 2)
            } while (_min <= _max)

            WCWIDTH_CACHE[_wchar] = _width
        }

        if (_width != -1) {
            _total += _width
        } else if (WCWIDTH_POSIX_MODE) {
            _total = -1
            break
        } else {
            # Ignore non-printable ASCII characters.
            _total += length(_wchar) == 1 ? _wchar > "\177" : 1
        }
    }

    RLENGTH = _rl
    RSTART = _rs
    return _total
}

# Expand tabs to spaces in a wide character-aware manner. Calculations done by
# this function assume the first character of the string is the first character
# of the line or the first character following a tab.
#
# Arguments:
# - _str: The string to expand.
# - _tab_stop: The maximum width of tabs. This must be an integer greater than
#   zero.
#
# Returns: A string with all tabs replaced with spaces.
#
function wcsexpand(_str, _tab_stop,    _column, _mark, _tab_index, _tab_width)
{
    _column = 0

    # An alternate implementation of this function used split(..., ..., "\t"),
    # but that approach was generally slower.
    for (_mark = 0; (_tab_index = index(_str, "\t")); _mark = _tab_index - 1) {
        _column += wcscolumns(substr(_str, _mark + 1, _tab_index - _mark - 1))
        _tab_width = _tab_stop - _column % _tab_stop
        sub(/\t/, sprintf("%*s", _tab_width, ""), _str)
    }

    return _str
}

# Truncate a string so that it spans a limited number of columns.
#
# Arguments:
# - _str: A string of any length. In AWK interpreters that are not multi-byte
#   safe, this argument is interpreted as a UTF-8 encoded string.
# - _columns: Maximum number of columns the resulting text may span.
#
# Returns: "_str" truncated as needed.
#
function wcstruncate(_str, _columns,    _result, _rl, _rs, _wchar, _width)
{
    _columns = 0 + _columns

    # Use "substr" for strings composed of 1-column characters.
    if (_str !~ /[^\040-\176]/ || (WCWIDTH_MULTIBYTE_SAFE &&
      _str !~ /[^ -~ -¬®-˿Ͱ-ͷͺ-Ϳ΄-ΊΌΎ-ΡΣ-҂Ҋ-ԯԱ-Ֆՙ-՟ա-և։֊־׀׃׆א-תװ-״]/)) {
        return length(_str) > _columns ? substr(_str, 1, _columns) : _str
    }

    # The individual widths of characters need not be checked when
    # `(length(_str) * 2) <= _columns` because a character may only span 2
    # columns at most.
    if ((WCWIDTH_MULTIBYTE_SAFE && (length(_str) * 2) <= _columns) ||
     (!WCWIDTH_MULTIBYTE_SAFE && WCWIDTH_INTERVAL_EXPRESSIONS_SUPPORTED &&
      _str ~ ("^" WCWIDTH_UTF8_RUNE_REGEX "{," int(_columns / 2) "}$"))) {
        return _str
    }

    _rl = RLENGTH
    _rs = RSTART
    _result = ""

    while (_columns > 0 && _str) {
        if (_str ~ /^[\040-\176]/) {
            _wchar = substr(_str, 1, 1)
            _str = substr(_str, 2)
            _width = 1
        } else if (WCWIDTH_MULTIBYTE_SAFE) {
            _wchar = substr(_str, 1, 1)
            _str = substr(_str, 2)
            _width = wcscolumns(_wchar)
        } else if (match(_str, WCWIDTH_UTF8_RUNE_REGEX)) {
            _wchar = substr(_str, RSTART, RLENGTH)
            _str = substr(_str, RSTART + RLENGTH)
            _width = wcscolumns(_wchar)
        }

        _columns -= _width

        if (_columns >= 0) {
            _result = _result _wchar
        }
    }

    RLENGTH = _rl
    RSTART = _rs
    return _result
}

# A reimplementation of the POSIX function of the same name to determine the
# number of columns needed to display a string.
#
# Arguments:
# - _str: A string of any length. In AWK interpreters that are not multi-byte
#   safe, this argument is interpreted as a UTF-8 encoded string.
#
# Returns: The number of columns needed to display the string is returned if
# all of character are printable and -1 if any are not.
#
function wcswidth(_str,    _width)
{
    WCWIDTH_POSIX_MODE = 1
    _width = wcscolumns(_str)
    WCWIDTH_POSIX_MODE = 0
    return _width
}

# A reimplementation of the POSIX function of the same name to determine the
# number of columns needed to display a single character.
#
# Arguments:
# - _wchar: A single character. In AWK interpreters that are not multi-byte
#   safe, this argument may consist of multiple characters that together
#   represent a single UTF-8 encoded code point.
#
# Returns: The number of columns needed to display the character if it is
# printable and -1 if it is not. If the argument does not contain exactly one
# character (or UTF-8 code point), -1 is returned.
#
function wcwidth(_wchar,    _result, _rl, _rs)
{
    _result = -1

    if (!_wchar) {
        # An empty string is an invalid argument.
    } else if (WCWIDTH_MULTIBYTE_SAFE && length(_wchar) == 1) {
        _result = wcswidth(_wchar)
    } else if (!WCWIDTH_MULTIBYTE_SAFE) {
        _rs = RSTART
        _rl = RLENGTH

        if (match(_wchar, WCWIDTH_UTF8_ANCHORED_RUNE_REGEX) &&
          RLENGTH == length(_wchar)) {
            _result = wcswidth(_wchar)
        }

        RSTART = _rs
        RLENGTH = _rl
    }

    return _result
}

#                                     ---
# The functions beyond this point are intended only for internal use and should
# be treated as implementation details.
#                                     ---

BEGIN {
    # Silence "defined but never called directly" warnings generated when using
    # GAWK's linter.
    if (0) {
        wcscolumns()
        wcsexpand()
        wcstruncate()
        wcswidth()
        wcwidth()
    }

    WCWIDTH_POSIX_MODE = 0
    _wcwidth_initialize_library()
}

# Initialize global state used by this library.
#
function _wcwidth_initialize_library(    _entry, _nul)
{
    # This method of checking for initialization will not generate a "reference
    # to uninitialized variable" when using GAWK's linter.
    for (_entry in WCWIDTH_CACHE) {
        return
    }

    split("X", WCWIDTH_CACHE)

    WCWIDTH_INTERVAL_EXPRESSIONS_SUPPORTED = "XXXX" ~ /^X{,4}$/
    WCWIDTH_MULTIBYTE_SAFE = length("宽") == 1

    if (!WCWIDTH_MULTIBYTE_SAFE) {
        if (sprintf("%c%c%c", 229, 174, 189) != "宽") {
            WCWIDTH_INITIALIZED = -1
            print "wcwidth: the AWK interpreter is not multi-byte safe and" \
                  " its sprintf implementation does not support manual" \
                  " composition of UTF-8 sequences." >> "/dev/fd/2"
            close("/dev/fd/2")
        }

        WCWIDTH_UTF8_RUNE_REGEX = "(" \
            "[\001-\177]|" \
            "[\302-\336\337][\200-\277]|" \
            "\340[\240-\277][\200-\277]|" \
            "[\341-\354\356\357][\200-\277][\200-\277]|" \
            "\355[\200-\237][\200-\277]|" \
            "\360[\220-\277][\200-\277][\200-\277]|" \
            "[\361-\363][\200-\277][\200-\277][\200-\277]|" \
            "\364[\200-\217][\200-\277][\200-\277]|" \
            "." \
        ")"

        WCWIDTH_UTF8_ANCHORED_RUNE_REGEX = "^" WCWIDTH_UTF8_RUNE_REGEX

        WCWIDTH_WIDE_CJK_RUNES_REGEX = "^((" \
            "\343(\201[\201-\277]|\202[\200-\226])|" \
            "\343(\202[\233-\277]|\203[\200-\277])|" \
            "\344([\270-\277][\200-\277])|" \
            "[\345-\350]([\200-\277][\200-\277])|" \
            "\351([\200-\276][\200-\277]|\277[\200-\225])|" \
            "[\352-\354][\260-\277][\200-\277]|" \
            "\355([\200-\235][\200-\277]|\236[\200-\243])|" \
            "\357(\274[\201-\277]|\275[\200-\240])" \
            ")[ -~]*" \
        ")+"
    }

    # Kludges to support AWK implementations allow NUL bytes inside of strings.
    if (length((_nul = sprintf("%c", 0)))) {
        if (!WCWIDTH_MULTIBYTE_SAFE) {
            WCWIDTH_UTF8_ANCHORED_RUNE_REGEX = \
                WCWIDTH_UTF8_ANCHORED_RUNE_REGEX "|^" _nul
        }

        WCWIDTH_CACHE[_nul] = 0
    }

    WCWIDTH_POSIX_MODE = WCWIDTH_POSIX_MODE ? 1 : 0
    WCWIDTH_TABLE_LENGTH = 0
    WCWIDTH_INITIALIZED = 1
}

# Populate the data structures that contain character width information. For
# convenience, this function accepts a character and returns its width.
#
# Arguments:
# - _wchar: A single character as described in the "wcwidth" documentation.
#
# Returns: The width of the character i.e. `wcwidth(_wchar)`.
#
function _wcwidth_unpack_data(_wchar,    _a, _b, _c, _data, _end, _entry,
  _parts, _ranges, _start, _width, _width_of_wchar_argument) {

    _data = \
    "0 0 0,1 32 126,1 160 767,0 768 879,1 880 887,1 890 895,1 900 906,1 908 " \
    "908,1 910 929,1 931 1154,0 1155 1161,1 1162 1327,1 1329 1366,1 1369 141" \
    "8,1 1421 1423,0 1425 1469,1 1470 1470,0 1471 1471,1 1472 1472,0 1473 14" \
    "74,1 1475 1475,0 1476 1477,1 1478 1478,0 1479 1479,1 1488 1514,1 1519 1" \
    "524,1 1536 1551,0 1552 1562,1 1563 1563,0 1564 1564,1 1565 1610,0 1611 " \
    "1631,1 1632 1647,0 1648 1648,1 1649 1749,0 1750 1756,1 1757 1758,0 1759" \
    " 1764,1 1765 1766,0 1767 1768,1 1769 1769,0 1770 1773,1 1774 1805,1 180" \
    "7 1808,0 1809 1809,1 1810 1839,0 1840 1866,1 1869 1957,0 1958 1968,1 19" \
    "69 1969,1 1984 2026,0 2027 2035,1 2036 2042,0 2045 2045,1 2046 2047,1 2" \
    "048 2069,0 2070 2073,1 2074 2074,0 2075 2083,1 2084 2084,0 2085 2087,1 " \
    "2088 2088,0 2089 2093,1 2096 2110,1 2112 2136,0 2137 2139,1 2142 2142,1" \
    " 2144 2154,1 2160 2190,1 2192 2193,0 2200 2207,1 2208 2249,0 2250 2273," \
    "1 2274 2274,0 2275 2306,1 2307 2361,0 2362 2362,1 2363 2363,0 2364 2364" \
    ",1 2365 2368,0 2369 2376,1 2377 2380,0 2381 2381,1 2382 2384,0 2385 239" \
    "1,1 2392 2401,0 2402 2403,1 2404 2432,0 2433 2433,1 2434 2435,1 2437 24" \
    "44,1 2447 2448,1 2451 2472,1 2474 2480,1 2482 2482,1 2486 2489,0 2492 2" \
    "492,1 2493 2496,0 2497 2500,1 2503 2504,1 2507 2508,0 2509 2509,1 2510 " \
    "2510,1 2519 2519,1 2524 2525,1 2527 2529,0 2530 2531,1 2534 2557,0 2558" \
    " 2558,0 2561 2562,1 2563 2563,1 2565 2570,1 2575 2576,1 2579 2600,1 260" \
    "2 2608,1 2610 2611,1 2613 2614,1 2616 2617,0 2620 2620,1 2622 2624,0 26" \
    "25 2626,0 2631 2632,0 2635 2637,0 2641 2641,1 2649 2652,1 2654 2654,1 2" \
    "662 2671,0 2672 2673,1 2674 2676,0 2677 2677,1 2678 2678,0 2689 2690,1 " \
    "2691 2691,1 2693 2701,1 2703 2705,1 2707 2728,1 2730 2736,1 2738 2739,1" \
    " 2741 2745,0 2748 2748,1 2749 2752,0 2753 2757,0 2759 2760,1 2761 2761," \
    "1 2763 2764,0 2765 2765,1 2768 2768,1 2784 2785,0 2786 2787,1 2790 2801" \
    ",1 2809 2809,0 2810 2815,0 2817 2817,1 2818 2819,1 2821 2828,1 2831 283" \
    "2,1 2835 2856,1 2858 2864,1 2866 2867,1 2869 2873,0 2876 2876,1 2877 28" \
    "78,0 2879 2879,1 2880 2880,0 2881 2884,1 2887 2888,1 2891 2892,0 2893 2" \
    "893,0 2901 2902,1 2903 2903,1 2908 2909,1 2911 2913,0 2914 2915,1 2918 " \
    "2935,0 2946 2946,1 2947 2947,1 2949 2954,1 2958 2960,1 2962 2965,1 2969" \
    " 2970,1 2972 2972,1 2974 2975,1 2979 2980,1 2984 2986,1 2990 3001,1 300" \
    "6 3007,0 3008 3008,1 3009 3010,1 3014 3016,1 3018 3020,0 3021 3021,1 30" \
    "24 3024,1 3031 3031,1 3046 3066,0 3072 3072,1 3073 3075,0 3076 3076,1 3" \
    "077 3084,1 3086 3088,1 3090 3112,1 3114 3129,0 3132 3132,1 3133 3133,0 " \
    "3134 3136,1 3137 3140,0 3142 3144,0 3146 3149,0 3157 3158,1 3160 3162,1" \
    " 3165 3165,1 3168 3169,0 3170 3171,1 3174 3183,1 3191 3200,0 3201 3201," \
    "1 3202 3212,1 3214 3216,1 3218 3240,1 3242 3251,1 3253 3257,0 3260 3260" \
    ",1 3261 3262,0 3263 3263,1 3264 3268,0 3270 3270,1 3271 3272,1 3274 327" \
    "5,0 3276 3277,1 3285 3286,1 3293 3294,1 3296 3297,0 3298 3299,1 3302 33" \
    "11,1 3313 3314,0 3328 3329,1 3330 3340,1 3342 3344,1 3346 3386,0 3387 3" \
    "388,1 3389 3392,0 3393 3396,1 3398 3400,1 3402 3404,0 3405 3405,1 3406 " \
    "3407,1 3412 3425,0 3426 3427,1 3430 3455,0 3457 3457,1 3458 3459,1 3461" \
    " 3478,1 3482 3505,1 3507 3515,1 3517 3517,1 3520 3526,0 3530 3530,1 353" \
    "5 3537,0 3538 3540,0 3542 3542,1 3544 3551,1 3558 3567,1 3570 3572,1 35" \
    "85 3632,0 3633 3633,1 3634 3635,0 3636 3642,1 3647 3654,0 3655 3662,1 3" \
    "663 3675,1 3713 3714,1 3716 3716,1 3718 3722,1 3724 3747,1 3749 3749,1 " \
    "3751 3760,0 3761 3761,1 3762 3763,0 3764 3772,1 3773 3773,1 3776 3780,1" \
    " 3782 3782,0 3784 3789,1 3792 3801,1 3804 3807,1 3840 3863,0 3864 3865," \
    "1 3866 3892,0 3893 3893,1 3894 3894,0 3895 3895,1 3896 3896,0 3897 3897" \
    ",1 3898 3911,1 3913 3948,0 3953 3966,1 3967 3967,0 3968 3972,1 3973 397" \
    "3,0 3974 3975,1 3976 3980,0 3981 3991,0 3993 4028,1 4030 4037,0 4038 40" \
    "38,1 4039 4044,1 4046 4058,1 4096 4140,0 4141 4144,1 4145 4145,0 4146 4" \
    "151,1 4152 4152,0 4153 4154,1 4155 4156,0 4157 4158,1 4159 4183,0 4184 " \
    "4185,1 4186 4189,0 4190 4192,1 4193 4208,0 4209 4212,1 4213 4225,0 4226" \
    " 4226,1 4227 4228,0 4229 4230,1 4231 4236,0 4237 4237,1 4238 4252,0 425" \
    "3 4253,1 4254 4293,1 4295 4295,1 4301 4301,1 4304 4351,2 4352 4447,0 44" \
    "48 4607,1 4608 4680,1 4682 4685,1 4688 4694,1 4696 4696,1 4698 4701,1 4" \
    "704 4744,1 4746 4749,1 4752 4784,1 4786 4789,1 4792 4798,1 4800 4800,1 " \
    "4802 4805,1 4808 4822,1 4824 4880,1 4882 4885,1 4888 4954,0 4957 4959,1" \
    " 4960 4988,1 4992 5017,1 5024 5109,1 5112 5117,1 5120 5788,1 5792 5880," \
    "1 5888 5905,0 5906 5908,1 5909 5909,1 5919 5937,0 5938 5939,1 5940 5942" \
    ",1 5952 5969,0 5970 5971,1 5984 5996,1 5998 6000,0 6002 6003,1 6016 606" \
    "7,0 6068 6069,1 6070 6070,0 6071 6077,1 6078 6085,0 6086 6086,1 6087 60" \
    "88,0 6089 6099,1 6100 6108,0 6109 6109,1 6112 6121,1 6128 6137,1 6144 6" \
    "154,0 6155 6159,1 6160 6169,1 6176 6264,1 6272 6276,0 6277 6278,1 6279 " \
    "6312,0 6313 6313,1 6314 6314,1 6320 6389,1 6400 6430,0 6432 6434,1 6435" \
    " 6438,0 6439 6440,1 6441 6443,1 6448 6449,0 6450 6450,1 6451 6456,0 645" \
    "7 6459,1 6464 6464,1 6468 6509,1 6512 6516,1 6528 6571,1 6576 6601,1 66" \
    "08 6618,1 6622 6678,0 6679 6680,1 6681 6682,0 6683 6683,1 6686 6741,0 6" \
    "742 6742,1 6743 6743,0 6744 6750,0 6752 6752,1 6753 6753,0 6754 6754,1 " \
    "6755 6756,0 6757 6764,1 6765 6770,0 6771 6780,0 6783 6783,1 6784 6793,1" \
    " 6800 6809,1 6816 6829,0 6832 6862,0 6912 6915,1 6916 6963,0 6964 6964," \
    "1 6965 6965,0 6966 6970,1 6971 6971,0 6972 6972,1 6973 6977,0 6978 6978" \
    ",1 6979 6988,1 6992 7018,0 7019 7027,1 7028 7038,0 7040 7041,1 7042 707" \
    "3,0 7074 7077,1 7078 7079,0 7080 7081,1 7082 7082,0 7083 7085,1 7086 71" \
    "41,0 7142 7142,1 7143 7143,0 7144 7145,1 7146 7148,0 7149 7149,1 7150 7" \
    "150,0 7151 7153,1 7154 7155,1 7164 7211,0 7212 7219,1 7220 7221,0 7222 " \
    "7223,1 7227 7241,1 7245 7304,1 7312 7354,1 7357 7367,0 7376 7378,1 7379" \
    " 7379,0 7380 7392,1 7393 7393,0 7394 7400,1 7401 7404,0 7405 7405,1 740" \
    "6 7411,0 7412 7412,1 7413 7415,0 7416 7417,1 7418 7418,1 7424 7615,0 76" \
    "16 7679,1 7680 7957,1 7960 7965,1 7968 8005,1 8008 8013,1 8016 8023,1 8" \
    "025 8025,1 8027 8027,1 8029 8029,1 8031 8061,1 8064 8116,1 8118 8132,1 " \
    "8134 8147,1 8150 8155,1 8157 8175,1 8178 8180,1 8182 8190,1 8192 8202,0" \
    " 8203 8207,1 8208 8231,0 8234 8238,1 8239 8287,0 8288 8292,0 8294 8303," \
    "1 8304 8305,1 8308 8334,1 8336 8348,1 8352 8384,0 8400 8432,1 8448 8587" \
    ",1 8592 8985,2 8986 8987,1 8988 9000,2 9001 9002,1 9003 9192,2 9193 919" \
    "6,1 9197 9199,2 9200 9200,1 9201 9202,2 9203 9203,1 9204 9254,1 9280 92" \
    "90,1 9312 9724,2 9725 9726,1 9727 9747,2 9748 9749,1 9750 9799,2 9800 9" \
    "811,1 9812 9854,2 9855 9855,1 9856 9874,2 9875 9875,1 9876 9888,2 9889 " \
    "9889,1 9890 9897,2 9898 9899,1 9900 9916,2 9917 9918,1 9919 9923,2 9924" \
    " 9925,1 9926 9933,2 9934 9934,1 9935 9939,2 9940 9940,1 9941 9961,2 996" \
    "2 9962,1 9963 9969,2 9970 9971,1 9972 9972,2 9973 9973,1 9974 9977,2 99" \
    "78 9978,1 9979 9980,2 9981 9981,1 9982 9988,2 9989 9989,1 9990 9993,2 9" \
    "994 9995,1 9996 10023,2 10024 10024,1 10025 10059,2 10060 10060,1 10061" \
    " 10061,2 10062 10062,1 10063 10066,2 10067 10069,1 10070 10070,2 10071 " \
    "10071,1 10072 10132,2 10133 10135,1 10136 10159,2 10160 10160,1 10161 1" \
    "0174,2 10175 10175,1 10176 11034,2 11035 11036,1 11037 11087,2 11088 11" \
    "088,1 11089 11092,2 11093 11093,1 11094 11123,1 11126 11157,1 11159 115" \
    "02,0 11503 11505,1 11506 11507,1 11513 11557,1 11559 11559,1 11565 1156" \
    "5,1 11568 11623,1 11631 11632,0 11647 11647,1 11648 11670,1 11680 11686" \
    ",1 11688 11694,1 11696 11702,1 11704 11710,1 11712 11718,1 11720 11726," \
    "1 11728 11734,1 11736 11742,0 11744 11775,1 11776 11869,2 11904 11929,2" \
    " 11931 12019,2 12032 12245,2 12272 12283,2 12288 12329,0 12330 12333,2 " \
    "12334 12350,1 12351 12351,2 12353 12438,0 12441 12442,2 12443 12543,2 1" \
    "2549 12591,2 12593 12686,2 12688 12771,2 12784 12830,2 12832 42124,2 42" \
    "128 42182,1 42192 42539,1 42560 42606,0 42607 42610,1 42611 42611,0 426" \
    "12 42621,1 42622 42653,0 42654 42655,1 42656 42735,0 42736 42737,1 4273" \
    "8 42743,1 42752 42954,1 42960 42961,1 42963 42963,1 42965 42969,1 42994" \
    " 43009,0 43010 43010,1 43011 43013,0 43014 43014,1 43015 43018,0 43019 " \
    "43019,1 43020 43044,0 43045 43046,1 43047 43051,0 43052 43052,1 43056 4" \
    "3065,1 43072 43127,1 43136 43203,0 43204 43205,1 43214 43225,0 43232 43" \
    "249,1 43250 43262,0 43263 43263,1 43264 43301,0 43302 43309,1 43310 433" \
    "34,0 43335 43345,1 43346 43347,1 43359 43359,2 43360 43388,0 43392 4339" \
    "4,1 43395 43442,0 43443 43443,1 43444 43445,0 43446 43449,1 43450 43451" \
    ",0 43452 43453,1 43454 43469,1 43471 43481,1 43486 43492,0 43493 43493," \
    "1 43494 43518,1 43520 43560,0 43561 43566,1 43567 43568,0 43569 43570,1" \
    " 43571 43572,0 43573 43574,1 43584 43586,0 43587 43587,1 43588 43595,0 " \
    "43596 43596,1 43597 43597,1 43600 43609,1 43612 43643,0 43644 43644,1 4" \
    "3645 43695,0 43696 43696,1 43697 43697,0 43698 43700,1 43701 43702,0 43" \
    "703 43704,1 43705 43709,0 43710 43711,1 43712 43712,0 43713 43713,1 437" \
    "14 43714,1 43739 43755,0 43756 43757,1 43758 43765,0 43766 43766,1 4377" \
    "7 43782,1 43785 43790,1 43793 43798,1 43808 43814,1 43816 43822,1 43824" \
    " 43883,1 43888 44004,0 44005 44005,1 44006 44007,0 44008 44008,1 44009 " \
    "44012,0 44013 44013,1 44016 44025,2 44032 55203,0 55216 55238,0 55243 5" \
    "5291,1 57344 63743,2 63744 64109,2 64112 64217,1 64256 64262,1 64275 64" \
    "279,1 64285 64285,0 64286 64286,1 64287 64310,1 64312 64316,1 64318 643" \
    "18,1 64320 64321,1 64323 64324,1 64326 64450,1 64467 64911,1 64914 6496" \
    "7,1 64975 64975,1 65008 65023,0 65024 65039,2 65040 65049,0 65056 65071" \
    ",2 65072 65106,2 65108 65126,2 65128 65131,1 65136 65140,1 65142 65276," \
    "0 65279 65279,2 65281 65376,1 65377 65470,1 65474 65479,1 65482 65487,1" \
    " 65490 65495,1 65498 65500,2 65504 65510,1 65512 65518,0 65529 65531,1 " \
    "65532 65533,1 65536 65547,1 65549 65574,1 65576 65594,1 65596 65597,1 6" \
    "5599 65613,1 65616 65629,1 65664 65786,1 65792 65794,1 65799 65843,1 65" \
    "847 65934,1 65936 65948,1 65952 65952,1 66000 66044,0 66045 66045,1 661" \
    "76 66204,1 66208 66256,0 66272 66272,1 66273 66299,1 66304 66339,1 6634" \
    "9 66378,1 66384 66421,0 66422 66426,1 66432 66461,1 66463 66499,1 66504" \
    " 66517,1 66560 66717,1 66720 66729,1 66736 66771,1 66776 66811,1 66816 " \
    "66855,1 66864 66915,1 66927 66938,1 66940 66954,1 66956 66962,1 66964 6" \
    "6965,1 66967 66977,1 66979 66993,1 66995 67001,1 67003 67004,1 67072 67" \
    "382,1 67392 67413,1 67424 67431,1 67456 67461,1 67463 67504,1 67506 675" \
    "14,1 67584 67589,1 67592 67592,1 67594 67637,1 67639 67640,1 67644 6764" \
    "4,1 67647 67669,1 67671 67742,1 67751 67759,1 67808 67826,1 67828 67829" \
    ",1 67835 67867,1 67871 67897,1 67903 67903,1 67968 68023,1 68028 68047," \
    "1 68050 68096,0 68097 68099,0 68101 68102,0 68108 68111,1 68112 68115,1" \
    " 68117 68119,1 68121 68149,0 68152 68154,0 68159 68159,1 68160 68168,1 " \
    "68176 68184,1 68192 68255,1 68288 68324,0 68325 68326,1 68331 68342,1 6" \
    "8352 68405,1 68409 68437,1 68440 68466,1 68472 68497,1 68505 68508,1 68" \
    "521 68527,1 68608 68680,1 68736 68786,1 68800 68850,1 68858 68899,0 689" \
    "00 68903,1 68912 68921,1 69216 69246,1 69248 69289,0 69291 69292,1 6929" \
    "3 69293,1 69296 69297,1 69376 69415,1 69424 69445,0 69446 69456,1 69457" \
    " 69465,1 69488 69505,0 69506 69509,1 69510 69513,1 69552 69579,1 69600 " \
    "69622,1 69632 69632,0 69633 69633,1 69634 69687,0 69688 69702,1 69703 6" \
    "9709,1 69714 69743,0 69744 69744,1 69745 69746,0 69747 69748,1 69749 69" \
    "749,0 69759 69761,1 69762 69810,0 69811 69814,1 69815 69816,0 69817 698" \
    "18,1 69819 69825,0 69826 69826,1 69837 69837,1 69840 69864,1 69872 6988" \
    "1,0 69888 69890,1 69891 69926,0 69927 69931,1 69932 69932,0 69933 69940" \
    ",1 69942 69959,1 69968 70002,0 70003 70003,1 70004 70006,0 70016 70017," \
    "1 70018 70069,0 70070 70078,1 70079 70088,0 70089 70092,1 70093 70094,0" \
    " 70095 70095,1 70096 70111,1 70113 70132,1 70144 70161,1 70163 70190,0 " \
    "70191 70193,1 70194 70195,0 70196 70196,1 70197 70197,0 70198 70199,1 7" \
    "0200 70205,0 70206 70206,1 70272 70278,1 70280 70280,1 70282 70285,1 70" \
    "287 70301,1 70303 70313,1 70320 70366,0 70367 70367,1 70368 70370,0 703" \
    "71 70378,1 70384 70393,0 70400 70401,1 70402 70403,1 70405 70412,1 7041" \
    "5 70416,1 70419 70440,1 70442 70448,1 70450 70451,1 70453 70457,0 70459" \
    " 70460,1 70461 70463,0 70464 70464,1 70465 70468,1 70471 70472,1 70475 " \
    "70477,1 70480 70480,1 70487 70487,1 70493 70499,0 70502 70508,0 70512 7" \
    "0516,1 70656 70711,0 70712 70719,1 70720 70721,0 70722 70724,1 70725 70" \
    "725,0 70726 70726,1 70727 70747,1 70749 70749,0 70750 70750,1 70751 707" \
    "53,1 70784 70834,0 70835 70840,1 70841 70841,0 70842 70842,1 70843 7084" \
    "6,0 70847 70848,1 70849 70849,0 70850 70851,1 70852 70855,1 70864 70873" \
    ",1 71040 71089,0 71090 71093,1 71096 71099,0 71100 71101,1 71102 71102," \
    "0 71103 71104,1 71105 71131,0 71132 71133,1 71168 71218,0 71219 71226,1" \
    " 71227 71228,0 71229 71229,1 71230 71230,0 71231 71232,1 71233 71236,1 " \
    "71248 71257,1 71264 71276,1 71296 71338,0 71339 71339,1 71340 71340,0 7" \
    "1341 71341,1 71342 71343,0 71344 71349,1 71350 71350,0 71351 71351,1 71" \
    "352 71353,1 71360 71369,1 71424 71450,0 71453 71455,1 71456 71457,0 714" \
    "58 71461,1 71462 71462,0 71463 71467,1 71472 71494,1 71680 71726,0 7172" \
    "7 71735,1 71736 71736,0 71737 71738,1 71739 71739,1 71840 71922,1 71935" \
    " 71942,1 71945 71945,1 71948 71955,1 71957 71958,1 71960 71989,1 71991 " \
    "71992,0 71995 71996,1 71997 71997,0 71998 71998,1 71999 72002,0 72003 7" \
    "2003,1 72004 72006,1 72016 72025,1 72096 72103,1 72106 72147,0 72148 72" \
    "151,0 72154 72155,1 72156 72159,0 72160 72160,1 72161 72164,1 72192 721" \
    "92,0 72193 72202,1 72203 72242,0 72243 72248,1 72249 72250,0 72251 7225" \
    "4,1 72255 72262,0 72263 72263,1 72272 72272,0 72273 72278,1 72279 72280" \
    ",0 72281 72283,1 72284 72329,0 72330 72342,1 72343 72343,0 72344 72345," \
    "1 72346 72354,1 72368 72440,1 72704 72712,1 72714 72751,0 72752 72758,0" \
    " 72760 72765,1 72766 72766,0 72767 72767,1 72768 72773,1 72784 72812,1 " \
    "72816 72847,0 72850 72871,1 72873 72873,0 72874 72880,1 72881 72881,0 7" \
    "2882 72883,1 72884 72884,0 72885 72886,1 72960 72966,1 72968 72969,1 72" \
    "971 73008,0 73009 73014,0 73018 73018,0 73020 73021,0 73023 73029,1 730" \
    "30 73030,0 73031 73031,1 73040 73049,1 73056 73061,1 73063 73064,1 7306" \
    "6 73102,0 73104 73105,1 73107 73108,0 73109 73109,1 73110 73110,0 73111" \
    " 73111,1 73112 73112,1 73120 73129,1 73440 73458,0 73459 73460,1 73461 " \
    "73464,1 73648 73648,1 73664 73713,1 73727 74649,1 74752 74862,1 74864 7" \
    "4868,1 74880 75075,1 77712 77810,1 77824 78894,0 78896 78904,1 82944 83" \
    "526,1 92160 92728,1 92736 92766,1 92768 92777,1 92782 92862,1 92864 928" \
    "73,1 92880 92909,0 92912 92916,1 92917 92917,1 92928 92975,0 92976 9298" \
    "2,1 92983 92997,1 93008 93017,1 93019 93025,1 93027 93047,1 93053 93071" \
    ",1 93760 93850,1 93952 94026,0 94031 94031,1 94032 94087,0 94095 94098," \
    "1 94099 94111,2 94176 94179,0 94180 94180,2 94192 94193,2 94208 100343," \
    "2 100352 101589,2 101632 101640,2 110576 110579,2 110581 110587,2 11058" \
    "9 110590,2 110592 110882,2 110928 110930,2 110948 110951,2 110960 11135" \
    "5,1 113664 113770,1 113776 113788,1 113792 113800,1 113808 113817,1 113" \
    "820 113820,0 113821 113822,1 113823 113823,0 113824 113827,0 118528 118" \
    "573,0 118576 118598,1 118608 118723,1 118784 119029,1 119040 119078,1 1" \
    "19081 119142,0 119143 119145,1 119146 119154,0 119155 119170,1 119171 1" \
    "19172,0 119173 119179,1 119180 119209,0 119210 119213,1 119214 119274,1" \
    " 119296 119361,0 119362 119364,1 119365 119365,1 119520 119539,1 119552" \
    " 119638,1 119648 119672,1 119808 119892,1 119894 119964,1 119966 119967" \
    ",1 119970 119970,1 119973 119974,1 119977 119980,1 119982 119993,1 1199" \
    "95 119995,1 119997 120003,1 120005 120069,1 120071 120074,1 120077 1200" \
    "84,1 120086 120092,1 120094 120121,1 120123 120126,1 120128 120132,1 12" \
    "0134 120134,1 120138 120144,1 120146 120485,1 120488 120779,1 120782 12" \
    "1343,0 121344 121398,1 121399 121402,0 121403 121452,1 121453 121460,0 " \
    "121461 121461,1 121462 121475,0 121476 121476,1 121477 121483,0 121499 " \
    "121503,0 121505 121519,1 122624 122654,0 122880 122886,0 122888 122904," \
    "0 122907 122913,0 122915 122916,0 122918 122922,1 123136 123180,0 12318" \
    "4 123190,1 123191 123197,1 123200 123209,1 123214 123215,1 123536 12356" \
    "5,0 123566 123566,1 123584 123627,0 123628 123631,1 123632 123641,1 123" \
    "647 123647,1 124896 124902,1 124904 124907,1 124909 124910,1 124912 124" \
    "926,1 124928 125124,1 125127 125135,0 125136 125142,1 125184 125251,0 1" \
    "25252 125258,1 125259 125259,1 125264 125273,1 125278 125279,1 126065 1" \
    "26132,1 126209 126269,1 126464 126467,1 126469 126495,1 126497 126498,1" \
    " 126500 126500,1 126503 126503,1 126505 126514,1 126516 126519,1 126521" \
    " 126521,1 126523 126523,1 126530 126530,1 126535 126535,1 126537 126537" \
    ",1 126539 126539,1 126541 126543,1 126545 126546,1 126548 126548,1 1265" \
    "51 126551,1 126553 126553,1 126555 126555,1 126557 126557,1 126559 1265" \
    "59,1 126561 126562,1 126564 126564,1 126567 126570,1 126572 126578,1 12" \
    "6580 126583,1 126585 126588,1 126590 126590,1 126592 126601,1 126603 12" \
    "6619,1 126625 126627,1 126629 126633,1 126635 126651,1 126704 126705,1 " \
    "126976 126979,2 126980 126980,1 126981 127019,1 127024 127123,1 127136 " \
    "127150,1 127153 127167,1 127169 127182,2 127183 127183,1 127185 127221," \
    "1 127232 127373,2 127374 127374,1 127375 127376,2 127377 127386,1 12738" \
    "7 127405,1 127462 127487,2 127488 127490,2 127504 127547,2 127552 12756" \
    "0,2 127568 127569,2 127584 127589,2 127744 127776,1 127777 127788,2 127" \
    "789 127797,1 127798 127798,2 127799 127868,1 127869 127869,2 127870 127" \
    "891,1 127892 127903,2 127904 127946,1 127947 127950,2 127951 127955,1 1" \
    "27956 127967,2 127968 127984,1 127985 127987,2 127988 127988,1 127989 1" \
    "27991,2 127992 128062,1 128063 128063,2 128064 128064,1 128065 128065,2" \
    " 128066 128252,1 128253 128254,2 128255 128317,1 128318 128330,2 128331" \
    " 128334,1 128335 128335,2 128336 128359,1 128360 128377,2 128378 128378" \
    ",1 128379 128404,2 128405 128406,1 128407 128419,2 128420 128420,1 1284" \
    "21 128506,2 128507 128591,1 128592 128639,2 128640 128709,1 128710 1287" \
    "15,2 128716 128716,1 128717 128719,2 128720 128722,1 128723 128724,2 12" \
    "8725 128727,2 128733 128735,1 128736 128746,2 128747 128748,1 128752 12" \
    "8755,2 128756 128764,1 128768 128883,1 128896 128984,2 128992 129003,2 " \
    "129008 129008,1 129024 129035,1 129040 129095,1 129104 129113,1 129120 " \
    "129159,1 129168 129197,1 129200 129201,1 129280 129291,2 129292 129338," \
    "1 129339 129339,2 129340 129349,1 129350 129350,2 129351 129535,1 12953" \
    "6 129619,1 129632 129645,2 129648 129652,2 129656 129660,2 129664 12967" \
    "0,2 129680 129708,2 129712 129722,2 129728 129733,2 129744 129753,2 129" \
    "760 129767,2 129776 129782,1 129792 129938,1 129940 129994,1 130032 130" \
    "041,2 131072 173791,2 173824 177976,2 177984 178205,2 178208 183969,2 1" \
    "83984 191456,2 194560 195101,2 196608 201546,0 917505 917505,0 917536 9" \
    "17631,0 917760 917999,1 983040 1048573,1 1048576 1114109"

    _width_of_wchar_argument = -1
    WCWIDTH_TABLE_LENGTH = split(_data, _ranges, ",")

    for (_entry = 0; _entry < WCWIDTH_TABLE_LENGTH; _entry++) {
        split(_ranges[_entry + 1], _parts)
        _width = 0 + _parts[1]
        _start = 0 + _parts[2]
        _end = 0 + _parts[3]

        if (WCWIDTH_MULTIBYTE_SAFE || _end < 128) {
            _start = sprintf("%c", _start)
            _end = sprintf("%c", _end)
        } else {
            # Sequences for code points U+0080 and up must be composed manually
            # if the interpreter is not multi-byte safe.

            # Re-use of the length encoding addended values for both endpoints
            # only works if both characters consist of the same number of
            # bytes. This is enforced by the width data generator.
            _a = _start >= 65536 ? 240 : 32
            _b = _a != 32 ? 128 : _start >= 2048 ? 224 : 32
            _c = _b != 32 ? 128 : _start >= 64 ? 192 : 32

            _start = sprintf("%c%c%c%c",
                _a + int(_start / 262144) % 64,
                _b + int(_start / 4096) % 64,
                _c + int(_start / 64) % 64,
                128 + _start % 64 \
            )

            _end = sprintf("%c%c%c%c",
                _a + int(_end / 262144) % 64,
                _b + int(_end / 4096) % 64,
                _c + int(_end / 64) % 64,
                128 + _end % 64 \
            )

            if (_a == 32) {
                _end = substr(_end, 2 + (_b == 32) + (_c == 32))
                _start = substr(_start, 2 + (_b == 32) + (_c == 32))
            }
        }

        if (_wchar <= _end) {
            if (_wchar >= _start) {
                _width_of_wchar_argument = _width
            }

            WCWIDTH_SEARCH_CURSOR = _entry
        }

        WCWIDTH_RANGE_WIDTH[_entry] = _width
        WCWIDTH_RANGE_START[_entry] = _start
        WCWIDTH_RANGE_END[_entry] = _end
    }

    return (WCWIDTH_CACHE[_wchar] = _width_of_wchar_argument)
}
