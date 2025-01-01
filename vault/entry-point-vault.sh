#!/bin/sh
exec vault server -config=/vault/config/vault.hcl $@
