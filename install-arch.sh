#!/bin/bash

echo "================================================="
echo "         kAFL Archlinux auto-magic installer     "
echo "================================================="

system_check()
{
	echo
	echo "[*] Performing basic sanity checks..."

	if [ ! "`uname -s`" = "Linux" ]; then
		echo "[-] Error: KVM-PT is supported only on Linux ..."
		exit 1
	fi

	grep -q ^flags.*intel_pt /proc/cpuinfo
	if [ $? -ne 0 ]; then
		echo "According to /proc/cpuinfo this system has no intel_pt."
		exit 1
	fi

	dist_id="$(lsb_release -si)"
	if [ "$dist_id" != "Arch" ]; then
		echo "[-] Error: This installer was tested using recent Arch."
		echo
		echo "Other recent Linux distributions will generally work as well but"
		echo "the installer will not be able to resolve the required dependencies."
		echo
		echo "It is recommended to abort the installer and instead follow this"
		echo "script by hand, resolving any build/runtime errors as they come up."
		echo
		echo "Press [Ctrl-c] to abort or [Return] to continue.."
		read
	fi

	for i in pacman sudo; do
		T=`which "$i" 2>/dev/null`
		if [ "$T" = "" ]; then
			echo "[-] Error: '$i' not found, please install first."
			exit 1
		fi
	done

}

system_deps()
{
	echo
	echo "[*] Installing essentials tools ..."
	sudo pacman -S git make gcc bc openssl pax-utils libelf \
		graphviz gnuplot ruby gtk3 glibc flex bison \
		python python-pip python-setuptools python-wheel \
		python-dateutil

	echo "[*] Installing build dependencies for QEMU ..."
  T=`mktemp -d`
  pushd $T
  asp checkout qemu
  cd qemu/trunk
  makepkg -seoc
  popd
  rm -fr $T

  echo "[*] Installing kAFL python dependencies ..."
  pip install -r $KAFL_ROOT/requirements.txt
}

set_env()
{
	test -d $CAPSTONE_ROOT || fatal "Could not find CAPSTONE_ROOT. Missing env setup?"
	test -d $LIBXDC_ROOT || fatal "Could not find LIBXDC_ROOT. Missing env setup?"

	## setup environment for non-global capstone/libxdc builds
	C_INCLUDE_PATH=$CAPSTONE_ROOT/include:$LIBXDC_ROOT
	LIBRARY_PATH=$CAPSTONE_ROOT:$LIBXDC_ROOT/
	LD_LIBRARY_PATH=$CAPSTONE_ROOT:$LIBXDC_ROOT/
	export C_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
}

unset_env()
{
	## unset build environment
	unset C_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
}

build_capstone()
{
	if [ ! -d "$CAPSTONE_ROOT" ]; then
		echo "[!] Could not find CAPSTONE_ROOT - failed to build capstone."
		return
	fi

	#echo "[*] Need to remove any existing (and likely conflicting) capstone install (need sudo)"
	#sudo apt-get remove -y libcapstone3 libcapstone-dev

	echo "[*] Building capstone at $CAPSTONE_ROOT..."
	echo "-------------------------------------------------"
	make -C $CAPSTONE_ROOT -j $jobs
	#echo "[*] Installing capstone v4 branch into system (need sudo)"
	#sudo make -C $CAPSTONE_ROOT install
}

build_libxdc()
{
	if [ ! -d "$LIBXDC_ROOT" ]; then
		echo "[!] Could not find LIBXDC_ROOT - failed to build libxdc."
		return
	fi


	echo "[*] Building libxdc at $LIBXDC_ROOT..."
	echo "-------------------------------------------------"
	set_env
	make -C $LIBXDC_ROOT -j $jobs
	unset_env
	#echo "[*] Installing libxdc branch into system (need sudo)"
	#sudo make -C $LIBXDC_ROOT install

}

