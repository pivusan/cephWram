#!/bin/bash
# Этот файл был создан puppet модулем ceph
#
# Help
if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]; then
  echo
  echo " Скрипт предназначен для удаление всех OSD расположенных на ram или hdd дисках сервера"
  echo " Использование: ${0} "nameDevClass" "namesDevDiskOsd""
  echo
  exit 0
fi

# Параметры командной строки скрипта:
# Имя класса устройств для идентификации устройств ram или hdd osd и построения CRUSH правил. Передаётся первым параметром из манифеста создания соответствующего OSD (osdram.pp или osdhdd.pp). Например, hdd или ram.
 nameDevClass=$1
# Сразу делаем shift, так как остальные параметры передаваемые скрипту из манифеста создания соответствующего OSD, это имена устройств, с которых нужно удалить OSD
 shift
# Из манифеста создания соответствующего OSD (osdram.pp или osdhdd.pp) в этот скрипт передаются все устройства, с которых нужно удалить OSD
 namesDevDiskOsd=$*

# Параметр, нужно вынести в параметры модуля ceph
# Префикс имени сервера, указывающий на интерфейс передачи данных, обычно это Infiniband интерфейс. Например, cephmon01ib.
 interfaceData=ib

# Очистим и сформируем список номеров osd расположенных на ram или hdd дисках сервера
 unset ListOSDOnServer
 for hostnamesServer in `hostname -s`"~"$nameDevClass `hostname -s`$interfaceData"~"$nameDevClass; do
   ListOSDOnServer="$ListOSDOnServer `ceph osd crush dump | jq --arg jqhostnamesServer ${hostnamesServer}  '.buckets[]|select(.name==$jqhostnamesServer)|.items[]|.id'`"
 done

# Удалить osd расположенные на ram или hdd дисках сервера
 for OsdOnServer in $ListOSDOnServer; do
   ceph osd out osd.$OsdOnServer
   systemctl stop ceph-osd@$OsdOnServer
   ceph osd purge $OsdOnServer --yes-i-really-mean-it
   sudo umount /var/lib/ceph/osd/ceph-$OsdOnServer
 done

# Удалить lvm на ram или hdd дисках на текущем сервере
 for devOsdOnServer in $namesDevDiskOsd; do
   /sbin/vgremove -f `/sbin/pvs|grep $devOsdOnServer|awk '{print $2;}'`
   if [ -b $devOsdOnServer ]; then /sbin/pvremove $devOsdOnServer; fi
 done
