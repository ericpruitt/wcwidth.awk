.POSIX:
.SUFFIXES: .gutenberg .text

# List of Project Gutenberg book numbers. This should consit of at least one
# ASCII book, one book composed mostly of CJK characters and one book that
# includes non-ASCII Latin character (e.g. French, Spanish, etc.).
CORPUS = 1493 2650-0 25229-0

TLS_PROJECT_GUTENBERG_MIRRORS = \
	https://mirror.csclub.uwaterloo.ca/gutenberg \
	https://mirrors.xmission.com/gutenberg \
	https://www.mirrorservice.org/sites/ftp.ibiblio.org/pub/docs/books/gutenberg \

WGET = wget --max-redirect="0" --no-verbose --no-use-server-timestamps

all: LANGUAGE_CORPORA

.DEFAULT:
	@case "$@" in \
	  *.gutenberg) \
		file="$@" && file="$${file%.gutenberg}" && id="$${file%%-*}"; \
		test "$$id" -gt 0; \
		set -- $(TLS_PROJECT_GUTENBERG_MIRRORS); \
		random_integer="$$(od -A n -N 4 -t u4 -v /dev/urandom)"; \
		eval 'mirror_root=$$'"$$((random_integer % $$# + 1))"; \
		file_path=$$( \
			echo "$$id" \
			| sed -e 's:[0-9]:\0/:g' -e 's:..$$:'"$$id/$$file"':' \
		); \
		$(WGET) -O $@ "$$mirror_root/$$file_path.txt"; \
	  ;; \
	  *) \
		echo ".DEFAULT: no rule to make target '$@'." >&2; \
		exit 2; \
	  ;; \
	esac

.gutenberg.text:
	tr -d "\r" < $< > $@

wcswidths: wcswidths.c
	$(CC) -o $@ $?

LANGUAGE_CORPORA: $(CORPUS:=.gutenberg) $(CORPUS:=.text) wcswidths
	rm -f *-corpus.text *-corpus.widths
	for path in $?; do \
		case "$$path" in \
		  *.text) ;; \
		  *) continue ;; \
		esac; \
		language=$$(awk ' \
			FNR >= 100 { \
				print FILENAME ": language not found"; \
				exit 1; \
			} \
			$$1 == "Language:" { \
				gsub(/^[ \t]*Language:[ \t]*|[ \t]+$$/, ""); \
				print tolower($$NF); \
					exit; \
				}' "$$path" \
		); \
		cat "$$path" >> "$$language-corpus.text"; \
	done
	for path in *-corpus.text; do \
		./wcswidths < "$$path" > "$${path%.text}.widths"; \
	done
	touch $@

clean:
	rm -f LANGUAGE_CORPORA *.gutenberg *.text *.tmp *.widths

cleaner:
	rm -f wcwidths
