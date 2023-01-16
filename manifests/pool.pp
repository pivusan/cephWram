# = Define: pool
#
# == Назначение
#
# Ресурс для развёртывания ceph. Создание pool
#
# == Использование
#
# В виде define в составе модуля ceph. 
# При текущих параметрах k и m ($k=5, $m=2) и текущей политике защиты от отказа, необходимо развернуть как минимум 7 osd на как минимум 7-ми серверах.
#
# == Детали реализации
#
# Управление ресурсами посредством Puppet
#
# == Параметры
#
# [*ensure*]
#   Параметр отвечает за поддерживаемое состояние управляемых манифестом ресурсов.
#   Возможные значения: running (запущен), stopped (остановлен), absent (удалён), undef (манифест не применяется).
#   Передаётся в виде строки.
#   Стандартное значение: undef
#
# [*k и m*]
#   Параметры для профиля удаляющего кодирования (EC)
#   Данные в ceph сохраняются разделёнными на части.
#   Эти части в EC имеют название порций (chunks) "k" и "m",
#   где "k" обозначает общее число кусочков самих данных, а "m" обозначает общее число кусочков удаляющего кода.
#   Таким образом данные сохраняются в k + m частях. Не стоит задавать большие значения "k" и "m".
#   Передаётся в виде целых положительных чисел.
#   Стандартное значение: $k=5, $m=2.
#
# [*pg_num_ec  pg_num_replicated*]
#   Параметры pg для pools EC и replicated соответственно
#   Рассчитываются по сложной формуле. Очень важные параметры
#   Для расчёта pg_num можно пользоваться ссылкой ниже или следующей ориентировочной формулой (pg_num = ((Total_number_of_OSD * 100) / max_replication_count) с округлением до ближайшей степени 2. https://ceph.com/pgcalc/.
#   Передаются в виде целых положительных чисел.
#   Стандартное значение: Не существует.
#
# [*max_mds_fss*]
#   Параметр для задействования заданного количества mds в активном состоянии для каждой ФС
#   https://docs.ceph.com/en/latest/cephfs/multimds/
#   Заданное количество mds должно существовать. (Необходимое количество mds)=(Количество ФС)*(max_mds_fss)+(mds в резерве, хотя бы один, определяется из соображений отказоустойчивости). Например, для ФС на hdd и ram и max_mds_fss=2, минимальное количество mds=2*2+1=5
#   Возможные значения: 1,2... зависит от целесообразности использования дополнительного mds
#   Передаётся в виде целого положительного числа
#   Стандартное значение: 1
#
# Для этого манифеста не полностью реализовано удаление.
define ceph::pool
(
  $ensure              = undef,
  $k                   = $ceph::k,
  $m                   = $ceph::m,

  # For 1622
   # Для hdd:
    # $pg_num_ec         = 2048,
    # $pg_num_replicated = 256,
   # Для ram:
    # $pg_num_ec         = 512,
    # $pg_num_replicated = 64,
  # For ЦАГИ
   # Для hdd:
    # $pg_num_ec         = 1024,
    # $pg_num_replicated = 128,
   # Для ram:
    # $pg_num_ec         = 256,
    # $pg_num_replicated = 32,
  $pg_num_ec           = undef,
  $pg_num_replicated   = undef,

  $max_mds_fss         = $ceph::max_mds_fss,
)
{

  # Формальная проверка параметров модуля ceph
  $ensure_values = ['running', 'stopped', 'absent']
  unless (member($ensure_values, $ensure) or ($ensure == undef) ) {
    fail("Модуль ${module_name}. Параметр \$ensure=$ensure, но должен иметь значения 'running', 'stopped', 'absent', or 'undef'")
  }

  # Если принято решение применять модуль ceph штатно, то $apply_ceph = true
  if ( $ceph::apply_ceph == true ) and
    # И если параметр ensure не undef.
    ( $ensure in $ensure_values ) {

  # This should be a integer.
    Integer($pg_num_ec)
    Integer($pg_num_replicated)

    # Параметр указывает, какой из pool hdd или ram создать. Берётся из заголовка define при её вызове.
    # Возможные значения: hdd, ram.
    $type = "${title}"
    # Проверим имеет ли параметр ${type} допустимые значения:
    unless $type in [ 'hdd', 'ram' ] {
      # Если нет, то fail
      fail("Модуль ${module_name}. Параметр \${type}=${type}, но должен иметь значения 'hdd' или 'ram'.")
    }

    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    ####################  Ensure для разных типов  #################### 
    $ensure_object=$ensure ? {
      'running' => 'present',
      'stopped' => 'present',
      'absent'  => 'absent',
    }
    ###################################################################

    # Если нужно создать pool
    if $ensure in [ 'running', 'stopped' ] {

      #### Чтобы не писать отдельный манифест под команды, которые нужно выполнить один раз на всём кластере ceph, вставим их сюда, так как этот манифест применяется один раз на всём кластере ceph
 
      # Сообщаем ceph о том, что мы будем использовать несколько файловых систем одновременно
      # Идемпотентно не нашёл как сделать. Не должно сломаться, если выполнить несколько раз.
      exec { "${type}-MultipleFSCreate":
        command => 'ceph fs flag set enable_multiple true --yes-i-really-mean-it',
      }

      # Подключаем балансировщик нагрузки, так как в Astra он почему то отключен
      # https://docs.ceph.com/docs/luminous/mgr/balancer/
      exec { "${type}-BalancerCreate01":
        command => 'ceph mgr module enable balancer && ceph balancer on',
        unless  => 'ceph balancer status |grep active|grep true',
      } ->
      exec { "${type}-BalancerCreate02":
        command => 'ceph balancer mode crush-compat',
        unless  => 'ceph balancer status |grep mode|grep crush-compat',
      }
      ####

      # Создаем CRUSH правило размещения данных для pool метаданных
      exec { "${type}-Create01":
        command => "ceph osd crush rule create-replicated rule_replicated_${type} default host ${type}",
        unless  => "ceph osd crush rule ls|grep rule_replicated_${type}",
      } ->

      # Создаём pool метаданных
      exec { "${type}-Create02":
        command =>  "ceph osd pool create pool_replicated_${type}_metadata ${pg_num_replicated} ${pg_num_replicated}  replicated rule_replicated_${type}",
        unless  => "ceph osd pool ls|grep pool_replicated_${type}_metadata",
      } ->

      # Создаём создать profile для pool erasure
      exec { "${type}-Create03":
        command => "ceph osd erasure-code-profile set profile_erasure_${type} k=${k} m=${m} crush-failure-domain=host crush-device-class=${type}",
        unless  => "ceph osd erasure-code-profile ls|grep profile_erasure_${type}",
      } ->

      # Создаём pool EC для данных
      exec { "${type}-Create04":
        command =>  "ceph osd pool create pool_erasure_${type}_data  ${pg_num_ec} ${pg_num_ec} erasure profile_erasure_${type}",
        unless  => "ceph osd pool ls|grep pool_erasure_${type}_data",
      } ->

      # Обязательно нужно установить параметр allow_ec_overwrites на ЕС pool
      # Не может быть отменена. Только удалять сам pool
      exec { "${type}-Create05":
        command => "ceph osd pool set pool_erasure_${type}_data allow_ec_overwrites true",
        unless  => "ceph osd pool ls detail |grep pool_erasure_${type}_data |grep ec_overwrites",
      } ->

      # Создать файловую систему
      exec { "${type}-Create06":
        command => "ceph fs new ${type}_fs pool_replicated_${type}_metadata pool_erasure_${type}_data",
        unless  => "ceph fs ls|grep ${type}_fs",
        notify  => Ceph::Healthcheck["${type}-CheckHealthOk"]
      } ->

      # Increasing the MDS active cluster size
      exec { "${type}-Create07":
        command => "ceph fs set ${type}_fs max_mds ${max_mds_fss}",
        unless  => "ceph fs get ${type}_fs|grep max_mds|grep ${max_mds_fss}",
      }

    }
    elsif $ensure == 'absent' {
      # Для удаления pool необходимо провести много действий на всех серверах. Пока не понятно как это сделать на всех серверах сразу.
      # Пока опишем, что конкретно нужно сделать.

      # Отмонтировать ФС на всех серверах
      # Ceph::Mount<| ensure == $ensure_mounted |>

      # Остановить MDS даймоны на всех серверах, на которых они запущены
      # может зависнуть какой либо конкретный mds. Тогда конкретно его нужно сделать старт и стоп:
      #1. Посмотреть "ceph -s" какой mds завис
      #2. sudo systemctl start ceph-mds@pnode13ib.service
      #3. sudo systemctl stop ceph-mds@pnode13ib.service
      #    exec { "${type}-StopMDSDaemon":
      #      command => 'systemctl stop ceph-mds.target',
      #      unless  => 'systemctl status ceph-mds.target |grep Active| grep dead',
      #    } ->

      exec { "${type}-Absent01":
        command => "ceph fs rm ${type}_fs --yes-i-really-mean-it",
        onlyif  => "ceph fs ls|grep ${type}_fs",
      } ->

      exec { "${type}-Absent02":
        command => "ceph osd pool rm pool_replicated_${type}_metadata pool_replicated_${type}_metadata --yes-i-really-really-mean-it",
        onlyif  => "ceph osd pool ls|grep pool_replicated_${type}_metadata",
      } ->

      exec { "${type}-Absent03":
        command => "ceph osd crush rule rm rule_replicated_${type}",
        onlyif  => "ceph osd crush rule ls|grep rule_replicated_${type}",
      } ->


      exec { "${type}-Absent04":
        command => "ceph osd pool rm pool_erasure_${type}_data pool_erasure_${type}_data --yes-i-really-really-mean-it",
        onlyif  => "ceph osd pool ls|grep pool_erasure_${type}_data",
      } ->

      exec { "${type}-Absent05":
        command => "ceph osd erasure-code-profile rm profile_erasure_${type}",
        onlyif  => "ceph osd erasure-code-profile ls|grep profile_erasure_${type}",
      } ->

      exec { "${type}-Absent06":
        command => "ceph osd crush rule rm pool_erasure_${type}_data",
        onlyif  => "ceph osd crush rule ls|grep pool_erasure_${type}_data",
      }

      # Не понятно, срабатывает ли флаг false
      exec { "${type}-MultipleFSAbsent":
        command => 'ceph fs flag set enable_multiple false --yes-i-really-mean-it',
      }

      exec { "${type}-BalancerAbsent":
        command => 'ceph mgr module enable balancer && ceph balancer off',
        unless  => 'ceph balancer status |grep active|grep false',
        notify  => Ceph::Healthcheck["${type}-CheckHealthOk"]
      }
    }
    ###################################################################

    # Экспортируем ресурс file_line, для использования на других узлах. Таким образом осуществляется передача параметров pg_num_* в скрипты выключения и включения ceph
    @@file_line { "pg_num_ec_${type}":
      ensure            =>  $ensure_object,
      path              =>  '/home/cephadm/cephdeploy/conf/ceph.env',
      line              =>  "pg_num_ec_${type}=${pg_num_ec}",
      match             => "^pg_num_ec_${type}",
      match_for_absence =>  true,
      tag               =>  'ceph.env',
    }
    @@file_line { "pg_num_replicated_${type}":
      ensure            =>  $ensure_object,
      path              =>  '/home/cephadm/cephdeploy/conf/ceph.env',
      line              =>  "pg_num_replicated_${type}=${pg_num_replicated}",
      match             => "^pg_num_replicated_${type}",
      match_for_absence =>  true,
      tag               =>  'ceph.env',
    }

    # Ресурсы манифеста pool.pp используемые различными блоками кода манифеста pool.pp

    # Проверка, что установка ceph прошла удачно. Выполняем exec-ом команду ceph health и ожидаем, что она вернёт "HEALTH_OK".
    ceph::healthcheck{"${type}-CheckHealthOk":}
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в значении параметра ensure или ensure = undef.
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure было одним из следующих [running, stopped, absent]")
  }
}
