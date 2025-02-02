wcwidth.awk
===========

The standard "length" function in AWK counts the number of characters in a
string which does not necessarily correspond to the visual width of the string.
This AWK library provides functions that can be used to determine the width of
UTF-8 characters even on interpreters that are not multi-byte safe. In addition
to reimplementations of the POSIX functions [_wcwidth(3)_][wcwidth.3] and
[_wcswidth(3)_][wcswidth.3], this library provides "wcscolumns", a function
with graceful degradation in the presence of characters that would cause the
POSIX functions to return -1; "wcstruncate", a function for truncating a string
to a specific visual column; and "wcsexpand", a function that expands tabs to
spaces in a wide character-aware manner.

The library is written so as to be portable across AWK interpreters; if the
interpreter does not have native support for multi-byte characters, the library
will fall back to using its own UTF-8 logic. This library has been successfully
tested with these AWK implementations:

- [BusyBox AWK][busybox]
- [GNU Awk][gawk]
- [MAWK][mawk]
- [Original AWK a.k.a "The One True Awk"][original-awk]

The width data used by the preexisting "wcwidth.awk" comes from version 2.36 of
the [GNU C Library][glibc], but it can be rebuilt to tailor to other systems
using instructions in the _Development_ section at the end of this document.

  [wcwidth.3]: http://pubs.opengroup.org/onlinepubs/9699919799/functions/wcwidth.html
  [wcswidth.3]: http://pubs.opengroup.org/onlinepubs/9699919799/functions/wcswidth.html
  [busybox]: https://busybox.net/
  [gawk]: https://www.gnu.org/software/gawk/
  [mawk]: http://invisible-island.net/mawk/mawk.html
  [original-awk]: https://packages.debian.org/wheezy/original-awk
  [glibc]: https://www.gnu.org/software/libc/

Usage and Functions
-------------------

The entirety of the library is contained in the "wcwidth.awk" file included
with this repository. The library has no dependencies (the other files in this
repository are for development purposes), so installation consists of copying
"wcwidth.awk" somewhere convenient. To use the functions in the library, source
the file using AWK's "-f" option or any equivalent construct like GNU Awk's
["@include"][gawk-include]. The library only uses "exit" if the library is
incompatible with the interpreter. In that case, "WCWIDTH_INITIALIZED" is set
to -1 so failed initialization can be detected with `WCWIDTH_INITIALIZED < 0`
in an "END" block. The special AWK variables "RSTART" and "RLENGTH" will always
have the same values after calling one of these functions as they did prior to
the invocation.

  [gawk-include]: https://www.gnu.org/software/gawk/manual/html_node/Include-Files.html

### wcscolumns(_string_) ###

Determine the number of columns needed to display a string. This function
differs from the "wcswidth" function in its handling of non-printable
characters; instead of making the function abort and immediately return -1,
non-printable ASCII characters are ignored while all others are treated as as
having a width of 1 because they will typically be rendered as a single-column
[".notdef" glyph][notdef-glyph].

  [notdef-glyph]: https://www.microsoft.com/typography/otspec/recom.htm

**Arguments:**
- **string**: A string of any length. In AWK interpreters that are not
  multi-byte safe, this argument is interpreted as a UTF-8 encoded string.

**Returns:** The number of columns needed to display the string. This value will
always be greater than or equal to 0.

**Example:**

    $ cat example.awk
    {
        printf "wcscolumns(\"%s\") → %s\n", $0, wcscolumns($0)
    }
    $ echo "A宽BデC🦀D" | awk -f wcwidth.awk -f example.awk
    wcscolumns("A宽BデC🦀D") → 10

### wcsexpand(_string_, _tab_stop_) ###

Expand tabs to spaces in a wide character-aware manner. Calculations done by
this function assume the first character of the string is the first character
of the line or the first character following a tab.

**Arguments:**

- **string**: The string to expand.
- **tab_stop**: The maximum width of tabs. This must be an integer greater than
  zero.

**Returns:** A string with all tabs replaced with spaces.

**Example:**

    $ cat example.awk
    {
        printf "wcsexpand(\"%s\", 8) → %s\n", $0, wcsexpand($0, 8)
    }
    $ printf "Rat\t鼠\t2020\n" | awk -f wcwidth.awk -f example.awk
    wcsexpand("Rat	鼠	2020", 8) → Rat     鼠      2020

### wcstruncate(_string_, _columns_) ###

Truncate a string so that it spans a limited number of columns.

**Arguments:**
- **string**: A string of any length. In AWK interpreters that are not
  multi-byte safe, this argument is interpreted as a UTF-8 encoded string.
- **columns**: Maximum number of columns the resulting text may span.

**Returns:** Input string truncated as needed.

**Example:**

    $ cat example.awk
    {
        printf "wcstruncate(\"%s\", %d) → %s\n", $1, $2, wcstruncate($1, $2)
    }
    $ printf "AエBビCシ 5\nxYzPqR 10\n" | awk -f wcwidth.awk -f example.awk
    wcstruncate("AエBビCシ", 5) → AエB
    wcstruncate("xYzPqR", 10) → xYzPqR

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
to "width-data". This data is inserted into "template.awk" on the line
consisting of a comment that contains "[WIDTH DATA]", and the resulting file is
written to "wcwidth.awk".

Makefile Targets:

- **all / test:** Verify that the "wcwidth" function works as expected. If
  "wcwidth.awk" does not exist, it will be created automatically. This target
  is the default target.
- **width-data:** Enumerate all Unicode code points and write the information
  to a file named "width-data". The existing file provided with this repository
  was generated using GNU libc 2.36. If the values returned by "wcwidth.awk" do
  not seem to match the behavior of the host's _wcwidth(3)_ implementation,
  delete "width-data" and run `make` to regenerate a properly tailored file.
- **clean:** Delete the binary used to generate the "width-data" file.
- **wcwidth.awk:** Generate the "wcwidth.awk" file.