build_qemu()
{
	if [ ! -d "$QEMU_ROOT" ]; then
		echo "[!] Could not find QEMU_ROOT - failed to build Qemu."
		return
	fi

	echo
	echo "[*] Building Qemu at $QEMU_ROOT..."
	echo "-------------------------------------------------"
	pushd $QEMU_ROOT > /dev/null
		set_env
		./configure \
			--target-list=x86_64-softmmu \
			--disable-gtk \
			--disable-docs \
			--disable-werror \
			--disable-capstone \
			--disable-libssh \
			--enable-nyx \
			--enable-nyx-static \
			--disable-tools
		make -j $jobs
		unset_env
	popd

	echo
	echo "-------------------------------------------------"
	echo "Qemu build should be done. You do not have to install this"
	echo "patched build into the system. Just update kAFL-Fuzzer/kafl.ini:"
	echo
	echo "  qemu_kafl_location = $QEMU_ROOT/x86_64-softmmu/qemu-system-x86_64"
	echo

}

build_linux()
{

	if [ ! -d "$LINUX_ROOT" ]; then
		echo "[!] Could not find LINUX_ROOT - failed to build Linux."
		return
	fi

	echo "[*] Need to remove any existing (and likely conflicting) linux-nyx install (need sudo)"
	sudo pacman -Rs linux-nyx linux-nyx-headers

	echo
	echo "[*] Building Linux at $LINUX_ROOT..."
	echo "-------------------------------------------------"
  pushd ./kafl/arch-packages/linux/
  makepkg -fs
  # After the first build !!!
  # makepkg -fs --noprepare

	echo "[*] Installing linux-nyx branch into system (need sudo)"
	sudo pacman -U linux-nyx-5.10.73-1-x86_64.pkg.tar.zst linux-nyx-headers-5.10.73-1-x86_64.pkg.tar.zst
  popd

	echo "[*] Configuring GRUB (need sudo)"
	sudo grub-mkconfig -o /boot/grub/grub.cfg
}

build_radamsa()
{

	if [ ! -d "$RADAMSA_ROOT" ]; then
		echo "[!] Could not find RADAMSA_ROOT - failed to build radamsa."
		return
	fi

	echo "[*] Building radamsa at $RADAMSA_ROOT..."
	echo "-------------------------------------------------"
	make -j $jobs -C $RADAMSA_ROOT
	echo "-------------------------------------------------"
}

system_perms()
{
	echo
	echo "[*] Fix permissions for user access to /dev/kvm..."
	echo
	sudo groupmod kvm
	if [ $? -ne 0 ]; then
		echo "Creating group kvm for user $USER to access /dev/kvm.."

		echo "KERNEL==\"kvm\", GROUP=\"kvm\"" | sudo -Eu root tee /etc/udev/rules.d/40-permissions.rules > /dev/null
		sudo groupadd kvm
		sudo usermod -a -G kvm $USER
		sudo root service udev restart
	else
		id|grep -q '(kvm)'
		if [ $? -eq 0 ]; then
			echo "KVM already seems to be setup for user $USER, skipping.."
		else
			echo "Group KVM already exists, adding this user $USER.."
			sudo usermod -a -G kvm $USER
		fi
	fi
}

print_help()
{
	echo
	echo "Usage: ./install <action>"
	echo
	echo "Perform complete installation or limit to individual action:"
	echo
	echo " check   - check for basic requirements"
	echo " deps    - install dependencies"
	echo " qemu    - download and build modified qemu"
	echo " libxdc  - download and build libxdc"
	echo " linux   - download and build modified linux kernel"
	echo " perms   - create kvm group and add user <$USER> for /dev/kvm access"
	echo " radamsa - download and build radamsa plugin"
	echo
	echo " all     - perform all of the above."
	echo
}

####################################
# main()
####################################

# Auto-scale building with number of CPUs. Override with ./install -j N <action>
jobs=$(nproc)
[ "$1" = "-j" ] && [ -n $2 ] && [ $2 -gt 0 ] && jobs=$2 && shift 2
#echo "Detected $(nproc) cores, building with -j $jobs..."

test -d $KAFL_ROOT || fatal "Could not find KAFL_ROOT. Missing env setup?"

case $1 in
	"check")
		system_check
		;;
	"deps")
		system_check
		system_deps
		;;
	"perms")
		system_perms
		;;
	"radamsa")
		build_radamsa
		;;
	"libxdc")
		build_libxdc
		;;
	"qemu")
		build_capstone
		build_libxdc
		build_qemu
		;;
	"linux")
		build_linux
		;;
	"all")
		system_check
		system_deps
		build_capstone
		build_libxdc
		build_qemu
		build_linux
		build_radamsa
		system_perms
		;;
	*)
		print_help
		exit
		;;
esac

echo
echo "[*] All done."
echo

exit