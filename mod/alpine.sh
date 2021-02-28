# Install alpine packages using apk

find_apk() {
	if [ -n "${APK_PATH}" ]; then
		echo "${APK_PATH}"
	else
		echo apk
	fi
}

up() {
	APK="$(find_apk)"
	${APK}	-X "${MIRROR}/${VERSION}/main" \
		-X "${MIRROR}/${VERSION}/community" \
		--update-cache \
		--root "${TARGET}" \
		--arch "${ARCH}" \
		--keys-dir "${KEYS}" \
		--initdb \
		add ${PACKAGES} | cat

	echo "${MIRROR}/${VERSION}/main" >> "${TARGET}/etc/apk/repositories"
	echo "${MIRROR}/${VERSION}/community" >> "${TARGET}/etc/apk/repositories"
}

fix() {
	apk fix

	rc-update add devfs sysinit
	rc-update add dmesg sysinit
	rc-update add mdev sysinit

	rc-update add hwclock boot
	rc-update add modules boot
	rc-update add sysctl boot
	rc-update add hostname boot
	rc-update add bootmisc boot
	rc-update add syslog boot

	rc-update add mount-ro shutdown
	rc-update add killprocs shutdown
	rc-update add savecache shutdown

	for s in ${SERVICES}; do
		rc-update add ${s} boot
	done
}

down() {
	if [ -n "${RMPACKAGES}" ]; then
		APK="$(find_apk)"
		${APK}	--root "${TARGET}" \
			--arch "${ARCH}" \
			--purge \
			del ${RMPACKAGES}
	fi
}
