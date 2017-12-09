wcwidth.awk
===========

The standard "length" function in AWK counts the number of characters in a
string which does not necessarily correspond to the visual width of the string.
This AWK library provides functions that can be used to determine the width of
UTF-8 characters even on interpreters that are not multi-byte safe. In addition
to reimplementations of the POSIX functions [_wcwidth(3)_][wcwidth.3] and
[_wcswidth(3)_][wcswidth.3], this library provides a "columns" function with
graceful degradation in the presence of characters that would cause the POSIX
functions to return -1.

The library is written so as to be portable across AWK interpreters; if the
interpreter does not have native support for multi-byte characters, the library
will fall back to using its own UTF-8 logic. This library has been successfully
tested with these AWK implementations:

- [BusyBox AWK][busybox]
- [GNU Awk][gawk]
- [MAWK][mawk]
- [Original AWK a.k.a "The One True Awk"][original-awk]

  [wcwidth.3]: http://pubs.opengroup.org/onlinepubs/9699919799/functions/wcwidth.html
  [wcswidth.3]: http://pubs.opengroup.org/onlinepubs/9699919799/functions/wcswidth.html
  [busybox]: https://busybox.net/
  [gawk]: https://www.gnu.org/software/gawk/
  [mawk]: http://invisible-island.net/mawk/mawk.html
  [original-awk]: https://packages.debian.org/wheezy/original-awk

Usage and Functions
-------------------

A "wcwidth.awk" file generated using GNU libc 2.24 is included with this
repository. It should be sourced using AWK's "-f" option (or any equivalent
construct) before any files that make use of this library's functions. The
library will only use the "exit" statement if it appears the library will not
work with the AWK interpreter.

### columns(_string_) ###

Determine the number of columns needed to display a string. This function
differs from the "wcswidth" function in its handling of non-printable
characters; instead of making the function abort and immediately return -1,
non-printable characters with a code point at or below 255 are ignored while
all others are treated as having a width of 1 because they will typically be
rendered as a single-column [".notdef" glyph][notdef-glyph].

  [notdef-glyph]: https://www.microsoft.com/typography/otspec/recom.htm

**Arguments:**
- **string**: A string of any length. In AWK interpreters that are not
  multi-byte safe, this argument is interpreted as a UTF-8 encoded string.

**Returns:** The number of columns needed to display the string. This value will
always be greater than or equal to 0.

**Example:**

    $ cat example.awk
    {
        printf "columns(\"%s\") → %s\n", $0, columns($0)
    }
    $ echo "A宽BデC🦀D" | awk -f wcwidth.awk -f example.awk
    columns("A宽BデC🦀D") → 10

### wcswidth(_string_) ###

A reimplementation of the [POSIX function of the same name][wcswidth.3] to
determine the number of columns needed to display a string.

**Arguments:**
- **string**: A string of any length. In AWK interpreters that are not
  multi-byte safe, this argument is interpreted as a UTF-8 encoded string.

**Returns:** The number of columns needed to display the string is returned if
all of character are printable and -1 if any are not.

**Example:**

    $ cat example.awk
    {
        printf "wcswidth(\"%s\") → %s\n", $0, wcswidth($0)
    }
    $ printf "津波\n概要\t20世紀\n" | awk -f wcwidth.awk -f example.awk
    wcswidth("津波") → 4
    wcswidth("概要	20世紀") → -1

### wcwidth(_character_) ###

A reimplementation of the [POSIX function of the same name][wcwidth.3] to
determine the number of columns needed to display a single character.

**Arguments:**
- **character**: A single character. In AWK interpreters that are not
  multi-byte safe, this argument may consist of multiple characters that
  together represent a single UTF-8 encoded code point.

**Returns:** The number of columns needed to display the character if it is
printable and -1 if it is not. If the argument does not contain exactly one
UTF-8 character, -1 is returned.

**Example:**

    $ cat example.awk
    {
        printf "wcwidth(\"%s\") → %s\n", $0, wcwidth($0)
    }
    $ printf "X\n宽\n:)\n" | awk -f wcwidth.awk -f example.awk
    wcwidth("X") → 1
    wcwidth("宽") → 2
    wcwidth(":)") → -1

Development
-----------

Unicode data is generated using the code in "generate-width-data.c" and written
to "width-data". This data is inserted into "template.awk" on the line with the
comment containing "XXX", and the resulting file is written to "wcwidth.awk".

Makefile Targets:

- **all / test:** Verify that the "wcwidth" function works as expected. If
  "wcwidth.awk" does not exist, it will be created automatically. This target
  is the default target.
- **width-data:** Enumerate all Unicode code points and write the information
  to a file named "width-data". The existing file provided with this repository
  was generated using GNU libc 2.24. If the values returned by "wcwidth.awk" do
  not seem to match the behavior of the host's _wcwidth(3)_ implementation,
  delete "width-data" and run `make` to regenerate a properly tailored file.
- **clean:** Delete the binary used to generate the "width-data" file.
- **wcwidth.awk:** Generate the "wcwidth.awk" file.
