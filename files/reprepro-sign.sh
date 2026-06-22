#!/bin/sh

# From the SignWith section of reprepro(1):
#   A '!' hook script is looked for in the confdir, unless it starts with ~/, ./,
#   +b/, +o/, +c/ or / . Is gets three command line arguments: The filename to
#   sign, an empty argument or the filename to create with an inline signature
#   (i.e. InRelease) and an empty argument or the filename to create an detached
#   signa‐ ture (i.e. Release.gpg). The script may generate no Release.gpg file
#   if it choses to (then the repository will look like unsigned for older
#   clients), but generating empty files is not allowed. Reprepro waits for the
#   script to finish and will abort the exporting of the distribution this
#   signing is part of un‐ less the scripts returns normally with exit code 0.
#   Using a space after ! is recommended to avoid incompatibilities with possible
#   future extensions.

SIGN_THIS_FILE="$1"
INLINE_OUTPUT="$2"
SIGFILE_OUTPUT="$3"

. "$HOME/.buildfarm/reprepro-sign-config.sh"

if [ -z "$SIGN_THIS_FILE" ]; then
	echo "No valid file to sign!" >&2
	exit 1
fi

if [ -n "$INLINE_OUTPUT" ]; then
	# shellcheck disable=SC2086  # We rely on word splitting for GPG_OPTS and KEY_OPTS
	if ! gpg --batch --no $GPG_OPTS $KEY_OPTS --output "$INLINE_OUTPUT" --clearsign "$SIGN_THIS_FILE" ; then
		echo "Unable to clearsign $SIGN_THIS_FILE as $INLINE_OUTPUT" >&2
		exit 2
	fi
fi

if [ -n "$SIGFILE_OUTPUT" ]; then
	# shellcheck disable=SC2086  # We rely on word splitting for GPG_OPTS and KEY_OPTS
	if ! gpg --batch --no $GPG_OPTS $KEY_OPTS --output "$SIGFILE_OUTPUT" --sign "$SIGN_THIS_FILE"; then
		echo "Unable to sign $SIGN_THIS_FILE as $SIGFILE_OUTPUT" >&2
		exit 2
	fi
fi
