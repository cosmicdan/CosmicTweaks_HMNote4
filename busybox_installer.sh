#!/sbin/sh
#BusyBox Installer
#by YashdSaraf@XDA
# Modded by CosmicDan for use in CosmicTweaks

OPFD=$1
BBZIP=$2

#embedded mode support
readlink /proc/$$/fd/$OPFD 2>/dev/null | grep /tmp >/dev/null
if [ "$?" -eq "0" ]
	then
	OPFD=0
	for FD in `ls /proc/$$/fd`
	do
		readlink /proc/$$/fd/$FD 2>/dev/null | grep pipe >/dev/null
		if [ "$?" -eq "0" ]
			then
			ps | grep " 3 $FD " | grep -v grep >/dev/null
		  	if [ "$?" -eq "0" ]
		  		then
				OPFD=$FD
				break
			fi
		fi
	done
fi

( /sbin/mount /data 
/sbin/mount /cache ) 2>/dev/null
:
#Redirect all errors to LOGFILE
SDCARD=$(ls -d /sdcard 2>/dev/null)
: ${SDCARD:=$(ls -d /data 2>/dev/null)}
: ${SDCARD:=/cache}
LOGFILE=/tmp/BusyBox-YDS-installer.log
echo "#`date`
#Ignore umount errors!" > $LOGFILE
exec 2>>$LOGFILE

ui_print() {
    echo -e "ui_print $1\n
    ui_print" >> /proc/self/fd/$OPFD
	echo -e "$1" >> $LOGFILE
}

error() {
	local ERRSTAT=$?
	if [ $ERRSTAT -ne 0 ]
		then
		ui_print "    [!] Error"
		ui_print "        $1"
        ui_print " "
		ui_print "Busybox installer process failed. Check $LOGFILE for errors"
		[ "$_mounted" == "no" ] && $_sbumt /system
		exit "$ERRSTAT"
	else sleep 0.5
	fi
}

is_mounted() {
	grep "$1" /proc/mounts > /dev/null 2>&1
	return $?
}

ARCH=arm
ARCH64=arm64

_sbmt=/sbin/mount
_sbumt=/sbin/umount

#ui_print "Mounting /system --"

#if (is_mounted /system)
#	then
#	$_sbmt -t auto -o rw,remount /system
#	_mounted="yes"
#else
#	$_sbmt -t auto -o rw /system
#	_mounted="no"
#fi

#error "    Error while mounting /system"

#ui_print "Checking Architecture --"

FOUNDARCH="$(grep -Eo "ro.product.cpu.abi(2)?=.+" /system/build.prop /default.prop 2>/dev/null | grep -Eo "[^=]*$" | head -n1)"

#ui_print "Looking for => '$ARCH', Found => '$FOUNDARCH'"


if [ "${FOUNDARCH::${#ARCH64}}" == "$ARCH64" ]
	then
	BBFILE=busybox64
	#ui_print "64 bit architecture detected --"
elif [ "${FOUNDARCH::${#ARCH}}" == "$ARCH" ]
	then
	BBFILE=busybox
	#ui_print "32 bit architecture detected --"
else
	false
	error "Wrong architecture found"
fi

#ui_print "Checking if busybox needs to have SELinux support --"

API=`grep -E "ro.build.version.sdk=.+" /system/build.prop /default.prop 2>/dev/null | grep -Eo "[^=]*$" | head -n1`

SELSTAT="DISABLED"
[ $API -ge 18 ] && [ -e /sys/fs/selinux/enforce ] && SELSTAT="ENABLED"

for i in /sdcard /data /cache
do
	if [ -f $i/bbxselinuxenabled ]
		then
		SELSTAT="ENABLED (user override)"
		break
	elif [ -f $i/bbxselinuxdisabled ]
		then
		SELSTAT="DISABLED (user override)"
		break
	fi
done
unset i

BBSEL=
if echo "$SELSTAT" | grep ENABLED > /dev/null 2>&1
	then
	BBSEL=-sel
fi

#ui_print "  "
#ui_print "SELinux support is $SELSTAT --"

SUIMG=$(ls /data/su.img 2>/dev/null)
: ${SUIMG:=$(ls /cache/su.img 2>/dev/null)}

