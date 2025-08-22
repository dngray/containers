include compose/compose.mk
include run/run.mk

SHELL=/bin/sh
UID := $(shell id -u)
CMD := docker

list:
	sudo ${CMD} ps -all
	sudo ${CMD} images
	sudo ${CMD} network ls

.PHONY: all-down
all-down:
	sudo ${CMD} stop $$(sudo ${CMD} ps -aq)

.PHONY: all-remove
all-remove:
	sudo ${CMD} rm $$(sudo ${CMD} ps -aq)
	sudo ${CMD} network prune
