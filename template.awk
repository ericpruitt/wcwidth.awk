#!/usr/bin/awk -f

# This AWK library provides 3 functions for working with UTF-8 strings:
#
# - columns(string): Returns the number of colums needed to display a string,
#   but unlike "wcswidth" and "wcwidth" which are written to function
#   identically to their POSIX counterparts, this function always returns a
#   value greater than or equal to 0.
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
function columns(_str,    _length, _max, _min, _offset, _total, _wchar, _width)
{
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
        # characters used on Chinese and Japanese sites. U+3099 is a combining
        # character, so it has been replaced with an octal sequence to keep
        # terminal screens from getting munged.
        _length = length(_str)
        _total -= _length
        gsub(/[가-힣一-鿕！-｠ぁ-ゖ\343\202\231-ヿ]+/, "", _str)
        _total += (_length - length(_str)) * 2

        _offset = 1
    }

    if (!_str) {
        return _total
    }

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
            if (match(_str, /^([\303-\313][\200-\277][ -~]*)+/)) {
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

            match(_str, WCWIDTH_UTF8_RUNE_REGEX)
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
            return -1
        } else {
            # Ignore non-printable ASCII characters.
            _total += length(_wchar) == 1 ? _wchar > "\177" : 1
        }
    }

    return _total
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
    _width = columns(_str)
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
function wcwidth(_wchar)
{
    if (!_wchar) {
        return -1
    } else if (WCWIDTH_MULTIBYTE_SAFE) {
        return length(_wchar) == 1 ? wcswidth(_wchar) : -1
    } else if (match(_wchar, WCWIDTH_UTF8_RUNE_REGEX)) {
        return RLENGTH == length(_wchar) ? wcswidth(_wchar) : -1
    } else {
        return -1
    }
}

#                                     ---
# The functions beyond this point are intended only for internal use and should
# be treated as implementation details.
#                                     ---

BEGIN {
    # Silence "defined but never called directly" warnings generated when using
    # GAWK's linter.
    if (0) {
        columns()
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

    WCWIDTH_MULTIBYTE_SAFE = length("宽") == 1

    if (!WCWIDTH_MULTIBYTE_SAFE) {
        if (sprintf("%c%c%c", 229, 174, 189) != "宽") {
            WCWIDTH_INITIALIZED = -1
            print "wcwidth: the AWK interpreter is not multi-byte safe and" \
                  " its sprintf implementation does not support allow UTF-8" \
                  " sequences to be composed manually" >> "/dev/fd/2"
            close("/dev/fd/2")
        }

        WCWIDTH_UTF8_RUNE_REGEX = "^(" \
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
        WCWIDTH_WIDE_CJK_RUNES_REGEX = "^((" \
            "\343(\201[\201-\277]|\202[\200-\226])|" \
            "\343(\202[\231-\277]|\203[\200-\277])|" \
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
            WCWIDTH_UTF8_RUNE_REGEX = WCWIDTH_UTF8_RUNE_REGEX "|^" _nul
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
    # XXX: This part of the function will be filled in automatically.

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
            # UTF-8 characters must be composed manually for multi-byte unsafe
            # interpreters outside of the ASCII range.

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
