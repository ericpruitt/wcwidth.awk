function here(show, format, a, b, c, d, e, f)
{
    if (show) {
        printf "%s:%s: " format "\n", FILENAME, FNR, a, b, c, d, e, f
    }
}

function test_state_reset()
{
    checked = 0
    failed = 0

    if (length(expect_filename)) {
        close(expect_filename)
    }
}

function test_done()
{
    if (WIDTH_DATA_TEST && !checked) {
        print "no character range endpoints were tested"
        exit_status = 1
    } else if (failed) {
        print failed, "of", checked, "checks failed"
        exit_status = 1
    }

    test_state_reset()

}

function abort(format, a, b, c, d, e, f)
{
    if (length(format)) {
        printf format "\n", a, b, c, d, e, f
    }

    exit (exit_status = 2)
}

BEGIN {
    ALWAYS = 1
    split("", WIDTH_DATA_FILES)

    for (i = 0; i < ARGC; i++) {
        if (index(ARGV[i], "width-data:") == 1) {
            sub(/^[^:]+:/, "", ARGV[i])
            WIDTH_DATA_FILES[ARGV[i]] = 1
        }
    }

    expect_filename = ""
    previous_filename = ""
    exit_status = 0

    test_state_reset()
}

FILENAME != previous_filename {
    if (length(previous_filename)) {
        test_done()
    }

    WIDTH_DATA_TEST = FILENAME in WIDTH_DATA_FILES
    GENERIC_TEST = !WIDTH_DATA_TEST

    if (GENERIC_TEST) {
        expect_filename = FILENAME
        sub(/\.[^.]+$/, ".widths", expect_filename)
    }

    if (WIDTH_DATA_TEST && !length(previous_filename)) {
        invalid_for_posix = "abc\txyz"

        if ((result = wcswidth(invalid_for_posix)) != (expect = -1)) {
            printf "wcswidth(invalid_for_posix) => %d ≠ %d\n", result, expect
            exit_status = 1
        }

        if ((result = columns(invalid_for_posix)) != (expect = 6)) {
            printf "columns(invalid_for_posix) => %d ≠ %d\n", result, expect
            exit_status = 1
        }
    }

    previous_filename = FILENAME
}

WIDTH_DATA_TEST {
    sub(/#.*/, "")

    if (!NF) {
        next
    } else if (NF != 3) {
        abort("expected 3 columns but this line has %d", NF)
    }

    for (i = 2; i == 2 || (i == 3 && $2 != $3); i++) {
        value = 0 + $i

        # This is the range of the leading ("high") code points in UCS
        # surrogate pairs. The values normally cannot appear in isolation and
        # are therefore not valid wide characters.
        if (value >= 55296 && value <= 57343) {
            continue
        }

        if (WCWIDTH_MULTIBYTE_SAFE || value < 128) {
            character = sprintf("%c", value)
        } else {
            character = ""
            len = (v = value) >= 65536 ? 4 : v >= 2048 ? 3 : v >= 128 ? 2 : 1

            for (divisor = 1; len-- > 1; divisor *= 2) {
                character = sprintf("%c", 128 + v % 64) character
                v = int(v / 64)
            }

            character = sprintf("%c", (1920 / divisor) % 256 + v) character
        }

        if (!length(character) && !value) {
            continue
        }

        w = wcswidth(character)

        checked++

        if (w != $1) {
            here(TERSE, "wcswidth(%d) => %d ≠ %d", value, w, $1)
            failed++
        }
    }
}

GENERIC_TEST {
    if ((getline expect < expect_filename) == -1) {
        abort("%s: %s", expect_filename, length(ERRNO) ? ERRNO : "I/O error")
    }

    checked += !!NF
    result = columns($0)

    if (result != expect) {
        here(TERSE, "expected wcswidth to return %s, not %s", expect, result)
        failed++
    }
}

END {
    if (exit_status != 2) {
        test_done()
    }

    exit exit_status
}
