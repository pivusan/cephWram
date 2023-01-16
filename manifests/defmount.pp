# = Define: defmount
#
# == Назначение
#
# Манифест для развёртывания ceph. Монтирование FS
#
# == Использование
#
# В виде define в составе модуля ceph.
#
# == Детали реализации
#
# Управление ресурсами посредством Puppet
#
# == Параметры
#
# [*ensure*]
#   Параметр отвечает за поддерживаемое состояние управляемых манифестом ресурсов.
#   Значение параметру присваивается при вызове define
#   Передаётся в виде строки.
#
# [*all_mon_ip_data*]
#   IP адреса интерфейса для передачи данных (обычно Infiniband) всех будующих MON-ов
#   Передаётся в виде Array IPv4 адресов, например ['10.10.165.30','10.10.165.24','10.10.165.67']
#   Передавать в виде Array нужно для того, чтоб иметь возможность изменить порядок следования этих IPv4 адресов в файле /etc/fstab. Одинаковый порядок следования Ipv4 адресов для разных монтируемых директорий заставляет Linux считать их одним устройством и не показывать все устройства в выдаче команды df. Что в свою очередь, вводит в заблуждение системного администратора.
#   Стандартное значение: Не существует
#
# [*cephfs_basedir*]
#   Начальная директория относительно которой монтируются pools ceph (например, hdd и ram)
#   Передаётся в виде строки
#   Стандартное значение: /var/cephfs
#
define ceph::defmount
(
  $ensure            = undef,
  $all_mon_ip_data   = $ceph::all_mon_ip_data,
  $cephfs_basedir    = $ceph::cephfs_basedir,
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
    # Параметр указывает, какую файловую систему - hdd или ram монтировать. Берётся из заголовка define при её вызове.
    # Возможные значения: hdd, ram.
    $type = "${title}"
    # Проверим имеет ли параметр $type допустимые значения:
    unless $type in [ 'hdd', 'ram' ] {
      # Если нет, то fail
      fail("Модуль ${module_name}. Параметр \$type=$type, но должен иметь значения 'hdd' или 'ram'.")
    }

    # В all_mon_ip_data_fstab формируется список IP адресов MON для добавления их в файл /etc/fstab.
    # Применение здесь функции shuffle обусловлено необходимостью менять порядок следования IP MON для различных монтируемых директорий в файле /etc/fstab. Иначе команда df покажет только одну точку монтирования вместо реально смонтированных нескольких. При применении функции shuffle, с некоторой долей вероятности, порядок следования IP адресов всё равно будет идентичным.
    $all_mon_ip_data_fstab_tmp = join( shuffle( $all_mon_ip_data ), ",")
    $all_mon_ip_data_fstab = "${all_mon_ip_data_fstab_tmp}:/"

    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    ####################  Ensure для разных типов  ####################
    $ensure_directory=$ensure ? {
    'running' => 'directory',
    'stopped' => 'directory',
    'absent'  => 'absent',
    }
    $ensure_object=$ensure ? {
      'running' => 'present',
      'stopped' => 'present',
      'absent'  => 'absent',
    }
    # Дополнительный новый $ensure для ресурса mount
    $ensure_mounted=$ensure ? {
    'running' => 'mounted',
    'stopped' => 'unmounted',
    'absent'  => 'absent',
    }
    ###################################################################

    #################  Последовательность применения  #################
    if $ensure in [ 'running', 'stopped' ] {
      # Получить файл /etc/ceph/ceph.conf из внешнего ресурса
      #File <<| tag == 'etc_ceph_conf' |>> ->
      # В новой реализации, взять файл /etc/ceph/ceph.conf из шаблона
      File[ '/etc/ceph/ceph.conf'] ->
      File["${cephfs_basedir}"] ->
      File["${cephfs_basedir}/${type}"] ->
      Exec['CreateOrDelCephfsKeyring'] ->
      Mount["${cephfs_basedir}/${type}"] ->
      Exec["defmountChModBasedir${cephfs_basedir}/${type}"]
    }
    if $ensure == 'absent' {
      Exec["defmountChModBasedir${cephfs_basedir}/${type}"] ->
      Mount["${cephfs_basedir}/${type}"] ->
      File["${cephfs_basedir}/${type}"] ->
      File["${cephfs_basedir}"] ->
      Exec['CreateOrDelCephfsKeyring'] ->
      #Exec['safelyDelCephConf']
      File[ '/etc/ceph/ceph.conf']
    }
    ###################################################################

    # Создание или удаление директории для монтирования файловой системы
    file {"${cephfs_basedir}/${type}":
      ensure => $ensure_directory,
      mode   => '0777',
      force  => true,
    }

    # Монтирование файловой системы
    # Добавить запись в fstab для всех MON-s перечисленных IP адресами и смонтировать cephfs
    mount {"${cephfs_basedir}/${type}":
      ensure  => $ensure_mounted,
      device  => $all_mon_ip_data_fstab,
      dump    => 0,
      fstype  => ceph,
      options => "name=admin,mds_namespace=${type}_fs,secretfile=/etc/ceph/cephfs.keyring,noatime,noauto,_netdev",
      pass    => 2,
    }

    # Поменять права на директорию ${cephfs_basedir}/${type}, так как она монтируется с правами не достаточными для записи не root пользователями
    exec { "defmountChModBasedir${cephfs_basedir}/${type}":
      command => "chmod 777 ${cephfs_basedir}/${type}",
      unless  => "stat -c%a ${cephfs_basedir}/${type} | grep 777",
    }

  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в значении параметра ensure или ensure = undef.
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure было одним из следующих [running, stopped, absent]")
  }
}
