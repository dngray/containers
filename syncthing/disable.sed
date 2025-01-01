#!/bin/sed -f
# sed -i -r -f disable.sed <file>

s/(globalAnnounceEnabled=")[^"]+"/\1false"/
s/(natEnabled=")[^"]+"/\1false"/
s/(relaysEnabled=")[^"]+"/\1false"/
s/(crashReportingEnabled=")[^"]+"/\1false"/
