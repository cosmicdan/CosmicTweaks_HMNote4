#!/sbin/sh
file_getprop() { grep "^$2" "$1" | cut -d= -f2; }

for i in 1 2 3 4 5; do
    testname="$(file_getprop /tmp/aroma/anykernel.prop device$i)";
    if [ "$(getprop ro.product.device)" == "$testname" -o "$(getprop ro.build.product)" == "$testname" ]; then
        exit 1;
    fi;
done;
exit 0;