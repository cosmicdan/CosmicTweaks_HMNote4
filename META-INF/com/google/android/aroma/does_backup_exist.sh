#!/sbin/sh
mount /system;

if [ -d /system/cosmictweaks_backup ]; then
    exit 1;
fi;

exit 0;