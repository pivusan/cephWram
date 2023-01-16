# = Class: system
#
# == Назначение
#
# Манифест для развёртывания ceph. Системная часть настроек сервера. Подготовка к развёртыванию ceph.
#
# == Использование
#
# В виде класса в составе модуля ceph.
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
# [*uid_cephadm, gid_cephadm*]
#   UID и GID пользователя cephadm
#   Передаётся в виде целого числа
#   Стандартное значение: 2100
#
# [*uid_ceph, gid_ceph*]
#   UID и GID пользователя ceph
#   Передаётся в виде целого числа
#   Стандартное значение: 64045
#
# [*osd_ram_size*]
#   Объём Ram диска в килобайтах. Нужно выбирать в зависимости от требований различного ПО работающего на сервере и доступной RAM памяти сервера.
#   Параметры osdramWeight и osd_ram_size  связаны - Weight диска примерно равен объёму этого диска, выраженному в ТБ.
#   Возможные значения: 268435456 (256 ГБ), 2097152 (2 ГБ), 314572800 (300 ГБ).
#   Передаётся в виде целого числа.
#   Стандартное значение: "268435456" (256 ГБ)

class ceph::system (
  $ensure         = 'running',

  $uid_cephadm    = $ceph::uid_cephadm,
  $gid_cephadm    = $ceph::gid_cephadm,

  $uid_ceph       = $ceph::uid_ceph,
  $gid_ceph       = $ceph::gid_ceph,

  $osd_ram_size   = $ceph::osd_ram_size,

  # Для передачи параметров через файл.
  $cephfs_basedir = $ceph::cephfs_basedir,
  $osdramWeight   = $ceph::osdramWeight,
  $k              = $ceph::k,
  $m              = $ceph::m,
  $max_mds_fss    = $ceph::max_mds_fss,
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
    Exec { path   => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    ####################  Ensure для разных типов  ####################
    $ensure_running=$ensure ? {
      'running'   => 'running',
      'stopped'   => 'stopped',
      'absent'    => 'stopped',
    }
    $ensure_object=$ensure ? {
      'running'   => 'present',
      'stopped'   => 'present',
      'absent'    => 'absent',
    }
    $ensure_directory=$ensure ? {
      'running'   => 'directory',
      'stopped'   => 'directory',
      'absent'    => 'absent',
    }
    ###################################################################

    # Группа для пользователя cephadm. Необходим для работы с ceph кластером.
    group { 'cephadm':
      ensure      => $ensure_object,
      gid         => "${gid_cephadm}",
    } -> # Ещё один способ выставить зависимости в манифесте

    # Пользователь cephadm. Необходим для работы с ceph кластером.
    user { 'cephadm':
      ensure      => $ensure_object,
      gid         => "${gid_cephadm}",
      uid         => "${uid_cephadm}",
      home        => '/home/cephadm',
      managehome  =>  true,
      comment     => 'User for ceph',
      groups      => ['dip', 'plugdev', 'netdev', 'astra-console', 'astra-admin'],
      password    => '$6$96XucOBh$Ll7PA1CNnbtx8TwmkXDrjVbNiW3ZrMm0wnvXAQdz5ZyIC8AHGeyJY2rRHnsRfZ6KyvaZj8Z.aBkCncCdxYbdh/',
      shell       => '/bin/bash',
    } ->

    # Специальная директория для хранения файлов необходимых для развёртывания ceph кластера
    file { '/home/cephadm/cephdeploy':
      ensure      => $ensure_directory,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0755',
    } ->

    # Специальная директория для хранения конфигурационных файлов необходимых для развёртывания ceph кластера и его эксплуатации
    file { '/home/cephadm/cephdeploy/conf':
      ensure      => $ensure_directory,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0755',
    } ->

    # Передача в скрипты включения-выключения ceph, параметров через файл.
    file { '/home/cephadm/cephdeploy/conf/ceph.env':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
    } ->
    file_line { 'description.ceph.env':
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => "# Этот файл был создан puppet модулем ceph",
    } ->
    file_line { 'CEPH_ARGS.ceph.env':
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => 'export CEPH_ARGS=" --name client.cephadm --keyring=/etc/ceph/ceph.client.cephadm.keyring"',
    } ->
    file_line { 'PATH.ceph.env':
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"',
    } ->
    file_line { "cephfs_basedir.ceph.env":
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => "cephfs_basedir=${cephfs_basedir}",
    } ->
    file_line { 'osdramWeight.ceph.env':
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => "osdramWeight=${osdramWeight}",
    } ->
    file_line { "k.ceph.env":
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => "k=${k}",
    } ->
    file_line { "m.ceph.env":
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => "m=${m}",
    } ->
    file_line { "max_mds_fss.ceph.env":
      ensure      => $ensure_object,
      path        => '/home/cephadm/cephdeploy/conf/ceph.env',
      line        => "max_mds_fss=${max_mds_fss}",
    } ->
    File_line <<| tag == 'ceph.env' |>>
    ->

    # Файл, используемый модулем ceph
    file { '/home/cephadm/cephdeploy/osdDel.sh':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
      content     => file('ceph/osdDel.sh'),
    } ->

    # Файлы, используемые для запуска и остановки ceph
    file { '/home/cephadm/cephdeploy/ceph_pre_down.sh':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
      content     => file('ceph/ceph_pre_down.sh'),
    } ->
    file { '/home/cephadm/cephdeploy/ceph_up.sh':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
      content     => file('ceph/ceph_up.sh'),
    } ->
    file { '/home/cephadm/cephdeploy/functions.sh':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
      content     => file('ceph/functions.sh'),
    } ->

    # Файлы, используемые для сервисных нужд
    file { '/home/cephadm/cephdeploy/runcmd.sh':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
      content     => file('ceph/runcmd.sh'),
    } ->

    file { '/home/cephadm/cephdeploy/pcp.sh':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
      content     => file('ceph/pcp.sh'),
    } ->

    file { '/home/cephadm/cephdeploy/cprootfile.sh':
      ensure      => $ensure_object,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
      content     => file('ceph/cprootfile.sh'),
    } ->

    # Беспарольный sudo для пользователя cephadm
    file { '/etc/sudoers.d/cephadm':
      ensure      => $ensure_object,
      mode        => '0440',
      content     => "cephadm ALL = (root) NOPASSWD:ALL\n",
    } ->

    # Доступ по ключу для пользователя cephadm на сервера кластера ceph
    file { '/home/cephadm/.ssh/':
      ensure      => $ensure_directory,
      group       => 'cephadm',
      owner       => 'cephadm',
      mode        => '0700',
    } ->
    file { '/home/cephadm/.ssh/authorized_keys':
      ensure      =>  $ensure_object,
      mode        => '0600',
      group       => 'cephadm',
      owner       => 'cephadm',
      content     => file("ceph/authorized_keys"),
    } ->
    file { '/home/cephadm/.ssh/id_rsa':
      ensure      =>  $ensure_object,
      mode        => '0600',
      group       => 'cephadm',
      owner       => 'cephadm',
      content     => file("ceph/id_rsa"),
    } ->
    file { '/home/cephadm/.ssh/id_rsa.pub':
      ensure      =>  $ensure_object,
      mode        => '0644',
      group       => 'cephadm',
      owner       => 'cephadm',
      content     => file("ceph/id_rsa.pub"),
    } ->
    file { '/home/cephadm/.ssh/config':
      ensure      =>  $ensure_object,
      mode        => '0644',
      group       => 'cephadm',
      owner       => 'cephadm',
      content     => file("ceph/config"),
    } ->

    # Добавить или удалить в профайл cephadm переменную CEPH_ARGS. Создание прав доступа для пользователя cephadm к кластеру ceph.
    file_line { 'CEPH_ARGS.profile':
      ensure      => $ensure_object,
      path        => '/home/cephadm/.profile',
      line        => 'export CEPH_ARGS=" --name client.cephadm --keyring=/etc/ceph/ceph.client.cephadm.keyring"',
    } ->
    # Добавить или удалить в профайл cephadm переменную PATH
    file_line { 'PATH.profile':
      ensure      => $ensure_object,
      path        => '/home/cephadm/.profile',
      line        => 'PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"',
    } ->
    # Добавить или удалить в профайл cephadm переход в служебную директорию
    file_line { 'CD.profile':
      ensure      => $ensure_object,
      path        => '/home/cephadm/.profile',
      line        => 'cd /home/cephadm/cephdeploy',
    } ->

    # Установить максимальный уровень целостности пользователям cephadm и root
    case $ensure {
      'running','stopped': {
        #exec { '/usr/sbin/pdpl-user -i 127 cephadm':
        exec { '/usr/sbin/pdpl-user -i 63  cephadm':
          unless => "grep 'cephadm:3f' /etc/parsec/micdb/${uid_cephadm}",
        } ->
        exec { '/usr/sbin/pdpl-user -i 63 root':
          unless => "grep 'root:3f' /etc/parsec/micdb/0",
        }
      }
      'absent': {
        exec { '/usr/sbin/pdpl-user -d cephadm':
          onlyif => "/usr/bin/test -f /etc/parsec/micdb/${uid_cephadm}",
        }
        exec { '/usr/sbin/pdpl-user -d root':
          onlyif => '/usr/bin/test -f /etc/parsec/micdb/0',
        }
      }
    }

    # Группа пользователя ceph
    group { 'ceph':
      ensure      => $ensure_object,
      gid         => "${gid_ceph}",
    } ->

    # Пользователь ceph. От его имени работает ceph
    user { 'ceph':
      ensure      => $ensure_object,
      gid         => "${gid_ceph}",
      uid         => "${uid_ceph}",
      home        => '/var/lib/ceph',
      managehome  =>  true,
      comment     => 'Ceph storage service',
      password    => '!*',
      shell       => '/bin/false',
    } ->

    # Сменить права на домашнюю директорию пользователя ceph. Права по умолчанию не подходят
    file { '/var/lib/ceph':
      ensure      => $ensure_directory,
      mode        => '0750',
    } ->

    # Удалить файлы которые создаются в домашней директории пользователя ceph. Пользователю ceph они не нужны
    file { ['/var/lib/ceph/Desktop', '/var/lib/ceph/.bash_logout', '/var/lib/ceph/.bashrc', '/var/lib/ceph/.profile']:
      ensure      => 'absent',
      force       => true,
    }

/*  Удалим управление службой NetworkManager из модуля ceph
    # Когда $ensure принимает значение absent, удалять системные файлы нельзя, поэтому организуем конструкцию case
    case $ensure {
      'running','stopped': {
        # Отключить службу NetworkManager. На всякий случай, чтоб не мешал настраивать сеть.
        service { 'NetworkManager':
          ensure  => 'stopped',
          enable  => 'mask',
        }
      }
      'absent': {
        # До установки ceph служба NetworkManager была включена, значит включаем её здесь
        service { 'NetworkManager':
          ensure  => 'running',
          enable  => true,
        }
      }
    }
*/

    # Утилита jq необходима для обработки информации в формате JSON, получаемой от утилит ceph
    package { 'jq':
      ensure      => $ensure_object,
    }

    # rsync необходим для копирование файлов между срверами и работы утилиты копирования файлов с правами root
    package { 'rsync':
      ensure      => $ensure_object,
    }

    # Настроить ОС так, чтобы RAM диск для osd на RAM создавался на этапе загрузки ОС
    file { '/etc/modules-load.d/cephbrd.conf':
      ensure      => $ensure_object,
      mode        => '0440',
      content     => 'brd',
    } ->
    file { '/etc/modprobe.d/cephbrd.conf':
      ensure      => $ensure_object,
      mode        => '0440',
      content     => "options brd rd_nr=1 rd_size=$osd_ram_size max_part=0",
      notify      => Service['systemd-modules-load'],
    }
    service { 'systemd-modules-load':
    }

    # Интегрируем скрипт подготовки к работе ceph в systemd
    file { '/etc/systemd/system/cephstartup.service':
      ensure      => $ensure_object,
      group       => 'root',
      owner       => 'root',
      mode        => '0644',
      content     => file('ceph/cephstartup.service'),
    } ~>
    exec { 'cephstartup-systemd-enabled':
      command     => 'systemctl enable cephstartup.service',
      refreshonly => true,
    } ~>
    exec { 'cephstartup-systemd-reload':
      command     => 'systemctl daemon-reload',
      refreshonly => true,
    }
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ensure = undef.
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure было одним из следующих [running, stopped, absent]")
  }
}
