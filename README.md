wcwidth.awk
===========

This AWK library provides a "wcwidth" function that accepts a string as its
only argument and returns the number of columns needed to display the string.
Unlike POSIX's [_wcwidth(3)_][wcwidth.3], the argument to this library's
"wcwidth" function can be any number of characters long. Bytes in invalid UTF-8
sequences are treated as "�" which means they have a width of 1.

The code is written to be as portable as possible. If the AWK interpreter
processing the library does not have native support for multi-byte characters,
the library will fall back to using its own UTF-8 logic. The library has been
successfully tested with the following AWK implementations:

- [BusyBox AWK][busybox]
- [GNU Awk][gawk]
- [MAWK][mawk]
- [Original AWK a.k.a "The One True Awk"][original-awk]

  [wcwidth.3]: http://pubs.opengroup.org/onlinepubs/9699919799/functions/wcwidth.html
  [busybox]: https://busybox.net/
  [gawk]: https://www.gnu.org/software/gawk/
  [mawk]: http://invisible-island.net/mawk/mawk.html
  [original-awk]: https://packages.debian.org/wheezy/original-awk

Using The Library
-----------------

A "wcwidth.awk" file generated using GNU libc 2.24 is included with this
repository. It should be sourced using AWK's "-f" option (or any equivalent
construct) before any files that make use of the "wcwidth" function. The
library will only use the "exit" statement if it appears the library will not
work with the AWK interpreter.

Example:

    $ cat example.awk
    {
        print $1 ":", wcwidth($1)
    }
    $ echo "A宽BデC🦀D" | awk -f wcwidth.awk -f example.awk
    A宽BデC🦀D: 10

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
