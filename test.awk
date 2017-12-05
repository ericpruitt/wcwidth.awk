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
}

WIDTH_DATA_TEST {
    sub(/#.*/, "")

    if (!NF) {
        next
    } else if (NF != 3) {
        abort("expected 3 columns but this line has %d", NF)
    }

    for (i = 2; i <= 3; i++) {
        # This is the range of the leading ("high") code points in UCS
        # surrogate pairs. The values normally cannot appear in isolation and
        # are therefore not valid wide characters.
        if ($i >= 55296 && $i <= 57343) {
            continue
        }

        w = wcwidth(WCWIDTH_MULTIBYTE_SAFE ? sprintf("%c", $i) : $i)
        checked++

        if (w != $1) {
            here(TERSE, "wcwidth(%d) => %d ≠ %d", $i, w, $1)
            failed++
        }
    }
}

GENERIC_TEST {
    if ((getline expect < expect_filename) == -1) {
        abort("%s: %s", expect_filename, length(ERRNO) ? ERRNO : "I/O error")
    }

    checked += !!NF
    result = wcwidth($0)

    if (result != expect) {
        here(TERSE, "expected wcwidth to return %s, not %s", expect, result)
        failed++
    }
}

END {
    if (exit_status != 2) {
        test_done()
    }

    exit exit_status
}