if [ ! -z "$SUIMG" ]
	then
	ui_print "    [i] Systemless root detected"
	#Following code to mount su.img is borrowed from supersu update-binary
	mkdir /su
	LOOPDEVICE=
	for LOOP in 0 1 2 3 4 5 6 7
	do
		if (! is_mounted /su)
			then LOOPDEVICE=/dev/block/loop$LOOP
			if [ ! -f "$LOOPDEVICE" ]
				then mknod $LOOPDEVICE b 7 $LOOP
			fi
			losetup $LOOPDEVICE $SUIMG
			if [ "$?" -eq "0" ]
				then
				mount -t ext4 -o loop $LOOPDEVICE /su
				if (! is_mounted /su)
					then /system/bin/toolbox mount -t ext4 -o loop $LOOPDEVICE /su
				fi
				if (! is_mounted /su)
					then /system/bin/toybox mount -t ext4 -o loop $LOOPDEVICE /su
				fi
			fi
			if (is_mounted /su)
				then break
			fi
		fi
	done
fi

INSTALLDIR="none"
for i in /su/xbin /system/xbin
do
	if [ -d $i ]
		then
		INSTALLDIR="$i"
		break
	fi
done
unset i

if [ "$INSTALLDIR" == "none" ]
	then #If xbin was not found in either /su or in /system (;-_-), then create one
	mkdir /system/xbin
	chown 0.0 /system/xbin
	chown 0:0 /system/xbin
	chmod 0755 /system/xbin
	INSTALLDIR="/system/xbin"
fi 2>/dev/null

ui_print "    [#] Removing any old busybox installs..."
TOTALSYMLINKS=0
for i in $(ls -d /system /su 2>/dev/null)
do
	for j in xbin bin
	do
		if [ -e $i/$j/busybox ]
			then
			ui_print "        [#] Removing at $i/$j ..."
			cd $i/$j
			count=0
			for k in $(ls | grep -v busybox)
			do
				if [ "$k" -ef "busybox" ] || ([ -x $k ] && [ "`head -n 1 $k`" == "#!$i/$j/busybox" ])
					then
					rm -f $k
					count=$((count+1))
				fi
			done
			rm -f busybox
			cd /
			error "Error while cleaning BusyBox in $i"
			TOTALSYMLINKS=$((TOTALSYMLINKS+count))
		fi
	done
done
unset i

#[ $TOTALSYMLINKS -gt 0 ] && {
#	ui_print "Total applets removed => $TOTALSYMLINKS --"
#	ui_print "  "
#}

BBFILE="${BBFILE}${BBSEL}.xz"

ui_print "    [#] Installing to $INSTALLDIR ..."
cd $INSTALLDIR
unzip -o "$BBZIP" $BBFILE ssl_helper xzdec
error "Error while unzipping $BBZIP to $INSTALLDIR"
chmod 0555 xzdec
./xzdec $BBFILE > busybox
chmod 0555 busybox
chmod 0555 ssl_helper
rm $BBFILE
rm xzdec

#ui_print "Setting up applets --"
for i in $(./busybox --list)
do
	./busybox ln -s busybox $i 2>/dev/null
	if [ ! -e $i ]
		then
		#Make wrapper scripts for applets if symlinking fails
		echo "#!$INSTALLDIR/busybox" > $i
		error "Error while setting up applets"
		chmod 0755 $i
	fi
done
unset i
# remove broken su applets. We delete these instead of skipping link so old users can upgrade and get the fix
if [ -L su ]; then rm su; fi
if [ -L sulogin ]; then rm sulogin; fi

ui_print "    [#] Adding common system users and groups..."
unzip -o "$BBZIP" addusergroup.sh
. ./addusergroup.sh
rm addusergroup.sh

_resolv=/system/etc/resolv.conf
if [ ! -f $_resolv ] || ! grep nameserver $_resolv >/dev/null 2>&1
	then
	echo "    [#] Adding google nameservers for busybox lookup utils (/system/etc/resolv.conf)" >> $_resolv
	echo "nameserver 8.8.8.8" >> $_resolv
	echo "nameserver 8.8.4.4" >> $_resolv
fi

cd /

#ui_print "Unmounting /system --"
#ui_print "  "
if (is_mounted /su)
	then
	$_sbumt /su
	losetup -d $LOOPDEVICE
	rmdir /su #not using rm -r so /su is deleted only if empty
fi 2>/dev/null
#$_sbumt /system
#ui_print "All DONE! -- Check $LOGFILE for more info"
