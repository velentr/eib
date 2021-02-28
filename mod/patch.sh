# Patch the rootfs with static files

up() {
	rsync -av ${DIRECTORIES} "${TARGET}"
}
