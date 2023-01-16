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

  NameThisScript=ceph_up.sh # Имя текущего скрипта для передачи в logger

  AmountAttempts=10 # Количество попыток выполнения атомарной операции
  TimeForSleep=10 # Время в секундах для ожидания после выполнения атомарной операции
  MaxTimeToWait=1800 # Время в секундах для ожидания успешного завершения скрипта на leader MON

  NameRamFS=ram_fs # Имя, данное RAM fs при установке ceph
  NameRamPoolMetadata=pool_replicated_ram_metadata # Имя, данное RAM pool для metadata при установке ceph
  NameRamPoolData=pool_erasure_ram_data # Имя, данное RAM pool для data при установке ceph
  NameRamProfileData=profile_erasure_ram # Имя, данное profile RAM pool data при установке ceph
  NameRamRuleMetadata=rule_replicated_ram # Имя, данное rule RAM pool metadata при установке ceph

  # Получить через файл от модуля ceph параметры. Проверку на наличие файла не делаем, если его не будет, то что то пошло не так и здесь будет ошибка.
  source /home/cephadm/cephdeploy/conf/ceph.env

  cephfs_basedir=${cephfs_basedir} # Начальная директория относительно которой монтируются pools ceph (например, hdd и ram)

  # Параметр помогает выделить RAM OSD из всех OSD. У RAM OSD объём отличается от HDD OSD.
  osdramWeight=${osdramWeight}
  # Параметры для профиля удаляющего кодирования (EC)
  k=${k}
  m=${m}
  # Параметр для задействования заданного количества mds в активном состоянии для каждой ФС
  max_mds_fss=${max_mds_fss}
  # Параметры pg для pools EC и replicated соответственно
  pg_num_ec_ram=${pg_num_ec_ram}
  pg_num_replicated_ram=${pg_num_replicated_ram}

# Загрузить функции из файла
  source /home/cephadm/cephdeploy/functions.sh

# Help
if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]; then
  echo
  echo " Скрипт предназначен для подготовки к работе ceph"
  echo " Для корректной работы этого скрипта необходимо, чтобы скрипт подготовки к выключению кластера ceph отработал корректно и состояние ceph было HEALTH_OK (все MDSs, OSDs и MONs запустились и достигнут quorum)"
  echo " Использование: ${NameThisScript}"
  echo
  exit 0
fi

# Определить состояние ceph посредством вызова функции
  check_health

