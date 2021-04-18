# Generate a pack for flashing the image

down() {
	cat << ENDFLASHER > "${NAME}"
#!/bin/sh

extract() {
	  line=\`awk '/^__ROOTFS__/ { print NR + 1; exit 0; }' \${1}\`
	  outdir="\${2}"
	  mkdir -p "\${outdir}"
	  tail -n+\${line} "\${1}" | base64 -d | gunzip | tar xf - --preserve-permissions --same-owner -C "\${outdir}"
}

extract "\${0}" outdir/

exit 0

__ROOTFS__
ENDFLASHER

	tar cf - -C "${TARGET}" . | gzip | base64 >> "${NAME}"

	chmod +x "${NAME}"
}
