#!/usr/bin/env -S dash -e

. $PWD/build.cfg

[ ! -d "$ROOTFS" ] && mkdir -pv "$ROOTFS" 
[ ! -d "$IMAGEDIR" ] && mkdir -pv "$IMAGEDIR" 
[ ! -d "$TEMPDIR" ] && mkdir -pv "$TEMPDIR" 

xinstall() {
	XBPS_ARCH=x86_64 xbps-install \
                     --repository=https://mirror.fit.cvut.cz/voidlinux/current \
                     --repository=/usr/local/src/wael-packages/hostdir/binpkgs/tinyramfs \
		             "$@"
}

make_iso() {
	"$ROOTFS"/usr/bin/xorriso -as mkisofs \
		-iso-level 3 -rock -joliet -max-iso9660-filenames -omit-period \
        -isohybrid-mbr "$IMAGEDIR"/boot/syslinux/isohdpfx.bin \
        -eltorito-boot boot/syslinux/isolinux.bin \
        -eltorito-catalog boot/syslinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
    	-e --interval:appended_partition_2:all:: \
    	-append_partition 2 0xef "$TEMPDIR"/efiboot.img  \
		-isohybrid-gpt-basdat -no-emul-boot \
		-volid "$VOLID" \
		-output chaos-001.iso "$IMAGEDIR"
}

syslinux_init() {
	mkdir -pv "$IMAGEDIR"/boot/syslinux
	cp -v "$FILESDIR"/syslinux.cfg "$IMAGEDIR"/boot/syslinux/
	for file in isohdpfx.bin isolinux.bin ldlinux.c32 libcom32.c32 libutil.c32; do
		cp "$ROOTFS"/usr/lib/syslinux/$file "$IMAGEDIR"/boot/syslinux/
	done
}

grub_efi_init() {
	mkdir -pv "$IMAGEDIR"/boot/grub
	sed "s/@@VOLID@@/$VOLID/g" "$FILESDIR"/grub-early.cfg > \
		"$IMAGEDIR"/boot/grub-early.cfg
	cp "$FILESDIR"/grub.cfg "$IMAGEDIR"/boot/grub
	
	"$ROOTFS"/usr/bin/grub-mkimage \
		-c "$IMAGEDIR"/boot/grub-early.cfg \
		-p "$IMAGEDIR"/boot/grub \
		-o "$TEMPDIR"/BOOTX64.efi \
        -O x86_64-efi \
		all_video cat configfile disk echo efi_gop efi_uga fat gzio help \
		iso9660 linux ls multiboot2 normal part_gpt part_msdos search search_label test true

	dd if=/dev/zero of="$TEMPDIR"/efiboot.img count=4096
	mkdosfs -n CHAOS_EFI "$TEMPDIR"/efiboot.img
	mkdir -pv "$TEMPDIR"/efiboot
	mount -o loop "$TEMPDIR"/efiboot.img "$TEMPDIR"/efiboot
	mkdir -pv "$TEMPDIR"/efiboot/EFI/BOOT
	cp "$TEMPDIR"/BOOTX64.efi "$TEMPDIR"/efiboot/EFI/BOOT
	umount "$TEMPDIR"/efiboot
}

make_initramfs() {
    mkdir -pv "$ROOTFS"/etc/tinyramfs/hook.d
	cp -rv "$FILESDIR/config" "$ROOTFS"/etc/tinyramfs
    cp -rv "$HOOKSDIR"/tinyramfs/diskless "$ROOTFS"/etc/tinyramfs/hook.d

	sed -i "$ROOTFS"/etc/tinyramfs/hook.d/diskless/diskless.init.late \
		-e "s/@@BASE_PKGS@@/$BASE_PKGS/g" \
		-e "s/@@HOSTNAME@@/$CHAOS_HOSTNAME/g" \
		-e "s/@@USERNAME@@/$CHAOS_USERNAME/g" \
		-e "s/@@ROOTPASS@@/$CHAOS_ROOTPASS/g" \
		-e "s/@@USERPASS@@/$CHAOS_USERPASS/g"

	sed -i "s/@@VOLID@@/$VOLID/g" "$ROOTFS"/etc/tinyramfs/config 

	"$ROOTFS"/usr/bin/xchroot "$ROOTFS" 'xbps-reconfigure -f linux5.18' 
}

xinstall -A -f -r "$ROOTFS" -c "$PACKAGESDIR" -Sy ${BASE_PKGS} 
mkdir -pv "$ROOTFS"/etc/xbps.d
echo "$IGNOREPKGS" > "$ROOTFS"/etc/xbps.d/99-ignore.conf
xinstall -r "$ROOTFS" -c "$CACHEDIR" -y ${ISO_PKGS}  
make_initramfs
grub_efi_init
syslinux_init
cp "$ROOTFS"/boot/vmlinuz* "$IMAGEDIR"/boot/vmlinuz
cp "$ROOTFS"/boot/initramfs* "$IMAGEDIR"/boot/initrd
xbps-rindex -a "$PACKAGESDIR"/*.xbps 1>/dev/null
cp -r "$PACKAGESDIR" "$IMAGEDIR"/pkgs
make_iso
#rm -r "$IMAGEDIR" "$ROOTFS" "$TEMPDIR"
