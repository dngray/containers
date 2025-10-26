include compose/compose.mk
include run/run.mk

SHELL=/bin/sh
UID := $(shell id -u)
GID := $(shell id -g)
CMD := docker

list:
	sudo ${CMD} ps -all
	sudo ${CMD} images
	sudo ${CMD} network ls

.PHONY: all-down
all-down:
	@sudo ${CMD} ps -aq | xargs -r sudo ${CMD} stop

.PHONY: all-remove
all-remove:
	@sudo ${CMD} ps -aq | xargs -r sudo ${CMD} rm
	@sudo ${CMD} network prune -f
