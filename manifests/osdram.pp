# = Class: osdram
#
# == Назначение
#
# Манифест для развёртывания ceph. Развёртывание OSD на RAM дисках.
#
# == Использование
#
# В виде класса в составе модуля ceph. При текущих параметрах k и m, необходимо развернуть всего как минимум 7 osd на как минимум 7 серверах.
# Размер pool задаётся в манифесте pool соответствующего osd.
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
#   Стандартное значение: "running"
#
# [*osdramWeight*]
#   Параметр помогает выделить RAM OSD из всех OSD. У RAM OSD объём отличается от HDD OSD.
#   Параметры osdramWeight и osd_ram_size  связаны - Weight OSD примерно равен объёму этого диска, выраженному в ТБ.
#   Возможные значения: 0.25000 для диска объёмом 256 GB; 0.00189 для диска объёмом 2 GB; 0.29300 для диска объёмом 300 GB.
#   Передаётся в виде строки.
#   Стандартное значение: "0.25000"
#
# [*forceDelLvmOsdRam*]
#   Параметр указывающий, удалять ли lvm на устройствах, на которых создаём osd ceph (ram)
#   Возможные значения: true (удалять lvm на osd), false (не удалять lvm на osd. Но тогда будет ошибка при создании osd, если на ram есть lvm).
#   Передаётся в виде строки.
#   Стандартное значение: false
#
# [*typeosd*]
#   Параметр отвечает за проверку OSD по типам.
#   Возможные значения: ram (проверяются osd на ram дисках), hdd (проверяются osd на hdd дисках).
#   Передаётся в виде строки.
#   Стандартное значение: отсутствует