#echo -e ${Yellow}" Create RAM disk."${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Создание RAM OSD на текущем сервере..."
  # Сформировать имя сервера из его короткого имени и префикса ib. Такое у нас соглашение об именовании интерфейса передачи данных (обычно это Infiniband интерфейс) сервера.
    ServerName=${HOSTNAME}
    ServerNameIB=${HOSTNAME}ib
  # Заменить hostname сервера на ServerNameXXib
    sudo hostnamectl set-hostname ${ServerNameIB}
    #echo -e ${Yellow}" Server name set=`hostname -s`"${NoColor}
    sleep ${TimeForSleep}

  # В связи с тем, что class ram OSD на текущем сервере может измениться скриптом, запущенным на другом сервере, результат проверки class ram osd может быть ошибочным. Пришлось переделать проверку.
  # Более того, формируя RAM_OSD необходимо отсортировать osd только в состоянии "up".
  # Создать RAM OSD и проверить его создание
    counter=1
    CreateRAMOSD=unsuccess
    until
      # Основываясь на weight osd, сформировать список RAM OSD
        RAM_OSD=`ceph osd tree | grep osd | grep ${osdramWeight} | grep up | awk '{print $1}'`;
      for osd in ${RAM_OSD}; do
        # Определить имя сервера на котором создан osd из списка RAM_OSD
          ServerWithRamOSD=`ceph osd find ${osd} | jq --raw-output .crush_location.host`;
        # Если имя (с префиксом "ib") текущего сервера, совпадает с именем сервера на котором создан какой либо osd из списка RAM_OSD, тогда на текущем сервере osd создался.
        [ "${ServerNameIB}" = "${ServerWithRamOSD}" ] && CreateRAMOSD=success;
      done;
    [ "${CreateRAMOSD}" = "success" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" RAM disk do not create"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. RAM OSD на текущем сервере не создан. Для запуска ceph, RAM OSD на текущем сервере должен быть создан. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        sudo hostnamectl set-hostname ${ServerName}
        #echo -e ${Yellow}" Server name set=`hostname -s`"${NoColor}
        sleep ${TimeForSleep}
        exit 1
      fi
      # Создать OSD на Ram диске. Сам RAM диск (/dev/ram0) создаётся силами ОС при загрузке.
        sudo /usr/sbin/ceph-volume lvm create --data /dev/ram0 --crush-device-class ram
      sleep ${TimeForSleep}
      ((counter++))
    done
  # Вернуть hostname сервера
    sudo hostnamectl set-hostname ${ServerName}
    #echo -e ${Yellow}" Server name set=`hostname -s`"${NoColor}
#echo -e ${Yellow}" Create RAM disk successful"${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "RAM OSD на текущем сервере создан."

<<Block_comment
Теперь не применяется, так как создаём ram osd сразу с правильным классом ram
#echo -e ${Yellow}" Set correct RAM OSD class"${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Установка корректного класса RAM OSD..."
    counter=1
    CorrectRAMClass=unsuccess
  until
    # Скорректировать класс для всех RAM OSD кластера ceph
    # Скрипт osdramCorrectClass.sh входит в состав модуля ceph и используется им
      bash osdramCorrectClass.sh;
    # Основываясь на weight osd, сформировать список RAM OSD с верным классом.
      OSD_CORRECT_CLASS_RAM=`ceph osd tree --format json-pretty | jq '.nodes[] | select(.device_class=="ram").id'`;
    for osd in $OSD_CORRECT_CLASS_RAM; do
      # Определить имя сервера на котором создан osd из списка OSD_CORRECT_CLASS_RAM
        ServerWithCorrectRAMClass=`ceph osd find ${osd} | jq --raw-output .crush_location.host`
      # Если имя (с префиксом "ib") текущего сервера, совпадает с именем сервера на котором создан какой либо osd из списка OSD_CORRECT_CLASS_RAM, тогда на текущем сервере, установился верный class для RAM osd.
        [ "${ServerNameIB}" = "${ServerWithCorrectRAMClass}" ] && CorrectRAMClass=success;
    done;
  [ "${CorrectRAMClass}" = "success" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" RAM OSD class do not set correct"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. Корректный класс RAM OSD на текущем сервере не установлен. Для запуска ceph, на текущем сервере должен быть установлен корректный класс RAM OSD. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      sleep ${TimeForSleep}
      ((counter++))
  done
#echo -e ${Yellow}" RAM OSD class set correct"${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Корректный класс RAM OSD на текущем сервере установлен."
Block_comment

# Дальнейшие шаги по запуску ceph выполнять только на leader MON. То есть запуск ceph проводить на одном сервере. На всех остальных серверах ожидать.
  # Определить leader MON
    LeaderMon=`ceph quorum_status --format json-pretty | jq --raw-output .quorum_leader_name`

  if [ "${ServerNameIB}" != "${LeaderMon}" ]; then
    #echo -e ${Yellow}" Server do not leader MON. Wait..."${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Текущий сервер не leader MON. Ожидаем окончания работы скрипта подготовки к работе ceph на leader MON..."

    # Здесь, в цикле until, происходит проверка условия установки параметра max_mds_fss у RAM FS. Установки параметра max_mds_fss у RAM FS выполняется последним шагом при создании RAM pool. Выполнение условия говорит нам о том, что скрипт на leader MON почти отработал и можно приступать к монтированию CephFS на текущем сервере.
    # Если с ceph будет что то не так, то скрипт на leader MON отработает с ошибкой, а на текущем сервере скрипт в нижележащем цикле выйдет по условию превышения встроенного в bash параметра $SECONDS (параметр отражает время работы скрипта) над параметром ${MaxTimeToWait}
    # Look down :PenultimateStepMark
    unset CurrentMax_mds_fss
    until
      # Получить данные, существует ли FS
        LSNameRamFS=`ceph fs ls --format json-pretty | jq --raw-output --arg jqNameRamFS ${NameRamFS} '.[]|select(.name==$jqNameRamFS).name'`
      # Получить данные, в какое значение установлен параметр max_mds_fss
        [ -n "${LSNameRamFS}" ] && CurrentMax_mds_fss=`ceph fs get ${NameRamFS} --format json-pretty | jq .mdsmap.max_mds`;
      [ "${CurrentMax_mds_fss}" = "${max_mds_fss}" ]; do
      if [ $SECONDS -gt ${MaxTimeToWait} ]; then
        #echo -e ${Red}" Exceed MaxTimeToWait"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. Превышено время ожидания окончания работы скрипта подготовки к работе ceph на leader MON. Необходимо просмотреть журналы каждого сервера ceph, найти leader MON и в сообщениях в его журнале узнать причину прерывания на нём запуска ceph."
        exit 1
      fi
      # echo " Nothing to do. We wait..."
      sleep ${TimeForSleep}
    done
  else
    #echo -e ${Yellow}" Server - leader MON. Doing something on this server."${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Текущий сервер leader MON. Приступаем к подготовке к работе ceph."

    #echo -e ${Yellow}" Those flags should be totally sufficient to safely powerdown your cluster but you could also set the following flags on top if you would like to pause your cluster completely"${NoColor}
      #ceph osd set noout    # If you do not want CRUSH to automatically rebalance the cluster as you stop OSDs for maintenance, set the cluster to noout first
      #ceph osd set nobackfill  #nobackfill и norecover делают одно и то же. В коде они отключают процесс recover немного по-разному, но результат один: полная остановка recovery io. 
      #ceph osd set norecover
      # На всякий случай добавить и эти флаги:
      #ceph osd set norebalance  # Флаг norebalance отличается. Он позволяет процессу recovery io идти только в случае, если placement group находится в состоянии degraded.
      #ceph osd set nodown    # prevent OSDs from getting marked down
      #ceph osd set pause     # Флаг pause по сути останавливает клиентское io. Никто из клиентов не сможет ни читать, ни писать из pools Ceph.

      #ceph osd dump | grep flags
      # В заключение скажу: все описанные флаги можно использовать только при внимательном контроле за кластером. Нельзя оставлять их и уходить спать. Они нужны для блокирования естественных процессов, протекающих в Ceph, а сами по себе эти процессы правильные. Система способна сама себя восстанавливать и балансировать. Поэтому блокировать естественные состояния Ceph можно только находясь у компьютера и контролируя процесс
    #echo -e ${Yellow}" Set flags"${NoColor}

    #echo -e ${Yellow}" Create rules for RAM pool metadata"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Создание правила для RAM pool metadata..."
    counter=1
    until
      # Сформировать список CRUSH правил для RAM pool метаданных
        LsNameRamRuleMetadata=`ceph osd crush rule ls --format json-pretty | jq --raw-output '.[]' | grep ${NameRamRuleMetadata}`;
      [ -n "${LsNameRamRuleMetadata}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" RAM rules for pool metadata do not create"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. Правило для RAM pool metadata не создано. Для запуска ceph, правило для RAM pool metadata должно быть создано. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      # Попытаться создать CRUSH правило для RAM pool метаданных
        ceph osd crush rule create-replicated ${NameRamRuleMetadata} default host ram
      sleep ${TimeForSleep}
      ((counter++))
    done
    #echo -e ${Yellow}" Create RAM rules for pool metadata successful"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Правило для RAM pool metadata создано."

    #echo -e ${Yellow}" Create RAM pools metadata."${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Создание RAM pool metadata..."
    counter=1
    until
      # Сформировать список RAM pools metadata
        LsNameRamPoolMetadata=`ceph osd pool ls --format json-pretty | jq --raw-output '.[]' | grep ${NameRamPoolMetadata}`;
      [ -n "${LsNameRamPoolMetadata}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
       #echo -e ${Red}" RAM pools metadata do not create"${NoColor}
       logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. RAM pool metadata не создан. Для запуска ceph, RAM pool metadata должен быть создан. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
       exit 1
      fi
      # Попытаться создать RAM pools metadata
        ceph osd pool create ${NameRamPoolMetadata} ${pg_num_replicated_ram} ${pg_num_replicated_ram} replicated ${NameRamRuleMetadata}
      sleep ${TimeForSleep}
      ((counter++))
    done
    #echo -e ${Yellow}" RAM pools metadata create successful"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "RAM pool metadata создан."

    #echo -e ${Yellow}" Create profile for RAM pool erasure"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Создание profile для RAM pool erasure..."
    counter=1
    until
      # Сформировать список profile для RAM pool erasure
        LsNameRamProfileData=`ceph osd erasure-code-profile ls --format json-pretty | jq --raw-output '.[]' | grep ${NameRamProfileData}`;
      [ -n "${LsNameRamProfileData}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
       #echo -e ${Red}" Profile for RAM pool erasure do not create"${NoColor}
       logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. Profile для RAM pool erasure не создан. Для запуска ceph, profile для RAM pool erasure должен быть создан. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
       exit 1
      fi
      # Попытаться создать profile для RAM pool erasure
        ceph osd erasure-code-profile set ${NameRamProfileData} k=${k} m=${m} crush-failure-domain=host crush-device-class=ram
      sleep ${TimeForSleep}
      ((counter++))
    done
    #echo -e ${Yellow}" Profile for RAM pool erasure create successful"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Profile для RAM pool erasure создан."

    #echo -e ${Yellow}" Create RAM pools data"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Создание RAM pool data..."
    counter=1
    until
      # Сформировать список RAM pools data
        LsNameRamPoolData=`ceph osd pool ls --format json-pretty | jq --raw-output '.[]' | grep ${NameRamPoolData}`;
      [ -n "${LsNameRamPoolData}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
       #echo -e ${Red}" RAM pools data do not create"${NoColor}
       logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. RAM pool data не создан. Для запуска ceph, RAM pool data должен быть создан. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
       exit 1
      fi
      # Попытаться создать RAM pools data
        ceph osd pool create ${NameRamPoolData} ${pg_num_ec_ram} ${pg_num_ec_ram} erasure ${NameRamProfileData}
      sleep ${TimeForSleep}
      ((counter++))
    done
    #echo -e ${Yellow}" RAM pools data create successful"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "RAM pool data создан."

    #echo -e ${Yellow}" Set parameter allow_ec_overwrites"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Установить параметр allow_ec_overwrites..."
    # Обязательно нужно установить параметр allow_ec_overwrites на erasure RAM pool. Операция не может быть отменена. Только удалять сам pool
    counter=1
    until
      # Получить данные, установлен ли параметр
        allow_ec_overwrites=`ceph osd pool ls detail -f json | jq --raw-output --arg jqNameRamPoolData ${NameRamPoolData} '.[] | select(.pool_name==$jqNameRamPoolData).flags_names' | grep ec_overwrites`;
      [ -n "${allow_ec_overwrites}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" Parameter allow_ec_overwrites do not set"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. Параметр allow_ec_overwrites не установлен. Для запуска ceph, параметр allow_ec_overwrites должен быть установлен. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      # Попытаться установить allow_ec_overwrites
        ceph osd pool set ${NameRamPoolData} allow_ec_overwrites true
      sleep ${TimeForSleep}
      ((counter++))
    done
    #echo -e ${Yellow}" Parameter allow_ec_overwrites set successful"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Параметр allow_ec_overwrites установлен."

    echo -e ${Yellow}" Create RAM FS"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Создать RAM FS..."
    # Создаём файловую систему RAM FS
    counter=1
    until
      # Сформировать список RAM FS
       LsNameRamFS=`ceph fs ls --format json-pretty | jq --raw-output --arg jqNameRamFS ${NameRamFS} '.[] | select(.name==$jqNameRamFS).name'`;
      [ -n "${LsNameRamFS}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" RAM FS do not create"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. RAM FS не создана. Для запуска ceph, RAM FS должна быть создана. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      # Попытаться создать RAM FS
        ceph fs new ${NameRamFS} ${NameRamPoolMetadata} ${NameRamPoolData}
      sleep ${TimeForSleep}
      ((counter++))
    done
    #echo -e ${Yellow}" RAM FS create successful"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "RAM FS создана."

    # :PenultimateStepMark
    #echo -e ${Yellow}" Set parameter max_mds_fss"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Установить параметр max_mds_fss"
    # Задать требуемое количество mds в активном состоянии для RAM FS
    counter=1
    until
      # Получить данные, в какое значение установлен параметр max_mds_fss
        CurrentMax_mds_fss=`ceph fs get ${NameRamFS} --format json-pretty | jq .mdsmap.max_mds`;
      [ "${CurrentMax_mds_fss}" = "${max_mds_fss}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" Parameter max_mds_fss do not set"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. Параметр max_mds_fss не установлен. Для запуска ceph, параметр max_mds_fss должен быть установлен. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      # Попытаться установить параметр max_mds_fss
        ceph fs set ${NameRamFS} max_mds ${max_mds_fss}
      sleep ${TimeForSleep}
      ((counter++))
    done
    #echo -e ${Yellow}" Parameter max_mds_fss set successful"${NoColor}
    logger -i --priority local0.info --tag ${NameThisScript} "Параметр max_mds_fss установлен."
  fi

# Определить состояние ceph посредством вызова функции
  check_health

# Далее, если все действия написанные выше выполнились успешно, значит, ceph готов к монтированию. Действие выполняется на каждом сервере.
  #echo -e ${Yellow}" Mount CephFS on current server."${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Монтирование CephFS на текущем сервере..."
  counter=1
  until
    # Определить, смонтирована ли директория ceph на текущем сервере
    LsCephfsRAM=`mount | grep ${cephfs_basedir}/ram`;
    LsCephfsHDD=`mount | grep ${cephfs_basedir}/hdd`;
    [ -n "${LsCephfsRAM}" ] && [ -n "${LsCephfsHDD}" ]; do
      if [ ${counter} -gt ${AmountAttempts} ]; then
        #echo -e ${Red}" CephFS do not mount on current server"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Подготовка к работе ceph прервана. CephFS не примонтирован на текущем сервере. Необходимо примонтировать CephFS на текущем сервере. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      # Смонтировать HDD и RAM pools
        sudo mount ${cephfs_basedir}/hdd
        sudo mount ${cephfs_basedir}/ram
      sleep ${TimeForSleep}
      ((counter++))
  done
  #echo -e ${Yellow}" Mount CephFS successful"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "CephFS примонтирована на текущем сервере."

# Пока не знаю, как сделать правильно...
sudo chmod 777 ${cephfs_basedir}/ram

#echo -e ${GREEN}" end ${0}"${NoColor}
logger -i --priority local0.info --tag ${NameThisScript} "Запуск ceph завершен успешно."

exit 0
