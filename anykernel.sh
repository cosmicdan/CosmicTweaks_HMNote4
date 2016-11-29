# AnyKernel2 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup

# shell variables
block=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot;

## end setup


## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;

chmod -R 755 $bin;
mkdir -p $ramdisk $split_img;

OUTFD=/proc/self/fd/$1;

# ui_print <text>
ui_print() { echo -e "ui_print $1\nui_print" > $OUTFD; }

show_progress() { echo "progress $1 $2" > $OUTFD; }
set_progress() { echo "set_progress $1" > $OUTFD; }

# contains <string> <substring>
contains() { test "${1#*$2}" != "$1" && return 0 || return 1; }

file_getprop() { grep "^$2" "$1" | cut -d= -f2; }

# dump boot and extract ramdisk
dump_boot() {
  dd if=$block of=/tmp/anykernel/boot.img;
  $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Dumping/splitting image failed. Aborting..."; exit 1;
  fi;
  mv -f $ramdisk /tmp/anykernel/rdtmp;
  mkdir -p $ramdisk;
  cd $ramdisk;
  gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i;
  if [ $? != 0 -o -z "$(ls $ramdisk)" ]; then
    ui_print " "; ui_print "Unpacking ramdisk failed. Aborting..."; exit 1;
  fi;
  cp -af /tmp/anykernel/rdtmp/* $ramdisk;
}

# repack ramdisk then build and write image
write_boot() {
  cd $split_img;
  cmdline=`cat *-cmdline`;
  board=`cat *-board`;
  base=`cat *-base`;
  pagesize=`cat *-pagesize`;
  kerneloff=`cat *-kerneloff`;
  ramdiskoff=`cat *-ramdiskoff`;
  tagsoff=`cat *-tagsoff`;
  if [ -f *-second ]; then
    second=`ls *-second`;
    second="--second $split_img/$second";
    secondoff=`cat *-secondoff`;
    secondoff="--second_offset $secondoff";
  fi;
  if [ -f /tmp/anykernel/zImage ]; then
    kernel=/tmp/anykernel/zImage;
  elif [ -f /tmp/anykernel/zImage-dtb ]; then
    kernel=/tmp/anykernel/zImage-dtb;
  else
    kernel=`ls *-zImage`;
    kernel=$split_img/$kernel;
  fi;
  if [ -f /tmp/anykernel/dtb ]; then
    dtb="--dt /tmp/anykernel/dtb";
  elif [ -f *-dtb ]; then
    dtb=`ls *-dtb`;
    dtb="--dt $split_img/$dtb";
  fi;
  if [ -f "$bin/mkbootfs" ]; then
    $bin/mkbootfs /tmp/anykernel/ramdisk | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
  else
    cd $ramdisk;
    find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
  fi;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Repacking ramdisk failed. Aborting..."; exit 1;
  fi;
  $bin/mkbootimg --kernel $kernel --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff $dtb --output /tmp/anykernel/boot-new.img;
  if [ $? != 0 ]; then
    ui_print " "; ui_print "Repacking image failed. Aborting..."; exit 1;
  elif [ `wc -c < /tmp/anykernel/boot-new.img` -gt `wc -c < /tmp/anykernel/boot.img` ]; then
    ui_print " "; ui_print "New image larger than boot partition. Aborting..."; exit 1;
  fi;
  if [ -f "/data/custom_boot_image_patch.sh" ]; then
    ash /data/custom_boot_image_patch.sh /tmp/anykernel/boot-new.img;
    if [ $? != 0 ]; then
      ui_print " "; ui_print "User script execution failed. Aborting..."; exit 1;
    fi;
  fi;
  dd if=/tmp/anykernel/boot-new.img of=$block;
}

# backup_file <file>
backup_file() { cp $1 $1~; }

# replace_string <file> <if search string> <original string> <replacement string>
replace_string() {
  if [ -z "$(grep "$2" $1)" ]; then
      sed -i "s;${3};${4};" $1;
  fi;
}

# replace_section <file> <begin search string> <end search string> <replacement string>
replace_section() {
  begin=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
  for end in `grep -n "$3" $1 | cut -d: -f1`; do
    if [ "$begin" -lt "$end" ]; then
      sed -i "/${2//\//\\/}/,/${3//\//\\/}/d" $1;
      sed -i "${begin}s;^;${4}\n;" $1;
      break;
    fi;
  done;
}

# remove_section <file> <begin search string> <end search string>
remove_section() {
  begin=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
  for end in `grep -n "$3" $1 | cut -d: -f1`; do
    if [ "$begin" -lt "$end" ]; then
      sed -i "/${2//\//\\/}/,/${3//\//\\/}/d" $1;
      break;
    fi;
  done;
}

# insert_line <file> <if search string> <before|after> <line match string> <inserted line>
insert_line() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;${5}\n;" $1;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | head -n1 | cut -d: -f1`;
    sed -i "${line}d" $1;
  fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo "$(cat $patch/$3 $1)" > $1;
  fi;
}

# insert_file <file> <if search string> <before|after> <line match string> <patch file>
insert_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;\n;" $1;
    sed -i "$((line - 1))r $patch/$5" $1;
  fi;
}

# append_file <file> <if search string> <patch file>
append_file() {
  if [ -z "$(grep "$2" $1)" ]; then
    echo -ne "\n" >> $1;
    cat $patch/$3 >> $1;
    echo -ne "\n" >> $1;
  fi;
}

# replace_file <file> <permissions> <patch file>
replace_file() {
  cp -pf $patch/$3 $1;
  chmod $2 $1;
}

# patch_fstab <fstab file> <mount match name> <fs match type> <block|mount|fstype|options|flags> <original string> <replacement string>
patch_fstab() {
  entry=$(grep "$2" $1 | grep "$3");
  if [ -z "$(echo "$entry" | grep "$6")" ]; then
    case $4 in
      block) part=$(echo "$entry" | awk '{ print $1 }');;
      mount) part=$(echo "$entry" | awk '{ print $2 }');;
      fstype) part=$(echo "$entry" | awk '{ print $3 }');;
      options) part=$(echo "$entry" | awk '{ print $4 }');;
      flags) part=$(echo "$entry" | awk '{ print $5 }');;
    esac;
    newentry=$(echo "$entry" | sed "s;${part};${6};");
    sed -i "s;${entry};${newentry};" $1;
  fi;
}

## end methods

###########################
###########################
###########################
## begin installation

ui_print " ";

export choice_main=`file_getprop /tmp/aroma/choice_main.prop selected`;

if [ "$choice_main" == "1" ]; then
    show_progress "0.2" "-1200"

    ui_print "[#] Erasing /cust (nothing but junk here)...";
    mount /cust
    rm -rf /cust/*
    umount /cust

    ui_print "[#] /system removals...";
    rm -rf /system/data-app/*;
    ui_print "    [i] Erased Chinese bloat at /system/data-app/*";
    rm /system/bin/install-recovery.sh;
    rm /system/recovery-from-boot.p;
    ui_print "    [i] Deleted stock recovery patch & script";
    rm -rf /system/app/AnalyticsCore;
    ui_print "    [i] Removed app/AnalyticsCore (Phone-home backdoor app)";
    rm -rf /system/app/AutoTest;
    ui_print "    [i] Removed app/AutoTest (Engineering diagnostics)";
    rm -rf /system/app/SogouInput;
    ui_print "    [i] Removed app/SogouInput (Chinese IME)";
    rm -rf /system/app/Whetstone
    ui_print "    [i] Removed Whetstone (appkiller)";
    rm -rf /system/app/AMAPNetworkLocation;
    # Removing causes security alert
    #rm -rf /system/app/GameCenter;
    rm -rf /system/app/jjcontainer;
    rm -rf /system/app/jjhome;
    rm -rf /system/app/jjknowledge;
    rm -rf /system/app/jjstore;
    rm -rf /system/app/mab;
    rm -rf /system/app/MiLivetalk;
    rm -rf /system/app/Mipay;
    # Can't disable MiuiSuperMarket 
    #rm -rf /system/app/MiuiSuperMarket;
    # Removing causes security alert
    #rm -rf /system/app/MiuiVideo
    rm -rf /system/app/PaymentService;
    rm -rf /system/app/SelfRegister;
    rm -rf /system/app/SystemAdSolution;
    rm -rf /system/app/VoiceAssist;
    rm -rf /system/app/XiaomiVip;
    rm -rf /system/app/XMPass;
    rm -rf /system/priv-app/MiuiVoip;
    rm -rf /system/priv-app/VirtualSim;
    rm -rf /system/priv-app/YellowPage;
    ui_print "    [i] Removed various Chinese-only services";
    ui_print "[#] /system patches...";
    replace_line /system/etc/device_features/$device1.xml "    <bool name=\"support_ota_validate\">true</bool>" "    <bool name=\"support_ota_validate\">false</bool>"
    ui_print "    [i] Disabled OTA app ZIP validation";
    replace_file /system/etc/install_app_filter.xml 644 install_app_filter.xml___replacement;
    ui_print "    [i] Remove Chinese carrier app selection";
    sed 's/^ro.product.locale=*/ro.product.locale=en-US/g' /system/build.prop > /dev/null 2>&1
    append_file /system/build.prop "# CosmicDan Additionals 01 " build.prop___additions;
    ui_print "    [i] build.prop replacements/additions";
    ui_print "[#] Extracting kernel...";
    dump_boot;
    ui_print "[#] Patching RAMDisk...";
    # change these to fstab functions
    replace_line fstab.mt6797 "/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/system /system ext4 ro wait,verify" "/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/system /system ext4 ro wait"
    ui_print "    [i] Disabled dm-verity (aka verified boot)";
    replace_string fstab.mt6797 "encryptable=" "forceencrypt=" "encryptable="
    ui_print "    [i] Disabled forced userdata encryption";
    # remove old broken init.d
    remove_section init.rc "# init.d" "    oneshot"
    rm /system/xbin/sysinit;
    append_file init.rc "# init.d" init.rc___additions
    cp /tmp/anykernel/sbin/* sbin/
    chmod 755 sbin/*
    echo "sepolicy-inject -z sysinit"
    $bin/sepolicy-inject -z sysinit -P sepolicy
    echo "sepolicy-inject -Z sysinit"
    $bin/sepolicy-inject -Z sysinit -P sepolicy

    echo "sepolicy-inject -s init -t sysinit [...]"
    $bin/sepolicy-inject -s init -t sysinit -c process -p transition -P sepolicy
    $bin/sepolicy-inject -s init -t sysinit -c process -p rlimitinh -P sepolicy
    $bin/sepolicy-inject -s init -t sysinit -c process -p siginh -P sepolicy
    $bin/sepolicy-inject -s init -t sysinit -c process -p noatsecure -P sepolicy

    echo "sepolicy-inject -s sysinit -t sysinit [...]"
    $bin/sepolicy-inject -s sysinit -t sysinit -c dir -p search,read -P sepolicy
    $bin/sepolicy-inject -s sysinit -t sysinit -c file -p read,write,open -P sepolicy
    $bin/sepolicy-inject -s sysinit -t sysinit -c unix_dgram_socket -p create,connect,write,setopt -P sepolicy
    $bin/sepolicy-inject -s sysinit -t sysinit -c lnk_file -p read -P sepolicy
    $bin/sepolicy-inject -s sysinit -t sysinit -c process -p fork,sigchld -P sepolicy
    $bin/sepolicy-inject -s sysinit -t sysinit -c capability -p dac_override -P sepolicy

    echo "sepolicy-inject -s sysinit -t [other-domains] ..."
    $bin/sepolicy-inject -s sysinit -t system_file -c file -p entrypoint,execute_no_trans -P sepolicy
    $bin/sepolicy-inject -s sysinit -t devpts -c chr_file -p read,write,open,getattr,ioctl -P sepolicy
    $bin/sepolicy-inject -s sysinit -t rootfs -c file -p execute,read,open,execute_no_trans,getattr -P sepolicy
    $bin/sepolicy-inject -s sysinit -t shell_exec -c file -p execute,read,open,execute_no_trans,getattr -P sepolicy
    $bin/sepolicy-inject -s sysinit -t zygote_exec -c file -p execute,read,open,execute_no_trans,getattr -P sepolicy
    $bin/sepolicy-inject -s sysinit -t toolbox_exec -c file -p getattr,open,read,ioctl,lock,getattr,execute,execute_no_trans,entrypoint -P sepolicy

    echo "sepolicy-inject -a mlstrustedsubject -s sysinit -P sepolicy"
    $bin/sepolicy-inject -a mlstrustedsubject -s sysinit -P sepolicy

    ui_print "    [i] Added init.d support";
    ui_print "[#] Writing kernel with patched RAMDisk...";
    show_progress "0.2" "-1500"
    write_boot;
fi;

if [ "$choice_main" == "2" ]; then
    ui_print "[i] TODO";
fi;