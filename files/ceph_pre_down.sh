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
#Red='\033[0;31m'
#GREEN='\033[0;32m'
#Yellow='\033[1;33m'
#NoColor='\033[0m'

# Parameters

  NameThisScript=ceph_pre_down.sh # Имя текущего скрипта для передачи в logger

  AmountAttempts=10 # Количество попыток остановки/удаления компонентов ceph
  TimeForSleep=10 # Время в секундах для ожидания после выполнения какой либо операции
  MaxTimeToWait=1800 # Время в секундах для ожидания успешного завершения скрипта на leader MON

  NameRamFS=ram_fs # Имя, данное RAM fs при установке ceph
  NameRamPoolMetadata=pool_replicated_ram_metadata # Имя, данное RAM pool для metadata при установке ceph
  NameRamPoolData=pool_erasure_ram_data # Имя, данное RAM pool для data при установке ceph
  NameRamProfileData=profile_erasure_ram # Имя, данное profile RAM pool data при установке ceph
  NameRamRuleMetadata=rule_replicated_ram # Имя, данное rule RAM pool metadata при установке ceph
  NameRamRuleData=pool_erasure_ram_data # Имя, данное rule RAM pool data при установке ceph

  # Получить через файл от модуля ceph параметры. Проверку на наличие файла не делаем, если его не будет, то что то пошло не так и здесь будет ошибка.
  source /home/cephadm/cephdeploy/conf/ceph.env

  cephfs_basedir=${cephfs_basedir} # Начальная директория относительно которой монтируются pools ceph (например, hdd и ram)

# Загрузить функции из файла
  source /home/cephadm/cephdeploy/functions.sh

# Help
if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]; then
  echo
  echo " Скрипт предназначен для подготовки к выключению кластера ceph"
  echo " Для корректной работы этого скрипта необходимо, чтобы отсутствовала работа клиентов с директориями ceph - ${cephfs_basedir} и состояние ceph было HEALTH_OK"
  echo " Использование: ${NameThisScript}"
  echo
  exit 0
fi

# Определить состояние ceph посредством вызова функции
# Пока комментируем
# Не будем проводить тест остояния ceph при остановке ceph
# Проверка состояния не позволяет восстановить ceph перезагрузкой при сбое питания.
#  check_health