class ceph::osdram
(
  $ensure            = 'running',
  $osdramWeight      = $ceph::osdramWeight,
  $forceDelLvmOsdRam = $ceph::forceDelLvmOsdRam,
  $typeosd           = 'ram',
)
{

  # Формальная проверка параметров модуля ceph
  $ensure_values = ['running', 'stopped', 'absent']
  unless (member($ensure_values, $ensure) or ($ensure == undef) ) {
    fail("Модуль ${module_name}. Параметр \$ensure=$ensure, но должен иметь значения 'running', 'stopped', 'absent', or 'undef'")
  }

  unless ( $typeosd == 'ram' ) {
    fail("Модуль ${module_name}. Параметр \$typeosd=$typeosd, но должен иметь значения 'ram'")
  }

  # Если принято решение применять модуль ceph штатно, то $apply_ceph = true
  if ( $ceph::apply_ceph == true ) and
    # И если параметр ensure не undef.
     ( $ensure in $ensure_values ) {
    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    # Зависимости между классами. Текущий класс требуется применить после класса 'ceph::system'
    require ceph::system

    # Необходимо сохранить текущее имя сервера. На текущем шаге имя сервера резолвится в IP адрес eth интерфейса сервера (pnodeXX)
    # Пример: имя сервера - pnode04, IP - 192.168.166.44
    $osdramNameServer=$facts['hostname']

    # Тогда имя сервера указывающего на интерфейс Infiniband, необходимый для установки ceph, будет (pnodeXXib):
    $osdramNameServerIB="${osdramNameServer}ib"

    ####################  Ensure для разных типов  #################### 
    $ensure_object=$ensure ? {
      'running' => 'present',
      'stopped' => 'present',
      'absent'  => 'absent',
    }
    ###################################################################

    if $ensure != 'absent' {
      # Если коллектор найдёт пакет ceph-mon, значит класс 'ceph::mon' есть, тогда текущий класс следует применить после класса 'ceph::mon'.
      # Это особенно нужно, когда устанавливается первый MON
      Package <| name == 'ceph-mon' |> ->
      Package['ceph-osd'] ->
      # Получить файл /etc/ceph/ceph.conf из внешнего ресурса
#      File <<| tag == 'etc_ceph_conf' |>> ->
      # В новой реализации, взять файл /etc/ceph/ceph.conf из шаблона
      File[ '/etc/ceph/ceph.conf'] ->
      File['/etc/ceph/ceph.client.admin.keyring'] ->

      # Поменять имя хоста на имя по которому резолвится Infiniband интерфейс сервера (pnodeXXib)
      # Использование тире в имени сервера приводит к ошибке развёртывания ceph
      # Смена имени сейчас необходима, чтобы обмен данными внутри кластера ceph и взаимодействие его с клиентами шло по Infiniband интерфейсу
      exec { 'osdramNameServerIB':
        command => "hostnamectl set-hostname ${osdramNameServerIB}",
        unless  => "/usr/bin/test ${osdramNameServerIB} = `/bin/cat /etc/hostname`",
      } ->

      # Создать bootstrap ключ
      exec { 'osdramBootstrapKeyAdd':
        command => 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/ceph.keyring',
        creates => '/var/lib/ceph/bootstrap-osd/ceph.keyring',
        before  => Exec['osdramCephVolumeCreate'],
      } #->

      # Если параметр forceDelLvmOsdRam установлен в true, удалить, lvm с RAM OSD
      if $forceDelLvmOsdRam == true {
#        exec { 'forceDelDdRam':
#          command => 'dd if=/dev/zero of=/dev/ram0 bs=25M count=1',
#          before  => Exec['forceDelVgremoveRam'],
#        }
        exec { 'forceDelVgremoveRam':
         command => "/sbin/vgremove -f `/sbin/pvs -ovg_name --noheadings /dev/ram0` || { echo \"Ошибка удаления VG на диске /dev/ram0\"; exit 1; }",
         onlyif  => "/sbin/pvs -ovg_name --noheadings /dev/ram0",
         before  => Exec['forceDelPvremoveRam'],
         after   => Exec['osdramBootstrapKeyAdd'],
        }
        exec { 'forceDelPvremoveRam':
          command => "/sbin/pvremove /dev/ram0",
          onlyif  => "/usr/bin/test -b /dev/ram0",
          before  => Exec['osdramCephVolumeCreate'],
        }
      }

      # Создать OSD на Ram диске
      exec { 'osdramCephVolumeCreate':
        command => 'ceph-volume lvm create --data /dev/ram0 --crush-device-class ram',
        unless  => 'pvdisplay 2> /dev/null |grep /dev/ram0',
        notify => Ceph::Healthcheck[osdramCheckHealthOk],
      } ->

/* Теперь не применяется, так как создаём ram osd сразу с правильным классом ram
      # Откоректировать неправильный класс Ram OSD на всех серверах (выделять конкретный сервер, нет необходимости).
      # sleep используется потому что между командами создания osd на Ram диске (предыдущая команда ceph-volume lvm create --data /dev/ram0) и командой проверки наличия этого созданного osd (onlyif  => "sleep 20 && ceph osd tree|grep hdd |grep ${osdramWeight}",) проходит мало времени и новый osd не успевает попасть в CRUSH таблицу
      file { '/home/cephadm/cephdeploy/osdramCorrectClass.sh':
        ensure  => 'present',
        group   => 'cephadm',
        owner   => 'cephadm',
        mode    => '0700',
        content => file('ceph/osdramCorrectClass.sh'),
      } ->
      exec { 'osdramCorrectClass':
        command => "/home/cephadm/cephdeploy/osdramCorrectClass.sh",
        onlyif  => "sleep 20 && ceph osd tree|grep hdd |grep ${osdramWeight}",
      } ->
*/

      # Вернуть имя хоста серверу по которому резолвится Ethernet интерфейс, например pnode04.
      # sleep используется потому что после команды создания osd на Ram диске (ceph-volume lvm create --data /dev/ram0) проходит мало времени и новый osd не успевает попасть в CRUSH таблицу. Меняется имя хоста потом добавляется Ram диск уже под именем хоста без "ib"
      exec { 'osdramNameServer':
        command => "hostnamectl set-hostname ${osdramNameServer}",
        unless  => "sleep 20 && /usr/bin/test ${osdramNameServer} = `/bin/cat /etc/hostname`",
      } ->

      # Создаём условия для мониторинга OSD на HDD.
      ceph::monitoring { 'osdram':
        typeosd => 'ram',
      } ->

      Service['ceph-osd.target']

    }
    else {
      exec { 'osdramDel':
       # Предполагаем, что имя класса устройств для идентификации ram osd и построения CRUSH правил - ram. Имя устройства Ram диска /dev/ram0. Нужно это вынести в параметры модуля ceph
        command =>  '/home/cephadm/cephdeploy/osdDel.sh ram /dev/ram0',
        # Запускаем скрипт удаления osd на Ram дисках только тогда, когда есть ceph physical volume на ram osd.
        # Закоментировал проверку наличия lvm на RAM, так как после перезагрузки сервера никакого lvm на RAM OSD быть не может, а удалять Osd на RAM диске всё равно нужно.
        # onlyif  => 'pvs |grep ceph |grep ram0',
        notify => Ceph::Healthcheck[osdramCheckHealthOk],
      } ->

      #    Found 1 dependency cycle:
      #    Service['ceph-osd.target'] ->

      # Возможно, кроме удаления файлов, необходимо удалять и ключи, которые можно посмотреть командой "ceph auth ls".
      # Пока, для простоты, не будем удалять ключи.
      Exec['safelyDelBootstrapOsdCephKeyring'] ->

      Package['ceph-osd'] ->
#      Exec['safelyDelCephConf'] ->
      File[ '/etc/ceph/ceph.conf'] ->
      File['/etc/ceph/ceph.client.admin.keyring']
    }

    # Ресурсы манифеста osdram.pp используемые различными блоками кода манифеста osdram.pp

    # Проверка, что установка ceph прошла удачно. Выполняем exec-ом команду ceph health и ожидаем, что она вернёт "HEALTH_OK". Здесь это не работает,  так как ~> не срабатывает.
    ceph::healthcheck{'osdramCheckHealthOk':}
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в значении параметра ensure или ensure = undef.
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure было одним из следующих [running, stopped, absent]")
  }
}
