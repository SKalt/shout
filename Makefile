./shout.sh: ./shout.posix.awk ./VERSION
	./shout.sh --replace ./shout.sh
.PHONY: test
test:
	./shout.sh --verbose --check ./README.md ./shout.sh ./tests/inline.in.txt 2>&1 | \
		tee /tmp/test.log | \
		grep ERRR
