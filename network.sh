# Set up networking on the device

up() {
	cp /etc/resolv.conf "${TARGET}/etc/resolv.conf"
	echo "${DEVNAME}" > "${TARGET}/etc/hostname"
}
