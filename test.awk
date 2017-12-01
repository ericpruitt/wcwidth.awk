BEGIN {
    wcwidth_tested_values = 0
    wcwidth_incorrect_values = 0
}

{
    sub(/#.*/, "")

    if (NF != 3) {
        next
    }

    for (i = 2; i <= 3; i++) {
        # This is the range of the leading ("high") code points in UCS
        # surrogate pairs. The values normally cannot appear in isolation and
        # are therefore not valid wide characters.
        if ($i >= 55296 && $i <= 57343) {
            continue
        }

        w = wcwidth(WCWIDTH_MULTIBYTE_SAFE ? sprintf("%c", $i) : $i)
        wcwidth_tested_values++

        if (w == $1) {
            continue
        }

        printf "%s line %d: wcwidth(%d) => %d ≠ %d\n", FILENAME, FNR, $i, w, $1
        wcwidth_incorrect_values++
    }
}

END {
    if (!wcwidth_tested_values) {
        print "no values were tested"
        exit 2
    } else if (wcwidth_incorrect_values) {
        exit 2
    }
}
