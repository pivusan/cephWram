# Этот файл был создан puppet модулем ceph
#
# Файл содержит функции для использования в других скриптах

# Функция проверки состояния ceph
check_health () {
  #echo -e ${Yellow}" The cluster must be in healthy state before proceeding."${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Проверка состояния ceph..."
  counter=1
  AmountAttempts_HEALTH_OK=15 # Количество попыток выполнения проверки состояния ceph
  TimeForSleep_HEALTH_OK=60 # Время в секундах для ожидания
  until
    # Определить состояние ceph
      CephHealth=`ceph health`;
    [ "${CephHealth}" = "HEALTH_OK" ]; do
      if [ ${counter} -gt ${AmountAttempts_HEALTH_OK} ]; then
        #echo -e ${Red}" Ceph do not HEALTH_OK"${NoColor}
        logger -i --priority local0.err --tag ${NameThisScript} "Сбой. Ceph в состоянии ${CephHealth}. Ceph должен быть в состоянии HEALTH_OK. Смотри Руководство по эксплуатации на СПО КВР (АФЕК.467379.395 РЭ) раздел Перечень возможных неисправностей..."
        exit 1
      fi
      sleep ${TimeForSleep_HEALTH_OK}
      ((counter++))
    done
  #echo -e ${Yellow}" Ceph healthy"${NoColor}
  logger -i --priority local0.info --tag ${NameThisScript} "Ceph в состоянии ${CephHealth}."
}
