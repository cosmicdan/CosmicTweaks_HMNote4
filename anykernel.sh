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
ZIP="$2";

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
        if [ "$begin" -lt "$end" ] 2>/dev/null; then
            sed -i "/${2//\//\\/}/,/${3//\//\\/}/d" $1;
            #break;
            return 0;
        fi;
    done;
    return 1;
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

## cosmicdan additionals

buildprop_enable() {
    append_file /system/build.prop "$1" "$2";
    ui_print "        <#0c0>... added!</#>";
}

buildprop_disable() {
    if remove_section /system/build.prop "$1" "$2"; then
        ui_print "        <#c00>... REMOVED!</#>";
    else
        ui_print "        <#00c>... not selected, skipped!</#>";
    fi;
}

zip_extract_dir() {
    if [ ! -d "$3" ]; then
        mkdir -p "$3"
    fi;
    unzip -o "$1" "$2/*" -d "$3";
    mv -f "$3/$2"/* "$3"
    basedir=$(echo "$2" | cut -d "/" -f1)
    rm -rf "$3/$basedir"
} 

## end methods

###########################
###########################
###########################
## begin installation

ui_print " ";

export choice_main=`file_getprop /tmp/aroma/choice_main.prop selected`;
export device1=`file_getprop /tmp/anykernel/anykernel.prop device1`;

ui_print "[#] Extracting kernel...";
show_progress "0.2" "-1500";
dump_boot;
ui_print "[#] Patching RAMDisk...";

############
## Install (kernel tasks)
############
if [ "$choice_main" == "1" ]; then
    patch_fstab fstab.mt6797 /system ext4 flags "wait,verify" "wait";
    ui_print "    [i] Disabled dm-verity (aka verified boot)";
    replace_string fstab.mt6797 "encryptable=" "forceencrypt=" "encryptable="
    ui_print "    [i] Disabled forced encryption";
    # remove old broken init.d
    remove_section init.rc "# init.d" "    oneshot"
    if [ -f "/system/xbin/sysinit" ]; then
        # upgrade from old versions
        rm /system/xbin/sysinit;
    fi;
    append_file init.rc "# init.d" init.rc___additions
    cp /tmp/anykernel/sbin/* sbin/
    chmod 755 sbin/*
    ui_print "    [#] Injecting sepolicy with init.d-related permissions...";
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

    ui_print "        ...done.";
fi;


############
## ADB (kernel tasks)
############
if [ "$choice_main" == "2" ]; then
    if [ "$(file_getprop /tmp/aroma/choice_adb.prop root)" == "install" ]; then
        ui_print "    [#] Set Insecure ADB On Boot...";
        export devicelock_newval="0";
        export secure_newval="0";
        export debuggable_newval="1";
        export usb_newval="adb";
        
        if [ -f /data/property/persist.sys.usb.config ]; then
            rm /data/property/persist.sys.usb.config
        fi;
        
        # root-mode adbd
        if [ -f sbin/sysinit ]; then
            if [ "$(file_getprop /tmp/aroma/choice_adb_rootmode.prop enabled)" == "1" ]; then
                insert_line init.rc "# adbd patch start" before "seclabel u:r:adbd:s0" "    # adbd patch start"
                insert_line init.rc "# adbd patch end" after "seclabel u:r:adbd:s0" "    # adbd patch end"
                replace_line init.rc "    seclabel u:r:adbd:s0" "    seclabel u:r:sysinit:s0"
                cp -f /tmp/anykernel/adbd/insecure sbin/adbd
                chmod 755 sbin/*
                ui_print "        [i] Injected root-mode ADBD binary";
            fi;
        else
            ui_print "        <#c00>[!] Error - The /system has CosmicTweaks but the kernel is not modded. You've flashed a stock kernel? Please reinstall CosmicTweaks!</#>";
        fi;
    else
        ui_print "    [#] Restore Secure and non-boot ADB...";
        export devicelock_newval="1";
        export secure_newval="1";
        export debuggable_newval="0";
        export usb_newval="adb";
        
        # root-mode adbd
        replace_section init.rc "    # adbd patch start" "    # adbd patch end" "    seclabel u:r:adbd:s0"
        if ! cmp -s "/tmp/anykernel/adbd/secure" "sbin/adbd"; then
            cp -f /tmp/anykernel/adbd/secure sbin/adbd
            chmod 755 sbin/*
            ui_print "        [i] Injected stock non-root-mode adbd binary";
        else
            ui_print "        [i] adbd binary is already stock";
        fi;
    fi;
    replace_line default.prop "ro.secureboot.devicelock=" "ro.secureboot.devicelock=$devicelock_newval"
    replace_line default.prop "ro.adb.secure=" "ro.adb.secure=$secure_newval"
    replace_line default.prop "ro.secure=" "ro.secure=$secure_newval"
    replace_line default.prop "ro.debuggable=" "ro.debuggable=$debuggable_newval"
    replace_line default.prop "persist.sys.usb.config=" "persist.sys.usb.config=$usb_newval"
fi;


############
## (finish kernel tasks)
############
ui_print "[#] Writing kernel with patched RAMDisk...";
write_boot;

############
## Install (post-kernel)
############
if [ "$choice_main" == "1" ]; then
    show_progress "0.2" "-1200"

    ui_print "[#] /system removals...";
    
    if [ "$(file_getprop /tmp/aroma/install_removals.prop data-app)" == "data-app_delete" ]; then
        if [ -d "/system/data-app" ]; then
            rm -rf "/system/data-app/*";
            ui_print "    [i] Deleted pre-install bloat from /system/data-app/";
        else
            ui_print "    [i] Pre-install bloat at /system/data-app/ already deleted.";
        fi;
    fi;
    
    if [ -f "/system/bin/install-recovery.sh" -o -f "/system/recovery-from-boot.p" ]; then
        rm /system/bin/install-recovery.sh;
        rm /system/recovery-from-boot.p;
        ui_print "    [i] Deleted stock recovery patch/script";
    else
        ui_print "    [i] Stock recovery patch/script not present";
    fi;
    
    if [ "$(file_getprop /tmp/aroma/install_removals.prop amapnetlocation)" == "1" ]; then
        ui_print "    [#] Removing AMAPNetworkLocation...";
        rm -rf /system/app/AMAPNetworkLocation;
    fi;
    if [ "$(file_getprop /tmp/aroma/install_removals.prop analyticscore)" == "1" ]; then
        ui_print "    [#] Removing AnalyticsCore...";
        rm -rf /system/app/AnalyticsCore;
    fi;
    if [ "$(file_getprop /tmp/aroma/install_removals.prop autotest)" == "1" ]; then
        ui_print "    [#] Removing AutoTest...";
        rm -rf /system/app/AutoTest;
    fi;
    if [ "$(file_getprop /tmp/aroma/install_removals.prop sogouinput)" == "1" ]; then
        ui_print "    [#] Removing SogouInput...";
        rm -rf /system/app/SogouInput;
    fi;
    if [ "$(file_getprop /tmp/aroma/install_removals.prop whetstone)" == "1" ]; then
        ui_print "    [#] Removing Whetstone...";
        rm -rf /system/app/Whetstone;
    fi;
    if [ "$(file_getprop /tmp/aroma/install_removals.prop yellowpage)" == "1" ]; then
        ui_print "    [#] Removing YellowPage...";
        rm -rf /system/priv-app/YellowPage;
    fi;
    
    if [ "$(file_getprop /tmp/aroma/install_removals.prop otherbloatapps)" == "1" ]; then
        ui_print "    [#] Removing various Chinese-only services/bloat...";
        # Removing causes security alert on China
        #rm -rf /system/app/GameCenter silent;
        rm -rf /system/app/jjcontainer silent;
        rm -rf /system/app/jjhome silent;
        rm -rf /system/app/jjknowledge silent;
        rm -rf /system/app/jjstore silent;
        rm -rf /system/app/mab silent;
        rm -rf /system/app/MiLivetalk silent;
        rm -rf /system/app/Mipay silent;
        # Can't disable MiuiSuperMarket on China
        #rm -rf /system/app/MiuiSuperMarket silent;
        # Removing causes security alert on China
        #rm -rf /system/app/MiuiVideo silent;
        rm -rf /system/app/PaymentService silent;
        rm -rf /system/app/SelfRegister silent;
        rm -rf /system/app/SystemAdSolution silent;
        rm -rf /system/app/VoiceAssist silent;
        rm -rf /system/app/XiaomiVip silent;
        rm -rf /system/app/XMPass silent;
        rm -rf /system/priv-app/MiuiVoip silent;
        rm -rf /system/priv-app/VirtualSim silent;
    fi;
    
    # non-optionals
    ui_print "[#] /system patches...";
    ui_print "    [#] Disable OTA app ZIP validation";
    replace_line /system/etc/device_features/$device1.xml "    <bool name=\"support_ota_validate\">true</bool>" "    <bool name=\"support_ota_validate\">false</bool>"
    ui_print "    [#] Remove Chinese carrier app selection";
    replace_file /system/etc/install_app_filter.xml 644 install_app_filter.xml___replacement;
    
    #######
    ### build.prop
    ui_print "    [#] build.prop replacements/additions...";
    # remove old build.prop tweaks first
    if remove_section /system/build.prop "# CosmicDan Additionals" "########"; then
        ui_print "    [!] Upgrade from old CosmicTweaks detected. Please note that the old build.prop changes are replaced OK, but I can NOT make it 100% original. If you want any future OTA deltas to work, please flash a stock ROM and start fresh. Sorry!";
    fi;
    
    sed 's/^ro.product.locale=*/ro.product.locale=en-US/g' /system/build.prop > /dev/null 2>&1
    append_file /system/build.prop "### CosmicTweaks - Common tweaks" build.prop___additions;
    
    # do optionals
    ui_print "        [#] Camera quality/encoding tweaks...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop camera)" == "1" ]; then
        buildprop_enable "### CosmicTweaks - Camera quality/encoding tweaks" build.prop___additions___camera-tweaks;
    else
        buildprop_disable "### CosmicTweaks - Camera quality/encoding tweaks" "###";
    fi;
    
    ui_print "        [#] Fast dormancy (battery improvement)...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop fastdormancy)" == "1" ]; then
        buildprop_enable "### CosmicTweaks - Fast dormancy (battery improvement)" build.prop___additions___fast-dormancy;
    else
        buildprop_disable "### CosmicTweaks - Fast dormancy (battery improvement)" "###";
    fi;
    
    ui_print "        [#] Force disable 4G...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop forcedisable4g)" == "1" ]; then
        buildprop_enable "### CosmicTweaks - Force disable 4G" build.prop___additions___force_disable_4g;
    else
        buildprop_disable "### CosmicTweaks - Force disable 4G" "###";
    fi;
    
    ui_print "        [#] Google location service...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop googlelocation)" == "1" ]; then
        buildprop_enable "### CosmicTweaks - Google location service" build.prop___additions___google-location;
    else
        buildprop_disable "### CosmicTweaks - Google location service" "###";
    fi;
    
    ui_print "        [#] Disable MIUI Optimization...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop miuioptimization)" == "1" ]; then
        buildprop_enable "### CosmicTweaks - MIUI Optimization" build.prop___additions___miui-optimisation;
    else
        buildprop_disable "### CosmicTweaks - MIUI Optimization" "###";
    fi;
    
    ui_print "        [#] Scrolling tweaks...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop scrollingtweaks)" == "1" ]; then
        buildprop_enable "### CosmicTweaks - Scrolling cache" build.prop___additions___scrolling-tweaks;
    else
        buildprop_disable "### CosmicTweaks - Scrolling cache" "###";
    fi;
    
    ### end build.prop
    #######
    
    #######
    ### install
    ui_print " ";
    show_progress "0.2" "-1000"
    ui_print "[#] Extract new /system files...";
    unzip -o "$ZIP" "system/*" -d "/";
    
    # additions
    ui_print "    [#] Additions/replacements...";
    if [ "$(file_getprop /tmp/aroma/install_additions.prop aospprovision)" == "1" ]; then
        if [ -d "/system/app/Provision" ]; then
            rm -rf "/system/app/Provision";
            zip_extract_dir "$ZIP" "system_optional/priv-app___Provision-AOSP" "/system/priv-app/"
            ui_print "        [i] MIUI Provision replaced with AOSP version";
        else
            ui_print "        [i] AOSP Provision selected, but MIUI version not found. Skipped.";
        fi;
    fi;
    ui_print "        [#] Vendor overlays...";
    mkdir -p "/system/vendor/overlay";
    if [ "$(file_getprop /tmp/aroma/install_additions.prop framework)" == "1" ]; then
        zip_extract_dir "$ZIP" "system_optional/vendor_overlay___framework" "/system/vendor/overlay/"
        ui_print "            [i] framework-res";
    fi;
    if [ "$(file_getprop /tmp/aroma/install_additions.prop quicksearchbox)" == "1" ]; then
        zip_extract_dir "$ZIP" "system_optional/vendor_overlay___QuickSearchBox" "/system/vendor/overlay/"
        ui_print "            [i] QuickSearchBox";
    fi;
    

    # init.d
    ui_print "    [#] init.d scripts...";
    mkdir -p "/system/etc/init.d";
    
    ui_print "        [#] Clear Icon Cache...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop cleariconcache)" == "1" ]; then
        zip_extract_dir "$ZIP" "system_optional/init.d___clear_icon_cache" "/system/etc/init.d/"
        ui_print "        <#0c0>... added!</#>";
    else
        if [ -f "/system/etc/init.d/clear_icon_cache" ]; then
            rm "/system/etc/init.d/clear_icon_cache";
            ui_print "        <#c00>... REMOVED!</#>";
        else
            ui_print "        <#00c>... not selected, skipped!</#>";
        fi;
    fi;
    
    ui_print "        [#] VM and LMK values...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop vmlmkvalues)" == "1" ]; then
        zip_extract_dir "$ZIP" "system_optional/init.d___memory_vm_lmk_tweaks" "/system/etc/init.d/"
        ui_print "        <#0c0>... added!</#>";
    else
        if [ -f "/system/etc/init.d/memory_vm_lmk_tweaks" ]; then
            rm "/system/etc/init.d/memory_vm_lmk_tweaks";
            ui_print "        <#c00>... REMOVED!</#>";
        else
            ui_print "        <#00c>... not selected, skipped!</#>";
        fi;
    fi;
    
    ui_print "        [#] Set Internal to NOOP I/O...";
    if [ "$(file_getprop /tmp/aroma/install_tweaks.prop internalnoop)" == "1" ]; then
        zip_extract_dir "$ZIP" "system_optional/init.d___mmcblk0_scheduler_noop" "/system/etc/init.d/"
        ui_print "        <#0c0>... added!</#>";
    else
        if [ -f "/system/etc/init.d/mmcblk0_scheduler_noop" ]; then
            rm "/system/etc/init.d/mmcblk0_scheduler_noop";
            ui_print "        <#c00>... REMOVED!</#>";
        else
            ui_print "        <#00c>... not selected, skipped!</#>";
        fi;
    fi;
    
    ui_print "    [#] Setting permissions...";
    show_progress "0.2" "-7000"
    busybox find /system/app/ -type d -exec chmod 755 {} \;
    busybox find /system/app/ -type f -exec chmod 644 {} \;
    chmod 644 /system/etc/system_fonts.xml
    chmod 755 /system/etc/init.d
    busybox find /system/etc/init.d/ -type f -exec chmod 755 {} \;
    busybox find /system/etc/permissions -type f -exec chmod 644 {} \;
    chmod 755 /system/etc/preferred-apps
    busybox find /system/etc/preferred-apps -type f -exec chmod 644 {} \;
    chmod 755 /system/etc/sysconfig
    busybox find /system/etc/sysconfig -type f -exec chmod 644 {} \;
    busybox find /system/fonts -type f -exec chmod 644 {} \;
    busybox find /system/framework/ -type f -exec chmod 644 {} \;
    busybox find /system/priv-app/ -type d -exec chmod 755 {} \;
    busybox find /system/priv-app/ -type f -exec chmod 644 {} \;
    ui_print " ";
    
    ui_print "[i] Busybox installer thanks to YashdSaraf@XDA...";
    show_progress "0.1" "-2000"
    PATH="/tmp/anykernel/bin:$PATH" $bb ash /tmp/anykernel/busybox_installer.sh $OUTFD $ZIP;
fi;

