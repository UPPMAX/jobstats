PANDOC = pandoc

all: README.html

README.html: README.md
	$(PANDOC) -f markdown -t html -o $@ $^