#echo -e ${Yellow}" Unmount CephFS on current server."${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Отмонтирование CephFS на текущем сервере..."
counter=1
until
  # Определить, есть ли смонтированные директории ceph на текущем сервере
  LsCephfsBasedir=`mount | grep ${cephfs_basedir}`;
  [ -z "${LsCephfsBasedir}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
      #echo -e ${Red}" CephFS do not unmount on current server"${NoColor}
      logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. CephFS не отмонтирован на текущем сервере. Необходимо отмонтировать CephFS на текущем сервере. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
      exit 1
    fi
    sudo umount ${cephfs_basedir}/ram
    sudo umount ${cephfs_basedir}/hdd
    sleep ${TimeForSleep}
    ((counter++))
done
#echo -e ${Yellow}" Unmount CephFS on current server successful"${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "CephFS отмонтирована на текущем сервере."

# Запустить этот скрипт и выполнить остановку ceph только на leader MON. То есть остановку ceph проводить на одном сервере. На всех остальных серверах запустить скрипт и ожидать.

# Определить leader MON
  LeaderMon=`ceph quorum_status --format json-pretty | jq --raw-output .quorum_leader_name`
# Сформировать имя сервера из его короткого имени и префикса ib. Такое у нас соглашение о именовании интерфейса передачи данных (обычно это Infiniband интерфейс) сервера.
  ServerNameIB=${HOSTNAME}ib

if [ "${ServerNameIB}" != "${LeaderMon}" ]; then
  #echo -e ${Yellow}" Server do not leader MON Do not stop ceph on this server."${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Текущий сервер не leader MON. Ожидаем окончания работы скрипта подготовки к выключению кластера ceph на leader MON..."

  # Здесь, в цикле until, происходит проверка условия наличия CRUSH rule для RAM pools. Удаление CRUSH rule для RAM pools сейчас происходит на последнем шаге. Выполнение условия говорит нам о том, что скрипт на leader MON отработал и можно приступать к выключению текущего сервера.
  # Если с ceph будет что то не так, то скрипт на leader MON отработает с ошибкой, а на текущем сервере скрипт в нижележащем цикле выйдет по условию превышения встроенного в bash параметра $SECONDS (параметр отражает время работы скрипта) над параметром ${MaxTimeToWait}
  # Look down :PenultimateStepMark
  until
    # Определить, есть ли в CRUSH rule для RAM pools
    LsNameRamRuleMetadata=`ceph osd crush rule ls | grep ${NameRamRuleMetadata}`;
    LsNameRamRuleData=`ceph osd crush rule ls | grep ${NameRamRuleData}`;
    [ -z "${LsNameRamRuleMetadata}" ] && [ -z "${LsNameRamRuleData}" ]; do
    if [ ${SECONDS} -gt ${MaxTimeToWait} ]; then
      #echo -e ${Red}" Exceed MaxTimeToWait"${NoColor}
      logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. Превышено время ожидания окончания работы скрипта подготовки к выключению кластера ceph на leader MON. Необходимо просмотреть журналы каждого сервера ceph, найти leader MON и в сообщениях в его журнале узнать причину прерывания на нём остановки ceph."
      exit 1
    fi
    # echo " Nothing to do. We wait..."
    sleep ${TimeForSleep}
  done
else
  #echo -e ${Yellow}" Server - leader MON. Stop ceph on this server."${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Текущий сервер leader MON. Приступаем к подготовке выключения кластера ceph."

  #echo -e ${Yellow}" Check Unmounting CephFS on all servers"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Проверка отмонтирования CephFS на всех серверах..."
  # Сформировать список всех серверов кластера ceph на которых есть MON, MDS, OSD.
  ListServersMonMdsOsd=(`ceph node ls | jq -r '.[] | keys|.[]'| sed 's/ib$//'|sort|uniq`);
  counter=1
  until
    [[ -z "${ListServersMonMdsOsd[@]}" ]]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" CephFS do not unmount on some servers"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. CephFS не отмонтирован. Необходимо отмонтировать CephFS на всех серверах. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
    # Проверить смонтированы ли директории ceph на каком либо сервере из ListServersMonMdsOsd
    for i in "${!ListServersMonMdsOsd[@]}"; do
      ListMountsCeph=`ssh ${ListServersMonMdsOsd[i]} "mount | grep ${cephfs_basedir}"`
      # Если на сервере нет смонтированных директорий ceph - удалить сервер из списка
      [ -z "${ListMountsCeph}" ] && unset 'ListServersMonMdsOsd[i]'
    done
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" Unmount CephFS successful on all servers"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "CephFS отмонтирован на всех серверах."

  #echo -e ${Yellow}" Those flags should be totally sufficient to safely powerdown your cluster but you could also set the following flags on top if you would like to pause your cluster completely"${NoColor}
    #ceph osd set noin    # If you do not want CRUSH to automatically rebalance the cluster as you stop OSDs for maintenance, set the cluster to noout first. Предотвращает in для OSD кластера.
    #ceph osd set noup    # Предотвращает up для OSD и его запуск.
    # Флаг full не работает.
    #ceph osd set full    # Создает впечатление, что кластер достиг своего уровня full_ratio, и тем самым предотвращает операции записи.
    #ceph osd set noscrub # Ceph предотвратит новые операции очистки.
    #ceph osd set nodeep-scrub # Ceph предотвратит новые операции глубокой очистки.
    #ceph osd set notieragent  # Ceph отключит процесс, который ищет холодные / грязные объекты для очистки и выселения.

    #ceph osd set noout   # If you do not want CRUSH to automatically rebalance the cluster as you stop OSDs for maintenance. Предотвращает out для OSD кластера.
    #ceph osd set nobackfill  #nobackfill и norecover делают одно и то же. В коде они отключают процесс recover немного по-разному, но результат один: полная остановка recovery io. 
    #ceph osd set norecover # Ceph предотвратит новые операции восстановления.
    # На всякий случай добавить и эти флаги:
    #ceph osd set norebalance  # Флаг norebalance отличается. Он позволяет процессу recovery io идти только в случае, если placement group находится в состоянии degraded.
    # Флаг nodown нельзя ставить, так как RAM OSD останавливаются и удаляются при выключении ceph
    #ceph osd set nodown    # prevent OSDs from getting marked down
    #ceph osd set pause     # Флаг pause по сути останавливает клиентское io. Никто из клиентов не сможет ни читать, ни писать из pools Ceph. Ceph прекратит операции обработки чтение и запись, но не будет влиять на OSD in, out, up или down статусы.

    #ceph osd dump | grep flags
    # В заключение скажу: все описанные флаги можно использовать только при внимательном контроле за кластером. Нельзя оставлять их и уходить спать. Они нужны для блокирования естественных процессов, протекающих в Ceph, а сами по себе эти процессы правильные. Система способна сама себя восстанавливать и балансировать. Поэтому блокировать естественные состояния Ceph можно только находясь у компьютера и контролируя процесс
  #echo -e ${Yellow}" Set flags"${NoColor}

  #echo -e ${Yellow}" Shutdown MGR nodes one by one"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Остановка сервисов MGR..."
  counter=1
  until
    # Определить на каких серверах запущены соответствующие сервисы 
    ListServersMgr=`ceph --status --format json-pretty | jq --raw-output '.mgrmap.standbys[].name, .mgrmap.active_name'`;
    [ -z "${ListServersMgr}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
      #echo -e ${Red}" Some Ceph MGR daemons do not down"${NoColor}
      logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. Некоторые сервисы MGR не остановлены. Для остановки ceph, все сервисы MGR должны быть остановлены. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
      exit 1
    fi
    # Попытаться остановить сервис на всех соответствующих сервису серверах
    for server in ${ListServersMgr}; do
      ssh ${server} "sudo systemctl stop ceph-mgr@${server}.service"
    done
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" MGR nodes shutdown successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Все сервисы MGR остановлены."

  #echo -e ${Yellow}" Shutdown MDS nodes one by one"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Остановка сервисов MDS..."
  counter=1
  until
    # Определить на каких серверах запущены соответствующие сервисы
    ListServersMds=`ceph --status --format json-pretty | jq --raw-output .fsmap.by_rank[].name`;
    [ -z "${ListServersMds}" ] || [ ${counter} -gt ${AmountAttempts} ]; do
    # Попытаться остановить сервис на всех соответствующих сервису серверах
    for server in ${ListServersMds}; do
      ssh ${server} "sudo systemctl stop ceph-mds@${server}.service"
    done
    sleep ${TimeForSleep}
    ((counter++))
  done
  if [ ${counter} -gt ${AmountAttempts} ]; then
    #echo -e ${Yellow}" Пытаемся по другому остановить MDS"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Предыдущая попытка остановки сервисов MDS не завершилась успешно. Попытаемся по другому остановить сервисы MDS..."
    counterMds=1
    until
      # Определить на каких серверах запущены соответствующие сервисы
      ListServersMds=`ceph --status --format json-pretty | jq --raw-output .fsmap.by_rank[].name`;
      [ -z "${ListServersMds}" ]; do
      if [ ${counterMds} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" Some Ceph MDS daemons do not down"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. Некоторые сервисы MDS не остановлены. Для остановки ceph, все сервисы MDS должны быть остановлены. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      # Попытаться запустить и остановить сервис на всех соответствующих сервису серверах
      for server in ${ListServersMds}; do
        ssh ${server} "sudo systemctl daemon-reload"
        sleep ${TimeForSleep}
        ssh ${server} "sudo systemctl start ceph-mds@${server}.service"
        sleep ${TimeForSleep}
        ssh ${server} "sudo systemctl stop ceph-mds@${server}.service"
      done
      sleep ${TimeForSleep}
      ((counterMds++))
    done
  fi
  #echo -e ${Yellow}" MDS nodes shutdown successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Все сервисы MDS остановлены."

  #echo -e ${Yellow}" Shutdown RAM OSD one by one"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Остановка сервисов OSD на RAM..."
  counter=1
  until
    # Определить все RAM osd в состоянии up
    # Пробовал для всех osd выполнить down, ceph "зависает" ...
    # ListOsdUp=`ceph osd tree --format json-pretty | jq '.nodes[] | select(.status=="up").id'`;
    # Пробуем только для RAM OSD
    ListRamOsdUp=`ceph osd tree --format json-pretty | jq '.nodes[] | select(.device_class=="ram") | select(.status=="up").id'`
    [ -z "${ListRamOsdUp}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
      #echo -e ${Red}" Some Ceph OSD daemons do not down"${NoColor}
      logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. Некоторые сервисы OSD на RAM не остановлены. Для остановки ceph, все сервисы OSD на RAM должны быть остановлены. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
      exit 1
    fi
    # Попытаться остановить все OSD из ListRamOsdUp
    for osd in ${ListRamOsdUp}; do
      # Определить сервер на котором конкретный OSD в состоянии Up
      ServerWithRamOsdUp=`ceph osd find ${osd} --format json-pretty | jq --raw-output .crush_location.host`
      # Зайти на сервер и попытаться остановить OSD в состоянии Up
      ssh ${ServerWithRamOsdUp} "sudo systemctl stop ceph-osd@${osd}.service"
    done
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" OSD daemons shutdown successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Все сервисы OSD на RAM остановлены."

  #echo -e ${Yellow}" Remove RAM OSD from CRUSH"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Удаление RAM OSD из CRUSH..."
  counter=1
  until
    # Определить все RAM osd в CRUSH
    ListRamOsd=`ceph osd tree --format json-pretty | jq '.nodes[] | select(.device_class=="ram").id'`;
    [ -z "${ListRamOsd}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
      #echo -e ${Red}" Some RAM OSD do not remove from CRUSH"${NoColor}
      logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. Некоторые RAM OSD не удалены из CRUSH. Для остановки ceph, все RAM OSD должны быть удалены из CRUSH. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
      exit 1
    fi
    # Попытаться удалить RAM osd из CRUSH
    for osd in ${ListRamOsd}; do
      ceph osd out osd.${osd}
      ceph osd purge ${osd} --yes-i-really-mean-it
    done
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" RAM osd from CRUSH remove successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Все RAM OSD удалены из CRUSH."

  #echo -e ${Yellow}" Remove RAM FS"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Удаление RAM FS..."
  counter=1
  until
    # Определить существует ли RAM FS 
    LsNameRamFS=`ceph fs ls | grep ${NameRamFS}`;
    [ -z "${LsNameRamFS}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
     #echo -e ${Red}" RAM FS do not remove"${NoColor}
     logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. RAM FS не удалена. Для остановки ceph, RAM FS должна быть удалена. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
     exit 1
    fi
    # Попытаться удалить RAM FS
    ceph fs rm ${NameRamFS} --yes-i-really-mean-it
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" RAM FS delete successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "RAM FS удалена."

  #echo -e ${Yellow}" Delete RAM pools"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Удаление RAM pools..."
  counter=1
  until
    # Определить существует ли RAM pools
    LsNameRamPoolMetadata=`ceph osd pool ls | grep ${NameRamPoolMetadata}`;
    LsNameRamPoolData=`ceph osd pool ls | grep ${NameRamPoolData}`;
    [ -z "${LsNameRamPoolMetadata}" ] && [ -z "${LsNameRamPoolData}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
     #echo -e ${Red}" Some RAM pools do not remove"${NoColor}
     logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. RAM pools не удалены. Для остановки ceph, RAM pools должны быть удалены. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
     exit 1
    fi
    # Попытаться удалить RAM pools
    ceph osd pool rm ${NameRamPoolMetadata} ${NameRamPoolMetadata} --yes-i-really-really-mean-it
    ceph osd pool rm ${NameRamPoolData} ${NameRamPoolData} --yes-i-really-really-mean-it
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" RAM pools delete successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "RAM pools удалены."

  #echo -e ${Yellow}" Delete profile for erasure RAM pool"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Удаление profile для erasure RAM pool..."
  counter=1
  until
    # Определить существует ли profile для erasure RAM pool
    LsNameRamProfileData=`ceph osd erasure-code-profile ls | grep ${NameRamProfileData}`;
    [ -z "${LsNameRamProfileData}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
     #echo -e ${Red}" Profile for erasure RAM pool do not remove"${NoColor}
     logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. Profile для erasure RAM pool не удалён. Для остановки ceph, profile для erasure RAM pool должен быть удалён. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
     exit 1
    fi
    # Попытаться удалить profile для erasure RAM pool
    ceph osd erasure-code-profile rm ${NameRamProfileData}
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" Profile for erasure RAM pool delete successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Profile для erasure RAM pool удалён."

  # :PenultimateStepMark
  #echo -e ${Yellow}" Delete CRUSH rule for RAM pools"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Удаление CRUSH правила для RAM pools..."
  counter=1
  until
    # Определить существует ли RAM rules 
    LsNameRamRuleMetadata=`ceph osd crush rule ls | grep ${NameRamRuleMetadata}`;
    LsNameRamRuleData=`ceph osd crush rule ls | grep ${NameRamRuleData}`;
    [ -z "${LsNameRamRuleMetadata}" ] && [ -z "${LsNameRamRuleData}" ]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
     #echo -e ${Red}" Some CRUSH rule for RAM pools do not remove"${NoColor}
     logger -i --priority local0.err --tag ${NameThisScript} "Выключение кластера ceph прервано. Некоторые CRUSH правила для RAM pools не удалены. Для остановки ceph, CRUSH правила для RAM pools должны быть удалены. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
     exit 1
    fi
    # Попытаться удалить CRUSH rule для RAM pools
    ceph osd crush rule rm ${NameRamRuleMetadata}
    ceph osd crush rule rm ${NameRamRuleData}
    sleep ${TimeForSleep}
    ((counter++))
  done
  #echo -e ${Yellow}" CRUSH rule for RAM pools delete successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "CRUSH правила для RAM pools удалены."

<<DoNotStopingMons 
# Потенциально "проблемный" код. После остановки какого либо MON, может быть долгой операция получения информации о ceph. Поэтому, любые проверки могут закончиться неудачей. Более того, к моменту времени, когда этот скрипт начнёт останавливать MONs на других серверах кластера ceph, MONs там уже могут быть остановлены systemd. Закомментирую его.
# Вернул код остановки MONs, так как решили запускать этот скрипт посредством puppet, а не systemd.
# Окончательно, в итоге, удаляем этот код. Нет необходимости останавливать MON...

#echo -e ${Yellow}" Shutdown MON nodes one by one"${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Остановка сервисов MON..."
# Перед остановкой MONs необходимо подождать продолжительное время, чтобы этот скрипт запущенный на серверах не leader MON, успел получить информацию от MONs, что RAM pools удалён и смог успешно завершиться.
# Удалил пока что. Нет необходимости это делать на первый взгляд.
#sleep $(( ${TimeForSleep} * 3 ))
# Определить на каких серверах запущены соответствующие сервисы
ListServersMon=(`ceph --status --format json-pretty | jq --raw-output .monmap.mons[].name`);
counter=1
until
  # Попытаться остановить сервис на всех соответствующих сервису серверах
  [[ -z "${ListServersMon[@]}" ]]; do
    if [ ${counter} -gt ${AmountAttempts} ]; then
      #echo -e ${Red}" Some Ceph MON daemons do not down"${NoColor}
      logger -i --priority local0.err --tag ${NameThisScript} "Остановка ceph продолжена, но некоторые сервисы MON не остановлены. Это может быть опасно."
      exit 0
    fi
    # Остановить MON и проверить остановились ли они на всех серверах из ListServersMon
    for i in "${!ListServersMon[@]}"; do
      ssh ${ListServersMon[i]} "sudo systemctl stop ceph-mon@${ListServersMon[i]}.service"
      OneMonStarted=`ssh ${ListServersMon[i]} "sudo systemctl is-active ceph-mon@${ListServersMon[i]}.service"`
      [ "${OneMonStarted}" = "inactive" ] && unset 'ListServersMon[i]'
    done
  sleep ${TimeForSleep}
  ((counter++))
done
#echo -e ${Yellow}" Все сервисы MON остановлены."${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Все сервисы MON остановлены."
DoNotStopingMons

fi

#echo -e ${GREEN}"end ${0}"${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Остановка ceph завершена успешно."

exit 0
