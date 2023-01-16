# = Class: shareresources
#
# == Назначение
#
# Манифест для развёртывания ceph. Управляет ресурсами, необходимыми для развёртывания ceph, в зависимости от параметра $ensure у различных манифестов модуля ceph. В зависимости от параметра $ensure у манифестов включает в Каталог Puppet совместно используемый манифестами модуля ceph ресурс с теми или иными параметрами.
# Например, если хотя бы у одного манифеста, которому нужен пакет 'ceph-osd', параметр $ensure не равен 'absent', то пакет 'ceph-osd' будет включён в Каталог Puppet с параметром 'ensure' установленым в 'present'.
# Если же у всех манифестов, которым нужен пакет 'ceph-osd', параметр $ensure равен 'absent', то пакет 'ceph-osd' будет включён в Каталог Puppet с параметром 'ensure' установленым в 'absent'.
# Также реализовано и управление файлом /etc/ceph/ceph.conf и другими ресурсами описанными в этом манифесте.
#
# == Использование
#
# В виде класса в составе модуля ceph. Класс shareresources должен идти после всех классов модуля ceph в site.pp так как класс shareresources проверяет параметр $ensure у других классов, а значит эти классы должны быть уже в Каталоге Puppet.
#
# == Параметры
#
#
class ceph::shareresources
(
  $cephfs_basedir           = $ceph::cephfs_basedir,

  # Следующие параметры должны в этом манифесте быть указаны, так как здесь создается ресурс файл ceph.conf из erb шаблона, в котором используются эти параметры
  $fsid                     = $ceph::fsid,
  $all_mon_name_data        = $ceph::all_mon_name_data,
  $all_mon_ip_data          = $ceph::all_mon_ip_data,
  $public_network_data      = $ceph::public_network_data,
  $mask_public_network_data = $ceph::mask_public_network_data,
)
{

  # Если принято решение применять модуль ceph штатно, то $apply_ceph = true
  if ( $ceph::apply_ceph == true ) {
    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    ########################  Логика управления общими ресурсами манифестов  ###############

    # В связи с тем, что пакет ceph-osd должен устанавливаться и для OSD на HDD и для OSD на RAM (которые определены в разных классах) впрямую в этих манифестах указывать что пакет ceph-osd должен быть установлен нельзя, приводит к ошибке дублирования описания ресурса
    # Если хотя бы у одного манифеста, которому нужен этот пакет параметр $ensure равен 'running' или 'stopped', то установить пакет
    if ( $ceph::osdhdd::ensure in [ 'running', 'stopped' ] ) or
       ( $ceph::osdram::ensure in [ 'running', 'stopped' ] ) {
      package { 'ceph-osd': ensure => 'present'}
    }
    # Если не так, то удалить пакет
    elsif ( $ceph::osdhdd::ensure == 'absent' ) or
          ( $ceph::osdram::ensure == 'absent' ) {
      package { 'ceph-osd':  ensure => 'absent' }
    }

    # В связи с тем, что сервис ceph-osd.target должен быть запущен и для OSD на HDD и для OSD на RAM (которые определены в разных классах), впрямую в этих манифестах указывать этот сервис нельзя, приводит к ошибке дублирования описания ресурса service.
    # После того, как OSD установлен, активировать и запустить ceph-osd.target, если хотя бы у одного манифеста, которому нужен этот сервис параметр $ensure равен 'running'
    if ( $ceph::osdhdd::ensure == 'running' ) or
       ( $ceph::osdram::ensure == 'running' )  {
      service { 'ceph-osd.target':
        ensure => 'running',
        enable => true,
      }
    }
    # Если не так, то остановить сервис
    elsif ( $ceph::osdhdd::ensure in [ 'stopped', 'absent' ] ) or
          ( $ceph::osdram::ensure in [ 'stopped', 'absent' ] ) {
      service { 'ceph-osd.target':
        ensure => 'stopped',
        enable => 'false',
      }
    }

    # Не удалять файл  /var/lib/ceph/bootstrap-osd/ceph.keyring если хотя бы у одного манифеста, которому нужен этот файл параметр $ensure равен 'running' или 'stopped'.
    # Если не так, то удалить файл
    if ( $ceph::osdhdd::ensure in [ 'running', 'stopped' ] ) or
       ( $ceph::osdram::ensure in [ 'running', 'stopped' ] ) {
      exec { 'safelyDelBootstrapOsdCephKeyring':
        command => 'echo "Файл /var/lib/ceph/bootstrap-osd/ceph.keyring нужен одному или нескольким манифестам и его, поэтому, нельзя удалять."',
        onlyif  => '/usr/bin/test -f /var/lib/ceph/bootstrap-osd/ceph.keyring',
      }
    }
    elsif ( $ceph::osdhdd::ensure == 'absent' ) or
          ( $ceph::osdram::ensure == 'absent' ) {
      exec { 'safelyDelBootstrapOsdCephKeyring':
        command => '/bin/rm /var/lib/ceph/bootstrap-osd/ceph.keyring',
        onlyif  => '/usr/bin/test -f /var/lib/ceph/bootstrap-osd/ceph.keyring',
      }
    }

    # В связи с тем, что сервис ceph.target должен быть запущен и для MON и для MDS и для OSD (которые определены в разных классах) впрямую в этих манифестах указывать этот сервис нельзя, приводит к ошибке дублирования описания ресурса service.
    # После того, как MON и MGR и OSD установлены, активировать и запустить ceph.target, если хотя бы у одного манифеста, которому нужен этот сервис параметр $ensure равен 'running'
    if ( $ceph::mon::ensure    == 'running' ) or
       ( $ceph::mds::ensure    == 'running' ) or
       ( $ceph::osdhdd::ensure == 'running' ) or
       ( $ceph::osdram::ensure == 'running' ) {
      service { 'ceph.target':
        ensure => 'running',
        enable => true,
      }
    }
    # Если не так, то остановить сервис
    elsif ( $ceph::mon::ensure    in [ 'stopped', 'absent' ] ) or
          ( $ceph::mds::ensure    in [ 'stopped', 'absent' ] ) or
          ( $ceph::osdhdd::ensure in [ 'stopped', 'absent' ] ) or
          ( $ceph::osdram::ensure in [ 'stopped', 'absent' ] ) {
      service { 'ceph.target':
        ensure => 'stopped',
        enable => 'false',
      }
    }

    # Создать ключ администратора ceph, если хотя бы у одного манифеста, которому нужен этот файл параметр $ensure равен 'running' или 'stopped'.
    if ( $ceph::mon::ensure    in [ 'running', 'stopped' ] ) or
       ( $ceph::mds::ensure    in [ 'running', 'stopped' ] ) or
       ( $ceph::osdhdd::ensure in [ 'running', 'stopped' ] ) or
       ( $ceph::osdram::ensure in [ 'running', 'stopped' ] ) or
       ( $ceph::cli::ensure    in [ 'running', 'stopped' ] ) {
      file { '/etc/ceph/ceph.client.admin.keyring':
        ensure  => 'present',
        mode    => '0600',
        content => file('ceph/ceph_client_admin_keyring'),
      }
    }
    # Если не так, то удалить файл
    elsif ( $ceph::mon::ensure    == 'absent' ) or
          ( $ceph::mds::ensure    == 'absent' ) or
          ( $ceph::osdhdd::ensure == 'absent' ) or
          ( $ceph::osdram::ensure == 'absent' ) or
          ( $ceph::cli::ensure    == 'absent' ) {
      file { '/etc/ceph/ceph.client.admin.keyring':
        ensure  => 'absent',
      }
    }

    # Создать файл /etc/ceph/ceph.conf если хотя бы у одного манифеста, которому нужен этот файл параметр $ensure равен 'running' или 'stopped'.
    if ( $ceph::mon::ensure       in [ 'running', 'stopped' ] ) or
       ( $ceph::mds::ensure       in [ 'running', 'stopped' ] ) or
       ( $ceph::osdhdd::ensure    in [ 'running', 'stopped' ] ) or
       ( $ceph::osdram::ensure    in [ 'running', 'stopped' ] ) or
       ( $ceph::mount::ensure_hdd in [ 'running', 'stopped' ] ) or
       ( $ceph::mount::ensure_ram in [ 'running', 'stopped' ] ) or
       ( $ceph::cli::ensure       in [ 'running', 'stopped' ] ) {
      file { '/etc/ceph/ceph.conf':
        ensure  => 'present',
        mode    => '0644',
        content => template('ceph/etc_ceph_conf.erb'),
      }
#      exec { 'safelyDelCephConf':
#        command => 'echo "Файл /etc/ceph/ceph.conf нужен одному или нескольким манифестам и его, поэтому, нельзя удалять."',
#        onlyif  => '/usr/bin/test -f /etc/ceph/ceph.conf',
#      }
    }
    # Если не так, то удалить файл
    elsif ( $ceph::mon::ensure       == 'absent' ) or
          ( $ceph::mds::ensure       == 'absent' ) or
          ( $ceph::osdhdd::ensure    == 'absent' ) or
          ( $ceph::osdram::ensure    == 'absent' ) or
          ( $ceph::mount::ensure_hdd == 'absent' ) or
          ( $ceph::mount::ensure_ram == 'absent' ) or
          ( $ceph::cli::ensure       == 'absent' ) {
      file { '/etc/ceph/ceph.conf':
        ensure  => 'absent',
      }
#      exec { 'safelyDelCephConf':
#        command => '/bin/rm /etc/ceph/ceph.conf',
#        onlyif  => '/usr/bin/test -f /etc/ceph/ceph.conf',
#      }
    }

    # Создать директорию для монтирования файловых систем CephFS если хотя бы у одного манифеста, которому нужна эта директория параметр $ensure равен 'running' или 'stopped'.
    if ( $ceph::mount::ensure_hdd in [ 'running', 'stopped' ] ) or
       ( $ceph::mount::ensure_ram in [ 'running', 'stopped' ] ) {
      file { "${cephfs_basedir}":
        ensure => 'directory',
        mode   => '0777',
      }
    }
    # Если не так, то удалить директорию
    elsif ( $ceph::mount::ensure_hdd == 'absent' ) or
          ( $ceph::mount::ensure_ram == 'absent' ) {
      file { "${cephfs_basedir}":
        ensure => 'absent',
        force  => true,
      }
    }

    # Создать файл  /etc/ceph/cephfs.keyring если хотя бы у одного манифеста, которому нужен этот файл параметр $ensure равен 'running' или 'stopped'.
    if ( $ceph::mount::ensure_hdd in [ 'running', 'stopped' ] ) or
       ( $ceph::mount::ensure_ram in [ 'running', 'stopped' ] ) {
      exec { 'CreateOrDelCephfsKeyring':
        command => 'ceph auth get-or-create-key client.admin -o /etc/ceph/cephfs.keyring',
        creates => '/etc/ceph/cephfs.keyring',
      }
    }
    # Если не так, то удалить файл
    # Возможно, кроме удаления файла, необходимо удалять и ключи, которые можно посмотреть командой "ceph auth ls". Пока, для простоты не будем удалять.
    elsif ( $ceph::mount::ensure_hdd == 'absent' ) or
          ( $ceph::mount::ensure_ram == 'absent' ) {
      exec { 'CreateOrDelCephfsKeyring':
        command => '/bin/rm /etc/ceph/cephfs.keyring',
        onlyif  => '/usr/bin/test -f /etc/ceph/cephfs.keyring',
      }
    }
    ########################################################################################
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true")
  }
}
