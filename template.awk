#!/usr/bin/awk -f

# This AWK library provides a "wcwidth" function that accepts a string as its
# only argument and returns the number of columns needed to display the string.
# Unlike POSIX's wcwidth(3), the argument to this library's "wcwidth" function
# can be any number of characters long. When the argument represents a single
# UTF-8 character, -1 is returned if the width is unknown, but if there are
# multiple characters in the string, characters with unknown widths are treated
# as "�" which means they have a width of 1.
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
    WCWIDTH_REPLACEMENT_CHARACTER_CODE_POINT = 65533  # "�"
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
    }
}

# Return the number of columns needed to display a string.
#
# Arguments:
# - _val: A string of any length or, when the value of "WCWIDTH_MULTIBYTE_SAFE"
#   is 0, an integer representing a Unicode code point.
#
# Returns: The number of columns needed to display the string.
#
function wcwidth(_val,    _cols, _len, _max, _many, _min, _mid, _n, _w, _x)
{
    _len = length(_val)

    if (!_len) {
        return 0
    }

    if (!WCWIDTH_MULTIBYTE_SAFE) {
        split(" " _val "X" _val, _x, "X")

        # Check the type of the "_val" argument. If it's a string, translate
        # each UTF-8 rune to a numeric code point. The type checking logic was
        # adapted from code written by Steven Penny
        # (https://github.com/svnpenn/stdlib/blob/45df8cf/libstd.awk#L460-L472).
        if (_val != _x[1]) {
            _many = 0
            _cols = 0

            while (length(_val)) {
                # Optimization for ASCII text.
                _cols += length(_val)
                _many = sub(/^[\040-\176]+/, "", _val) || _many
                _cols -= length(_val)

                if (!match(_val, WCWIDTH_UTF8_RUNE_REGEX)) {
                    break
                }

                _w = wcwidth(_wcwidth_code_point(substr(_val, RSTART, RLENGTH)))
                _cols += _w == -1 ? 1 : _w
                _val = substr(_val, RLENGTH + 1)
                _many = _many || length(_val)
            }

            return _many ? _cols : _w
        }

    } else if (_len > 1) {
        # Optimization for ASCII and Latin 1 (ISO 8859-1) text.
        _cols += _len
        gsub(/[\040-\176\240-\254\256-\377]+/, "", _val)
        _len = length(_val)
        _cols -= _len

        for (_n = 1; _n <= _len; _n++) {
            _w = wcwidth(substr(_val, _n, 1))
            _cols += (_w == -1 ? 1 : _w)
        }

        return _cols
    }

    if (!WCWIDTH_TABLE_LENGTH) {
        _wcwidth_unpack_data()
    } else if (_val in WCWIDTH_CACHE) {
        return WCWIDTH_CACHE[_val]
    }

    # Do a binary search to find the width of the character.
    _min = 0
    _max = WCWIDTH_TABLE_LENGTH - 1
    _w = -2

    while (_min <= _max) {
        _mid = int((_min + _max) / 2)

        if (_val > WCWIDTH_RANGE_END[_mid]) {
            _min = _mid + 1
        } else if (_val < WCWIDTH_RANGE_START[_mid]) {
            _max = _mid - 1
        } else {
            _w = WCWIDTH_RANGE_WIDTH[_mid]
            break
        }
    }

    if (_w == -2) {
        _w = _val == "\000" ? 0 : -1
    }

    WCWIDTH_CACHE[_val] = _w

    return _w
}

# Convert a sequence of bytes to a Unicode code point.
#
# Arguments:
# - _bytes: A string of bytes.
#
# Returns:
# - -1: The length of "_bytes" is 0 or greater than 4.
# - `WCWIDTH_REPLACEMENT_CHARACTER_CODE_POINT`: The bytes are not a valid UTF-8
#   sequence.
# - If the bytes are a valid UTF-8 sequence, the corresponding code point is
#   returned.
#
function _wcwidth_code_point(_bytes,    _i, _l, _len, _n, _value)
{
    if (!WCWIDTH_ASCII_TABLE_POPULATED) {
        for (_i = 0; _i < 256; _i++) {
            WCWIDTH_BYTE_VALUES[sprintf("%c", _i)] = _i
        }

        WCWIDTH_ASCII_TABLE_POPULATED = 1
    }

    _value = -1
    _len = length(_bytes)

    if (!_len || _len > 4) {
        return -1
    }

    _n = WCWIDTH_BYTE_VALUES[substr(_bytes, 1, 1)]

    if (_len == 1) {
        return _n < 128 ? _n : WCWIDTH_REPLACEMENT_CHARACTER_CODE_POINT
    }

    if (int(_n / 32) == 6) {         #   0b110
        _value = _n % 32
        _l = 2
    } else if (int(_n / 16) == 14) { #  0b1110
        _value = _n % 16
        _l = 3
    } else if (int(_n / 8) == 30) {  # 0b11110
        _value = _n % 8
        _l = 4
    } else {
        _l = 0
    }

    if (_len != _l) {
        return WCWIDTH_REPLACEMENT_CHARACTER_CODE_POINT
    }

    for (_i = 2; _i <= _len; _i++) {
        #      = _value << 6 | (... & 0b00111111)
        _value = _value * 64 + WCWIDTH_BYTE_VALUES[substr(_bytes, _i, 1)] % 128
    }

    return _value
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
