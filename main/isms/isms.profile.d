# Sourced by /etc/profile (every login shell) - see /etc/profile.d/*.sh's
# standard Alpine convention. Without this, `isms server migrate` (or any
# other isms admin command run BY HAND, outside isms.initd) had no way to
# find /etc/isms/server.env on its own: isms.initd exports ISMS_SERVER_ENV
# before exec'ing the daemon, but that only ever applies to the daemon's
# own process, never to an interactive shell an operator opens separately -
# confirmed the hard way, `isms server migrate` failing with "DATABASE_URL
# is required" even though the real value was sitting right there in
# server.env the whole time.
#
# ${ISMS_SERVER_ENV:-...} - never overrides an operator's own explicit
# override (matches isms.initd's own default-with-override pattern in
# /etc/conf.d/isms).
export ISMS_SERVER_ENV="${ISMS_SERVER_ENV:-/etc/isms/server.env}"
