#!/bin/bash
# Этот файл был создан puppet модулем ceph
#
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
RED='\033[0;31m'
GREEN='\033[0;32m'
NoColor='\033[0m'

# Help
  if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]; then
    echo
    echo -e " Скрипт предназначен для копирования заданного файла в заданную директорию с правами ${RED}"root"${NoColor}"
    echo " В скрипте используются другие скрипты"
    echo " Использование: $0 <Один Ключ для скриптов pcp.sh и runcmd.sh> <имя файла или папки для копирования > <в какую директорию на удалённых серверах копировать>"
    echo
    exit 0
  fi

Key=${1}
File=${2}
Dir=${3}

bash pcp.sh    $Key ${File} ~
bash runcmd.sh $Key "sudo chown root.root ~/${File}"
bash runcmd.sh $Key "[ -f ${Dir}/${File} ] && sudo mv ${Dir}/${File} ${Dir}/${File}.bak"
bash runcmd.sh $Key "sudo mv ~/${File} ${Dir}/"
bash runcmd.sh $Key "cat ${Dir}/${File}"
bash runcmd.sh $Key "ls -al  ${Dir}/${File}"

echo -e ${GREEN}"end ${0}"${NoColor}
