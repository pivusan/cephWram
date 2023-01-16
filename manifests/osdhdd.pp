# = Class: osdhdd
#
# == Назначение
#
# Манифест для развёртывания ceph. Развёртывание OSD на HDD дисках.
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
# [*nameDisksOsdHdd*]
#   Параметр указывающий какие HDD использовать для развёртывания OSD. Информация на этих дисках удаляется, поэтому заполнять параметр следует очень аккуратно.
#   Возможные значения: ['/dev/sdb', '/dev/sdc', '/dev/sdd', '/dev/sde', '/dev/sdf', '/dev/sdg']
#   Передаётся в виде массива имён устройств.
#   Стандартное значение: Не существует.
#
# [*forceDelLvmOsdHdd*]
#   Параметр указывающий, удалять ли lvm на устройствах, на которых создаём osd ceph (hdd)
#   Возможные значения: true (удалять lvm на osd), false (не удалять lvm на osd. Но тогда будет ошибка при создании osd, если на hdd есть lvm).
#   Передаётся в виде строки.
#   Стандартное значение: false
#
# [*typeosd*]
#   Параметр отвечает за проверку OSD по типам.
#   Возможные значения: ram (проверяются osd на ram дисках), hdd (проверяются osd на hdd дисках).
#   Передаётся в виде строки.
#   Стандартное значение: отсутствует

class ceph::osdhdd
(
  $ensure            = 'running',
  $nameDisksOsdHdd   = $ceph::nameDisksOsdHdd,
  $forceDelLvmOsdHdd = $ceph::forceDelLvmOsdHdd,
  $typeosd           = 'hdd',
)
{

  # Формальная проверка параметров модуля ceph
  $ensure_values = ['running', 'stopped', 'absent']
  unless (member($ensure_values, $ensure) or ($ensure == undef) ) {
    fail("Модуль ${module_name}. Параметр \$ensure=$ensure, но должен иметь значения 'running', 'stopped', 'absent', or 'undef'")
  }

  unless ( $typeosd == 'hdd' ) {
    fail("Модуль ${module_name}. Параметр \$typeosd=$typeosd, но должен иметь значения 'hdd'")
  }

  # Если принято решение применять модуль ceph штатно, то $apply_ceph = true
  if ( $ceph::apply_ceph == true ) and
    # И если параметр ensure не undef.
     ( $ensure in $ensure_values ) {
    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    # Зависимости между классами. Текущий класс требуется применить после класса 'ceph::system'
    require ceph::system

    # Необходимо сохранить список устройств сервера, на которых будут устанавливаться OSD на HDD. Затем этот список используется в скрипте удаления OSD на HDD
    $nameDisksOsdHddForScript=join($nameDisksOsdHdd, ' ')

    # Необходимо сохранить текущее имя сервера. На текущем шаге имя сервера резолвится в IP адрес eth интерфейса сервера (pnodeXX)
    # Пример: имя сервера - pnode04, IP - 192.168.166.44
    $osdhddNameServer=$facts['hostname']

    # Тогда имя сервера указывающего на интерфейс Infiniband, необходимый для установки ceph, будет (pnodeXXib):
    $osdhddNameServerIB="${osdhddNameServer}ib"

    #################  Последовательность применения  #################
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
      exec { 'osdhddNameServerIB':
        command => "hostnamectl set-hostname ${osdhddNameServerIB}",
        unless  => "/usr/bin/test ${osdhddNameServerIB} = `/bin/cat /etc/hostname`",
      } ->

      # Создать bootstrap ключ для bootstrap-osd 
      exec { 'osdhddBootstrapKeyAdd':
        command => 'ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/ceph.keyring',
        creates => '/var/lib/ceph/bootstrap-osd/ceph.keyring',
      } # ->

      # Здесь подразумевается вызов функции $nameDisksOsdHdd.each реализовано указанием параметра require и before. Напрямую на функцию поставить зависимость стрелочкой (->) нельзя.
      # Adding bluestore OSDs
      $nameDisksOsdHdd.each |String $hdd| {
        if $forceDelLvmOsdHdd == true {
#          exec { "forceDelDd${hdd}":
#            command => "dd if=/dev/zero of=${hdd} bs=25M count=1",
#            before  => Exec["forceDelVgremove${hdd}"],
#          }
          exec { "forceDelVgremove${hdd}":
            command => "/sbin/vgremove -f `/sbin/pvs -ovg_name --noheadings ${hdd}` || { echo \"Ошибка удаления VG на диске ${hdd}\"; exit 1; }",
            onlyif  => "/sbin/pvs -ovg_name --noheadings ${hdd}",
            before  => Exec["forceDelPvremove${hdd}"],
          }
          exec { "forceDelPvremove${hdd}":
            command => "/sbin/pvremove ${hdd} || { echo \"Ошибка удаления PV на диске ${hdd}\"; exit 1; }",
            onlyif  => "/usr/bin/test -b ${hdd}",
            before  => Exec["osdhddCreate${hdd}"],
          }
        }
        exec { "osdhddCreate${hdd}":
          command => "ceph-volume lvm create --data ${hdd} --crush-device-class hdd",
          unless  => "/sbin/pvdisplay 2> /dev/null |grep ${hdd}",
          require => Exec['osdhddBootstrapKeyAdd'],
          before  => Exec['osdhddNameServer'],
          notify => Ceph::Healthcheck[osdhddCheckHealthOk],
        }
      } # ->

      # Вернуть имя хоста серверу по которому резолвится Ethernet интерфейс, например pnode04.
      exec { 'osdhddNameServer':
        command => "hostnamectl set-hostname ${osdhddNameServer}",
        unless  => "/usr/bin/test ${osdhddNameServer} = `/bin/cat /etc/hostname`",
      } ->

      # Создаём условия для мониторинга OSD на HDD.
      ceph::monitoring { 'osdhdd':
        typeosd => 'hdd',
      } ->

      Service['ceph-osd.target']

    }

    else {
      exec { 'osdhddDel':
       # Предполагаем, что имя класса устройств для идентификации устройств hdd osd и построения CRUSH правил - hdd. Имя устройств hdd это параметр.
        command =>  "/home/cephadm/cephdeploy/osdDel.sh hdd ${nameDisksOsdHddForScript}",
        # Запускаем скрипт удаления osd на HDD дисках только тогда, когда есть ceph physical volume на sd дисках. ram исключаем.
        onlyif  => '/sbin/pvs |grep ceph | grep sd | egrep -v ram',
        notify => Ceph::Healthcheck[osdhddCheckHealthOk],
      } ->

      Service['ceph-osd.target'] ->

      # Возможно, кроме удаления файлов, необходимо удалять и bootstrap ключи, которые можно посмотреть командой "ceph auth ls".
      # Пока, для простоты, не будем удалять bootstrap ключи.
      Exec['safelyDelBootstrapOsdCephKeyring'] ->

      Package['ceph-osd'] ->
#      Exec['safelyDelCephConf'] ->
      File[ '/etc/ceph/ceph.conf'] ->
      File['/etc/ceph/ceph.client.admin.keyring']
    }
    ###################################################################

    # Ресурсы манифеста osdhdd.pp используемые различными блоками кода манифеста osdhdd.pp

    # Проверка, что установка ceph прошла удачно. Выполняем exec-ом команду ceph health и ожидаем, что она вернёт "HEALTH_OK".
    ceph::healthcheck{'osdhddCheckHealthOk':}
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в значении параметра ensure или ensure = undef.
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure было одним из следующих [running, stopped, absent]")
  }
}
