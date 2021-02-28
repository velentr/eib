#!/bin/sh
# Wrapper for calling a given stage for the given set of modules.

EIB_PATH=opt/eib

is_function() {
	# TODO make this actually check for a function
	type "$1" > /dev/null 2>&1
}

do_up() {
	# An empty TARGET variable will cause us to try to install things to
	# root; exit immediately so we don't accidentally corrupt the user's
	# system.
	if [ -z "$TARGET" ]; then
		echo '$TARGET is empty: aborting' 1>&2
		exit 1
	fi

	unset -f up
	. "${1}"
	if is_function up; then
		up
		unset -f up
	fi
}

do_fix() {
	unset -f fix
	. "${1}"
	if is_function fix; then
		fix
		unset -f fix
	fi
}

do_down() {
	# An empty TARGET variable will cause us to try to install things to
	# root; exit immediately so we don't accidentally corrupt the user's
	# system.
	if [ -z "$TARGET" ]; then
		echo '$TARGET is empty: aborting' 1>&2
		exit 1
	fi

	unset -f down
	. "${1}"
	if is_function down; then
		down
		unset -f down
	fi
}

stage="$1"
shift
modules="$@"

case "$stage" in
	up|fix|down)
		echo "running stage: $stage"
		;;
	*)
		echo error
		exit 1
		;;
esac

for m in $modules; do
	if [ ! -f "$m" ]; then
		echo "$m does not exist!"
		exit 1
	fi
	echo "  $m"
	do_${stage} "$m"
done
