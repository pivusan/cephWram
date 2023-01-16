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
GREEN='\033[0;32m'
NoColor='\033[0m'

# Help
  if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]; then
    echo
    echo " Скрипт предназначен для запуска команды на серверах, указанных ключём"
    echo " Использование: ${0} [-f или -m или -t ] <команда выполняющаяся на удалённых серверах заключенная в кавычки> "
    echo
    exit 0
  fi

if [ "${1}" = "-f" ]; then
  cluster=(pnode{01..16});
fi
if [ "${1}" = "-m" ]; then
  cluster=(pnode{02..05});
fi
if [ "${1}" = "-t" ]; then
  cluster=(pnode06);
fi

for host in ${cluster[@]}; do
  echo -e ${GREEN}"HOST="${host}${NoColor}
  /usr/bin/ssh  ${host} ${2};
  echo; echo;
done

echo -e ${GREEN}"end ${0}"${NoColor}
