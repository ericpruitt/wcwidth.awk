#!/usr/bin/awk -f

# This AWK library provides a "wcwidth" function that accepts a string as its
# only argument and returns the number of columns needed to display the string.
# Unlike POSIX's wcwidth(3), the argument to this library's "wcwidth" function
# can be any number of characters long. Bytes in invalid UTF-8 sequences are
# treated as "�" which means they have a width of 1.
#
# To minimize the likelihood of name conflicts, all global variables used by
# this code begin with "WCWIDTH_...", all internal functions begin with
# "_wcwidth_...", and all arguments / function-local variables that are not
# arguments begin with a "_".
#
# Author: Eric Pruitt (https://www.codevat.com)
# License: 2-Clause BSD (http://opensource.org/licenses/BSD-2-Clause)
# Project Page: https://github.com/ericpruitt/wcwidth.awk

BEGIN {
    WCWIDTH_ASCII_TABLE_POPULATED = 0
    WCWIDTH_MULTIBYTE_SAFE = length("宽") == 1
    WCWIDTH_TABLE_LENGTH = 0

    split("", WCWIDTH_CACHE)

    if (!WCWIDTH_MULTIBYTE_SAFE) {
        WCWIDTH_UTF8_RUNE_REGEX = "^(" \
            "[\001-\177]|" \
            "[\302-\337][\200-\277]|" \
            "\340[\240-\277][\200-\277]|" \
            "[\341-\354\356\357][\200-\277][\200-\277]|" \
            "\355[\200-\237][\200-\277]|" \
            "\360[\220-\277][\200-\277][\200-\277]|" \
            "[\361-\363][\200-\277][\200-\277][\200-\277]|" \
            "\364[\200-\217][\200-\277][\200-\277]|" \
            "." \
        ")"
    } else if (sprintf("%c", 23485) != "宽") {
        print "wcwidth: AWK interpreter supports multibyte sequences," \
              " but sprintf does not accept wide character values for \"%c\"" \
          > "/dev/fd/2"
        close("/dev/fd/2")
        exit 2
    } else if ("\000X" != "\000Y") {
        # Kludge to support AWK implementations allow NUL bytes inside of
        # strings.
        WCWIDTH_CACHE["\000"] = 0
    }
}

# Return the number of columns needed to display a string.
#
# Arguments:
# - _val: A string of any length.
#
# Returns: The number of columns needed to display the string.
#
function wcwidth(_val,    _bytes, _char, _cols, _len, _max, _min, _mid, _n, _w)
{
    _len = length(_val)

    if (!_len) {
        return 0
    }

    _cols = 0

    if (WCWIDTH_MULTIBYTE_SAFE) {
        # Optimization for ASCII and Latin 1 (ISO 8859-1) text.
        _cols = _len
        gsub(/[\040-\176\240-\254\256-\377]+/, "", _val)
        _len = length(_val)
        _cols -= _len

        if (!_len) {
            return _cols
        }

        _n = 1
    }

    while (1) {
        if (!WCWIDTH_MULTIBYTE_SAFE) {
            # Optimization for ASCII text.
            _cols += length(_val)
            sub(/^[\040-\176]+/, "", _val)
            _cols -= length(_val)

            if (!length(_val) || !match(_val, WCWIDTH_UTF8_RUNE_REGEX)) {
                break
            }

            _bytes = substr(_val, RSTART, RLENGTH)
            _val = substr(_val, RLENGTH + 1)

            # Convert the UTF-8 sequence to a numeric code point.
            if (!WCWIDTH_ASCII_TABLE_POPULATED) {
                for (_n = 0; _n < 256; _n++) {
                    WCWIDTH_BYTE_VALUES[sprintf("%c", _n)] = _n
                }

                WCWIDTH_ASCII_TABLE_POPULATED = 1
            }

            if (length(_bytes) == 1) {
                _char = WCWIDTH_BYTE_VALUES[substr(_bytes, 1, 1)]
                _char = _char >= 128 ? 65533 : _char  # Invalid -> "�"
            } else if (length(_bytes) == 2) {
                _char = \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 2, 1)] % 128 + \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 1, 1)] % 32 * 64
            } else if (length(_bytes) == 3) {
                _char = \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 3, 1)] % 128 + \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 2, 1)] % 128 * 64 + \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 1, 1)] % 16 * 4096
            } else {
                _char = \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 4, 1)] % 128 + \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 3, 1)] % 128 * 64 + \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 2, 1)] % 128 * 4096 + \
                    WCWIDTH_BYTE_VALUES[substr(_bytes, 1, 1)] % 8 * 262144
            }
        } else if (_n > length(_val)) {
            break
        } else {
            _char = substr(_val, _n++, 1)
        }

        if (_char in WCWIDTH_CACHE) {
            _w = WCWIDTH_CACHE[_char]
        } else {
            if (!WCWIDTH_TABLE_LENGTH) {
                _wcwidth_unpack_data()
            }

            # Do a binary search to find the width of the character.
            _min = 0
            _max = WCWIDTH_TABLE_LENGTH - 1
            _w = -1

            while (_min <= _max) {
                _mid = int((_min + _max) / 2)

                if (_char > WCWIDTH_RANGE_END[_mid]) {
                    _min = _mid + 1
                } else if (_char < WCWIDTH_RANGE_START[_mid]) {
                    _max = _mid - 1
                } else {
                    WCWIDTH_CACHE[_char] = _w = WCWIDTH_RANGE_WIDTH[_mid]
                    break
                }
            }
        }

        if (_w == -1) {
            return -1
        }

        _cols += _w
    }

    return _cols
}

# Populate the data structures that contain character width information.
#
function _wcwidth_unpack_data(    _data, _end, _entry, _parts, _ranges, _start)
{
    _data = \
    # XXX: This part of the function will be filled in automatically.

    WCWIDTH_TABLE_LENGTH = split(_data, _ranges, ",")

    for (_entry = 0; _entry < WCWIDTH_TABLE_LENGTH; _entry++) {
        split(_ranges[_entry + 1], _parts)
        _start = 0 + _parts[2]
        _end = 0 + _parts[3]

        WCWIDTH_RANGE_WIDTH[_entry] = 0 + _parts[1]

        if (WCWIDTH_MULTIBYTE_SAFE) {
            WCWIDTH_RANGE_START[_entry] = sprintf("%c", _start)
            WCWIDTH_RANGE_END[_entry] = sprintf("%c", _end)
        } else {
            WCWIDTH_RANGE_START[_entry] = _start
            WCWIDTH_RANGE_END[_entry] = _end
        }
    }
}
