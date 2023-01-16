#!/bin/bash
#
# Color
<<CommentColor
 Black        0;30     Dark Gray     1;30
 Red          0;31     Light Red     1;31
 Green        0;32     Light Green   1;32
 Brown/Orange 0;33     Yellow        1;33
 Blue         0;34     Light Blue    1;34
 Purple       0;35     Light Purple  1;35
 Cyan         0;36     Light Cyan    1;36
 Light Gray   0;37     White         1;37
CommentColor
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NoColor='\033[0m'

# Help
  if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]; then
    echo
    echo " Скрипт предназначен для создания нагрузки на сервер "
    echo " Использование: ${0} "
    echo
    exit 0
  fi

# Functions

# Функция нагрузки на диск
function rundiskload {
timesleep=$(($1/100+0.05)) # % нагрузки (load) переведём в секунды и добавим 0.05 секунды на запуск самой ${program}
program="dd"
keys="if=/dev/zero of=/var/cephfs/hdd/dd.1G bs=1G count=1 oflag=direct"
(sleep ${timesleep} && killall ${program}) & ${program} ${keys}
}

function runcpuload {
timesleep=$(($1/100)) # Время ожидания перед тем, как завершить программу. Рассчитывается в зависимости от требуемой загрузки сервера. Возможный диапазон от 0 до одной секунды.
program="openssl"
keys="speed"
for i in 1 2 # Количество потоков должно быть равно количеству ядер
  do
    ${program} ${keys} &
  done
sleep ${timesleep} && killall ${program}
}

function runramload {
echo $1
sleep 3
}

function runinfinibandload {
echo $1
sleep 3
}

# Parameters
load=10 # Процент нагрузки на кластер
numberofcore=2 # Число ядер процессора

echo -e ${GREEN}"HOST="`hostname -s`${NoColor}
echo -e ${ORANGE}"Press Ctrl+C to abort..."${NoColor}

while true
  do
    echo -e ${GREEN}"Run disk load"${NoColor}
    rundiskload ${load} &

    echo -e ${GREEN}"Run cpu load"${NoColor}
    runcpuload ${load} ${numberofcore} &

    echo -e ${GREEN}"Run RAM load"${NoColor}
    runramload ${load} &

    echo -e ${GREEN}"Run Infiniband load"${NoColor}
    runinfinibandload ${load} &
  done

echo -e ${GREEN}"end ${0}"${NoColor}
