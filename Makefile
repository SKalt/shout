# © Steven Kalt
# SPDX-License-Identifier: BSD-3-Clause

./shout.sh: ./shout.posix.awk ./VERSION
	./shout.sh --replace ./shout.sh
.PHONY: test
test:
	./shout.sh --check ./README.md
