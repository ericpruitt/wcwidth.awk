# Author: Eric Pruitt (https://www.codevat.com)
# License: 2-Clause BSD (http://opensource.org/licenses/BSD-2-Clause)
.POSIX:
.SILENT: test wcwidth.awk

AWK = awk
AWKS = \
	"busybox awk" \
	"gawk --posix" \
	"gawk" \
	"mawk" \
	"original-awk" \

all: test

width-data: generate-width-data.c
	$(CC) -o $(<:.c=) $< && ./$(<:.c=) > $@

clean:
	rm -f generate-width-data

wcwidth.awk: template.awk width-data
	insert=$$( \
		grep -v "^-1 " width-data \
		| tr "\n" "," \
		| fold -w 71 \
		| sed -e 's/^.*$$/    "\0" \\\\/' -e '$$s/," \\\\$$/"/' \
	) && \
	$(AWK) -v insert="$$insert" ' \
		/# XXX/ { \
			print insert; \
			next; \
		} \
		{ \
			print; \
		} \
	' template.awk > $@.tmp
	mv $@.tmp $@
	echo "$@: file generated succesfully"

test: wcwidth.awk
	fallback="$(AWK)" && \
	for awk in $(AWKS); do \
		if ! $$awk "BEGIN { exit }" 2>/dev/null; then \
			test "$$fallback" && awk="$$fallback" || continue; \
		fi; \
		fallback=""; \
		printf "%-24s" "$$awk:"; \
		$$awk -f wcwidth.awk -f test.awk width-data; \
		echo " OK"; \
	done
