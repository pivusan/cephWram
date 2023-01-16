# = Class: mds
#
# == Назначение
#
# Манифест для развёртывания ceph. Развёртывание MDS.
#
# == Использование
#
# В виде класса в составе модуля ceph.
# Необходимо минимум к трём серверам применить манифест mds.pp.
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
class ceph::mds
(
  $ensure = undef,
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
    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    # Пропишем зависимости между классами
    # Текущий класс требуется применить после класса 'ceph::system'
    require ceph::system

    # Необходимо сохранить текущее имя сервера, оно должно указывать на IP адрес Ethernet интерфейса сервера
    # Пример: имя сервера - pnode04, IP - 192.168.166.44
    $mdsNameServer = $facts['hostname']
    # Тогда имя сервера указывающего на интерфейс Infiniband, необходимый для установки ceph, будет pnode04ib
    $mdsNameServerIB = "${mdsNameServer}ib"

    ####################  Ensure для разных типов  ####################
    $ensure_running=$ensure ? {
      'running' => 'running',
      'stopped' => 'stopped',
      'absent'  => 'stopped',
    }
    $ensure_object=$ensure ? {
      'running' => 'present',
      'stopped' => 'present',
      'absent'  => 'absent',
    }
    $ensure_directory=$ensure ? {
      'running' => 'directory',
      'stopped' => 'directory',
      'absent'  => 'absent',
    }
    $ensure_enable=$ensure ? {
      'running' => true,
      'stopped' => false,
      'absent'  => false,
    }
    ###################################################################


    #################  Последовательность применения  #################
    if $ensure != 'absent' {
      # Если коллектор найдёт пакет ceph-mon, значит класс 'ceph::mon' есть, тогда текущий класс следует применить после класса 'ceph::mon'.
      # Это особенно нужно, когда устанавливается первый MON
      Package <| name == 'ceph-mon' |> ->
      Package['ceph-mds'] ->
      # Получить файл /etc/ceph/ceph.conf из внешнего ресурса
      #File <<| tag == 'etc_ceph_conf' |>> ->
      # В новой реализации, взять файл /etc/ceph/ceph.conf из шаблона
      File[ '/etc/ceph/ceph.conf'] ->
      File['/etc/ceph/ceph.client.admin.keyring'] ->

      # Поменять имя хоста на имя по которому резолвится Infiniband интерфейс сервера (например на pnode01ib)
      exec { 'mdsNameServerIB':
        command => "hostnamectl set-hostname ${mdsNameServerIB}",
        unless  => "/usr/bin/test ${mdsNameServerIB} = `/bin/cat /etc/hostname`",
      } ->

      # Создать bootstrap ключ 
      exec { 'mdsBootstrapKeyAdd':
        command => 'ceph auth get client.bootstrap-mds -o /var/lib/ceph/bootstrap-mds/ceph.keyring',
        creates => '/var/lib/ceph/bootstrap-mds/ceph.keyring',
      } ->

      File["/var/lib/ceph/mds/ceph-${mdsNameServerIB}"] ->

      # Создать связку ключей. Create a keyring for your cluster
      exec { 'mdsKeyringAdd':
      #      command =>  "ceph-authtool --create-keyring /var/lib/ceph/mds/ceph-${mdsNameServerIB}/keyring --gen-key -n mds.${mdsNameServerIB}",
        command =>  "ceph auth get-or-create mds.${mdsNameServerIB} mds 'allow' osd 'allow *' mon 'allow profile mds' > /var/lib/ceph/mds/ceph-${mdsNameServerIB}/keyring",
        creates => "/var/lib/ceph/mds/ceph-${mdsNameServerIB}/keyring",
      } ->

      File["/var/lib/ceph/mds/ceph-${mdsNameServerIB}/keyring"] ->

      # Вернуть имя хоста серверу по которому резолвится Ethernet интерфейс, например pnode04
      exec { 'mdsNameServer':
        command => "hostnamectl set-hostname ${mdsNameServer}",
        unless  => "/usr/bin/test ${mdsNameServer} = `/bin/cat /etc/hostname`",
      } ->

      # Создаём условия для мониторинга MDS.
      ceph::monitoring{'mds':} ->

      # Запустим сервис mds. Только если он запускается, выполним проверку "HEALTH_OK".
      Service["ceph-mds@${mdsNameServerIB}"]
      #Service['ceph.target'] ->

    }

    else {
      #Service['ceph.target'] ->
      Service["ceph-mds@${mdsNameServerIB}"] ->
      File["/var/lib/ceph/mds/ceph-${mdsNameServerIB}/keyring"] ->
      File["/var/lib/ceph/mds/ceph-${mdsNameServerIB}"] ->

      # Возможно, кроме удаления файлов, необходимо удалять и ключи, которые можно посмотреть командой "ceph auth ls".
      # Пока, для простоты, не будем удалять ключи. Удалим пока только то, что точно нужно удалять и не будем удалять остальное.
      exec { 'mdsBootstrapKeyDel':
        command => '/bin/rm /var/lib/ceph/bootstrap-mds/ceph.keyring',
        onlyif  => '/usr/bin/test -f /var/lib/ceph/bootstrap-mds/ceph.keyring',
      } ->

      Package['ceph-mds'] ->
      #Exec['safelyDelCephConf'] ->
      File[ '/etc/ceph/ceph.conf'] ->
      File['/etc/ceph/ceph.client.admin.keyring']
    }
    ###################################################################

    # Ресурсы, используемые различными блоками кода этого манифеста

    # Установить компоненты ceph MDS
    package { 'ceph-mds':
      ensure  => $ensure_object,
    }

    # Create a default data directory (or directories)
    # Создать директорию, если она отсутствует
    file { "/var/lib/ceph/mds/ceph-${mdsNameServerIB}":
      ensure => $ensure_directory,
      group  => 'ceph',
      owner  => 'ceph',
      mode   => '0755',
      force  => true,
    }

    # Отконфигурировать и запустить службу MDS
    service { "ceph-mds@${mdsNameServerIB}":
      ensure => $ensure_running,
      enable => $ensure_enable,
      notify => Ceph::Healthcheck[mdsCheckHealthOk],
    }

    # Поменять права файлу
    file { "/var/lib/ceph/mds/ceph-${mdsNameServerIB}/keyring":
      ensure => $ensure_object,
      group  => 'ceph',
      owner  => 'ceph',
      mode   => '0600',
    }

    # Проверка, что установка ceph прошла удачно. Выполняем exec-ом команду ceph health и ожидаем, что она вернёт "HEALTH_OK".
    ceph::healthcheck{'mdsCheckHealthOk':}
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в значении параметра ensure или ensure = undef.
    notice('Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: $ceph::apply_ceph - [true], $ensure - [running, stopped, absent]')
  }
}
