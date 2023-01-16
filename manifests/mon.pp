# = Class: mon
#
# == Назначение
#
# Манифест для развёртывания ceph. Развёртывание MON и MGR. MGR устанавливается на том же сервере, где устанавливается MON.
# Если удаляется MON, то нужно удалять и MGR.
#
# == Использование
#
# В виде класса в составе модуля ceph. Необходимо минимум к трём серверам применить манифест mon.pp. Развёртывать более пяти MON, пока, смысла особого не вижу.
# При развёртывании MON нужно установить переменную $firstMON.
# Если переменная равна true, то развёртывается первый MON в кластере. Если переменная равна false, то развёртываются последующие MON.
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
# [*fsid*]
#   Идентификатор кластера ceph
#   Передаётся в виде сгенерерованного командой 'uuidgen -r' значения
#   Стандартное значение: Не существует
#
# [*first_mon*]
#   Параметр указывающий первый ли MON развёртывается.
#   Если переменная равна true, то развёртывается первый MON в кластере. Если переменная равна false, то развёртываются последующие MON.
#   Передаётся в виде булевого значения true или false.
#   Стандартное значение: false
#
# [*first_mon_ip_data*]
#   Можно сделать автоматически, но приняли решение с Будник Р.Н. Заполнять вручную, для надёжности
#   IP интерфейса для передачи данных (обычно Infiniband) первого MON.
#   Передаётся в виде IPv4, например 10.53.206.124
#   Стандартное значение: Не существует
#
#Удалить  [*all_mon_name_data*]
#   Имя сервера интерфейса для передачи данных (обычно Infiniband) только одного первого MON кластера ceph.
#   Передаётся в виде Array, например, ['pnode01ib']
#   Стандартное значение: Не существует
#
# [*public_network_data*]
#   Public network интерфейса для передачи данных (обычно Infiniband)
#   Передаётся в виде адреса сети, например 10.53.206.0
#   Стандартное значение: Не существует
#
# [*mask_public_network_data*]
#   Mask Public network интерфейса для передачи данных (обычно Infiniband)
#   Передаётся в виде десятичного числа маски сети IPv4 в CIDR представлении 
#   Стандартное значение: 24
#
class ceph::mon
(
  $ensure                   = undef,
  $first_mon                = $ceph::first_mon,
  $fsid                     = $ceph::fsid,
  $first_mon_ip_data        = $ceph::first_mon_ip_data,

  # Параметры all_mon_ip_data и $all_mon_name_data должны в этом манифесте быть указаны, так как здесь экспортируется файл ceph.conf, в котором используется эти параметры
# Теперь не экспортируется
#  $all_mon_name_data        = $ceph::all_mon_name_data,
#  $all_mon_ip_data          = $ceph::all_mon_ip_data,
#  $public_network_data      = $ceph::public_network_data,
#  $mask_public_network_data = $ceph::mask_public_network_data,
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
    $monNameServer = $facts['hostname']
    $mgrNameServer = $facts['hostname']

    # Тогда имя сервера указывающего на интерфейс Infiniband, необходимый для установки ceph, будет (pnodeXXib):
    $monNameServerIB = "${monNameServer}ib"
    $mgrNameServerIB = "${mgrNameServer}ib"

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

    # Если MON первый создаваемый в кластере, тогда выполнить код в блоке $first_mon=true
    # Если MON в кластере уже есть, тогда выполнить код в блоке "else"
    if $first_mon == true { # Если MON первый создаваемый в кластере
      # Экспортируемый конфигурационный файл /etc/ceph/ceph.conf, для использования на других узлах.
      # Теперь не используем экспорт, создаём из шаблона
#      @@file { '/etc/ceph/ceph.conf':
#        ensure  => $ensure_object,
#        tag     => 'etc_ceph_conf',
#        mode    => '0644',
#        content => template('ceph/etc_ceph_conf.erb'),
#      }

      #################  Последовательность применения  #################
      if $ensure != 'absent' { # Если MON первый в кластере и нужно установить  MON

        Package['ceph-mon'] ->

        # Поменять имя хоста на имя по которому резолвится Infiniband интерфейс сервера (pnodeXXib)
        exec { 'monNameServerIB':
          command => "hostnamectl set-hostname ${monNameServerIB}",
          unless  => "/usr/bin/test ${monNameServerIB} = `/bin/cat /etc/hostname`",
        } ->

#        File['/etc/ceph/ceph.conf.first_mon'] ->
#        # И скопировать файл /etc/ceph/ceph.conf.first_mon в /etc/ceph/ceph.conf так как никаким другим способом не удаётся создать локальный файл /etc/ceph/ceph.conf и одновременно создать экспортированный ресурс (файл) /etc/ceph/ceph.conf в puppetdb.
#        exec { '/bin/cp /etc/ceph/ceph.conf.first_mon /etc/ceph/ceph.conf':
#          creates => '/etc/ceph/ceph.conf',
#        } ->
        # В новой реализации, взять файл /etc/ceph/ceph.conf из шаблона
        File[ '/etc/ceph/ceph.conf'] ->

        File['/etc/ceph/ceph.client.admin.keyring'] ->

        # Создать связку ключей для первого и пока единственного в кластере MON
        # Create a keyring for your cluster and generate a monitor secret key.
        exec { 'FirstMonKey01':
          command =>  "ceph-authtool --create-keyring /tmp/ceph.mon.keyring --gen-key -n mon. --cap mon 'allow *'",
          creates => '/tmp/ceph.mon.keyring',
        } ->

        File['/tmp/ceph.mon.keyring'] ->

        # Add the client.admin key to the ceph.mon.keyring.
        exec { 'FirstMonKey03':
          command => 'ceph-authtool /tmp/ceph.mon.keyring --import-keyring /etc/ceph/ceph.client.admin.keyring',
          unless  => 'grep client.admin /tmp/ceph.mon.keyring 2>/dev/null',
        } ->

        # Generate a monitor map using the hostname(s), host IP address(es) and the FSID. Save it as /tmp/monmap:
        exec { 'FirstMonKey04':
          command => "monmaptool --create --add ${monNameServerIB} ${first_mon_ip_data} --fsid ${fsid} /tmp/monmap",
          creates => '/tmp/monmap',
        } ->

        File["/var/lib/ceph/mon/ceph-${monNameServerIB}"] ->

        # Populate the monitor daemon(s) with the monitor map and keyring.
        exec { 'FirstMonKey05':
          command => "sudo -u ceph ceph-mon --mkfs -i ${monNameServerIB} --monmap /tmp/monmap --keyring /tmp/ceph.mon.keyring",
          creates => "/var/lib/ceph/mon/ceph-${monNameServerIB}/keyring",
        } ->

        File["/var/lib/ceph/mon/ceph-${monNameServerIB}/done"] ->
        Service["ceph-mon@${monNameServerIB}"] ->
        File["/var/lib/ceph/mon/ceph-${monNameServerIB}/systemd"] ->

        # Создать bootstrap ключи для bootstrap-mds bootstrap-osd bootstrap-rbd bootstrap-rgw
        # Файлы /var/lib/ceph/bootstrap-mon/ceph.keyring и /var/lib/ceph/bootstrap-mgr/ceph.keyring не создаются
        exec { 'FirstMonKey06':
          command => "ceph-create-keys --id ${monNameServerIB}",
          creates => '/var/lib/ceph/bootstrap-osd/ceph.keyring', # А также другие bootstrap ключи
        } ->

        # Расположенный именно в этом месте "вызов" "функции" создаёт условия для мониторинга интегральных параметров кластера ceph (например, health_ok). И экспорта их на Сервер управления. Если сервер, являющийся first_mon выйдет из строя, интегральные параметры кластера ceph не будут мониториться.
        ceph::monitoring{'integral':} ->

        # Расположенный именно в этом месте "вызов" "функции" создаёт условия для мониторинга MON на первом MON.
        ceph::monitoring{'mon':} ->

        # Здесь создаётся только зависимость для правильной последовательности выполнения манифеста. Здесь должна быть ссылка на первый ресурс установки mgr
        Package['ceph-mgr']

    } # end Если MON первый в кластере и нужно установить  MON

      else {  # Если MON первый в кластере и нужно удалить MON

        Service["ceph-mon@${monNameServerIB}"] ->

        # Удаляем MON из кластера ceph
        exec { 'monRemoveFirstMon':
          command =>  "ceph mon remove ${monNameServerIB}",
          onlyif  =>  "sleep 5 && ceph health detail|grep ${monNameServerIB}|grep '(out of quorum)'",
        } ->

        Package['ceph-mon'] ->
        #DC      File["/var/lib/ceph/mon/ceph-${monNameServerIB}/keyring"] ->
        #DC      File["/var/lib/ceph/mon/ceph-${monNameServerIB}/done"] ->
        File["/var/lib/ceph/mon/ceph-${monNameServerIB}/systemd"] ->
        File["/var/lib/ceph/mon/ceph-${monNameServerIB}"] ->
        File['/tmp/ceph.mon.keyring'] ->

        exec { '/bin/rm /tmp/monmap':
          onlyif  => '/usr/bin/test -f /tmp/monmap',
        } ->

#        File['/etc/ceph/ceph.conf.first_mon'] ->
        # В новой реализации, взять файл /etc/ceph/ceph.conf из шаблона
        File[ '/etc/ceph/ceph.conf'] ->

        # Здесь создаётся только зависимость для правильной последовательности выполнения манифеста. Здесь должна быть ссылка на ресурс удаления mgr
        Service['ceph.target']

      }# end Если MON первый в кластере и нужно удалить MON
      ###################################################################

      # Ресурсы манифеста mon.pp используемые только блоком кода манифеста mon.pp, когда first_mon = true:

      # Создать или удалить промежуточный файл для /etc/ceph/ceph.conf для использования на первом MON
#      file { '/etc/ceph/ceph.conf.first_mon':
#        ensure  => $ensure_object,
#        mode    => '0644',
#        content => template('ceph/etc_ceph_conf.erb'),
#      }

      # Поменять права файлу /tmp/ceph.mon.keyring, а то у него после создания доступ только root. Или удалить файл, в зависимости от $ensure
      file { '/tmp/ceph.mon.keyring':
        ensure => $ensure_object,
        mode   => '0644',
      }

      # Файл systemd нужно создавать только если сервис ceph-mon@$monNameServerIB успешно запустился
      # In this case, to allow the start of the daemon at each reboot you must create empty files like this:
      file { "/var/lib/ceph/mon/ceph-${monNameServerIB}/systemd":
        ensure => $ensure_object,
        group  => 'ceph',
        owner  => 'ceph',
        mode   => '0644',
      }

      # Файл done нужно создавать только если команда "ceph ceph-mon --mkfs" выполнилась успешно
      # Mark that the monitor is created and ready to be started:
      file { "/var/lib/ceph/mon/ceph-${monNameServerIB}/done":
        ensure => $ensure_object,
        group  => 'ceph',
        owner  => 'ceph',
        mode   => '0644',
      }

    } # end # Если MON первый создаваемый в кластере
    else {# Если устанавливаемый MON не первый. В кластере уже есть другой MON

      # Ресурсы манифеста mon.pp используемые только когда first_mon = false

      # Создать или удалить директорию
      file { '/tmp/ceph':
        ensure  => $ensure_directory,
        force  => true,
      }

      #################  Последовательность применения  #################
      if $ensure != 'absent' { # Если MON НЕ первый в кластере и нужно установить MON

        Package['ceph-mon'] ->

        # Поменять имя хоста на имя по которому резолвится Infiniband интерфейс сервера (pnodeXXib)
        exec { 'monNameServerIB':
          command => "hostnamectl set-hostname ${monNameServerIB}",
          unless  => "/usr/bin/test ${monNameServerIB} = `/bin/cat /etc/hostname`",
        } ->

        # Получить файл /etc/ceph/ceph.conf из внешнего ресурса
#        File <<| tag == 'etc_ceph_conf' |>> ->
        # В новой реализации, взять файл /etc/ceph/ceph.conf из шаблона
        File[ '/etc/ceph/ceph.conf'] ->

        File['/etc/ceph/ceph.client.admin.keyring'] ->
        File["/var/lib/ceph/mon/ceph-${monNameServerIB}"] ->
        File['/tmp/ceph'] ->

        # Получить связку ключей от созданного в кластере и уже работающего MON и создать MON на текущем сервере
        exec { 'NextMonKey01':
          command =>  'ceph auth get mon. -o /tmp/ceph/keyring',
          creates => '/tmp/ceph/keyring',
        } ->
        exec { 'NextMonKey02':
          command =>  'ceph mon getmap -o /tmp/ceph/map-filename',
          creates => '/tmp/ceph/map-filename',
        } ->

        # Здесь создаётся сам MON и его fs,
        exec { 'NextMonKey03':
          command => "sudo -u ceph ceph-mon -i ${monNameServerIB} --mkfs --monmap /tmp/ceph/map-filename --keyring /tmp/ceph/keyring",
          creates => "/var/lib/ceph/mon/ceph-${monNameServerIB}/keyring",
        } ->

        Service["ceph-mon@${monNameServerIB}"] ->

        # Расположенный именно в этом месте "вызов" "функции" создаёт условия для мониторинга второго и последующих MON.
        ceph::monitoring{'mon':} ->

        # Здесь создаётся только зависимость для правильной последовательности выполнения манифеста. Здесь должна быть ссылка на ресурс установки mgr
        Package['ceph-mgr']

      } # end Если MON НЕ первый в кластере и нужно установить MON
      else {  # Если MON НЕ первый в кластере и нужно удалить MON
        Service["ceph-mon@${monNameServerIB}"] ->

        # Удаляем MON из кластера ceph
        exec { 'monRemoveNextMon':
          command =>  "ceph mon remove ${monNameServerIB}",
          onlyif  =>  "sleep 5 && ceph health detail|grep ${monNameServerIB}|grep '(out of quorum)'",
        } ->

        Package['ceph-mon'] ->
        File["/var/lib/ceph/mon/ceph-${monNameServerIB}/keyring"] ->
        #File["/var/lib/ceph/mon/ceph-${monNameServerIB}/done"] ->
        #File["/var/lib/ceph/mon/ceph-${monNameServerIB}/systemd"] ->
        File["/var/lib/ceph/mon/ceph-${monNameServerIB}"] ->

        exec { '/bin/rm /tmp/ceph/keyring':
          onlyif  => '/usr/bin/test -f /tmp/ceph/keyring',
        } ->
        exec { '/bin/rm /tmp/ceph/map-filename':
          onlyif  => '/usr/bin/test -f /tmp/ceph/map-filename',
        } ->

        File['/tmp/ceph'] ->

        # Здесь создаётся только зависимость для правильной последовательности выполнения манифеста. Здесь должна быть ссылка на ресурс удаления mgr
        Service['ceph.target']

      }# end Если MON НЕ первый в кластере и нужно удалить MON
      ###################################################################

    } # end # Если устанавливаемый MON не первый. В кластере уже есть другой MON



    # MGR должен устанавливаться и настраивается на том же сервере, где есть MON.

    #################  Последовательность применения  #################
    if $ensure != 'absent' { # Установка MGR только после установки MON
      Package['ceph-mgr'] ->

      File["/var/lib/ceph/mgr/ceph-${mgrNameServerIB}"] ->

      # First, create an authentication key for your daemon:
      exec { 'MgrKey01':
        command =>  "ceph auth get-or-create mgr.${mgrNameServerIB} mon 'allow profile mgr' osd 'allow *' mds 'allow *' -o /var/lib/ceph/mgr/ceph-${mgrNameServerIB}/keyring",
        creates => "/var/lib/ceph/mgr/ceph-${mgrNameServerIB}/keyring",
      } ->

      # Поменять права файлу
      file { "/var/lib/ceph/mgr/ceph-${mgrNameServerIB}/keyring":
        ensure => $ensure_object,
        group  => 'ceph',
        owner  => 'ceph',
        mode   => '0600',
      } ->

      # Вернуть имя хоста серверу по которому резолвится Ethernet интерфейс, например pnode04.
      exec { 'mgrNameServer':
        command => "hostnamectl set-hostname ${mgrNameServer}",
        unless  => "/usr/bin/test ${mgrNameServer} = `/bin/cat /etc/hostname`",
      } ->

      Service["ceph-mgr@${mgrNameServerIB}"] ->

      Service['ceph.target']

    }
    else {  # Удаление MGR
        Service['ceph.target'] ->
        Service["ceph-mgr@${mgrNameServerIB}"] ->
        Package['ceph-mgr'] ->

      file { "/var/lib/ceph/mgr/ceph-${mgrNameServerIB}/keyring":
        ensure => $ensure_object,
        group  => 'ceph',
        owner  => 'ceph',
        mode   => '0600',
      } ->

      File["/var/lib/ceph/mgr/ceph-${mgrNameServerIB}"] ->

      /*  # Возможно, кроме удаления файлов, необходимо удалять и bootstrap ключи, которые можно посмотреть командой "ceph auth ls".
      # Пока, для простоты не будем удалять. С директориями, тоже, пока не понятно. Нужно ли удалять, например директорию bootstrap-osd при
      # удалении MON и MGR. Удалим пока то, что точно нужно удалять и не будем удалять остальное.
      # Файлы /var/lib/ceph/bootstrap-mon/ceph.keyring и /var/lib/ceph/bootstrap-mgr/ceph.keyring не создаются.
      # Удалять здесь bootstrap ключи других сервисов - osd, mds, rbd, rgw - нельзя
      exec { '/bin/rm /var/lib/ceph/bootstrap-mgr/ceph.keyring':
        onlyif  => '/usr/bin/test -f /var/lib/ceph/bootstrap-mgr/ceph.keyring',
      } ->
      */
      # Создаётся при установке MON. Удаляется здесь
#      Exec['safelyDelCephConf'] ->
      File[ '/etc/ceph/ceph.conf'] ->

      # Создаётся при установке MON. Удаляется здесь
      File['/etc/ceph/ceph.client.admin.keyring']

    } # end # Удаление MGR
    ###################################################################



    # Ресурсы манифеста mon.pp используемые различными блоками кода манифеста mon.pp

    # Установить компоненты ceph MON и MGR. MGR должен устанавливаться и настраивается на том же сервере, где есть MON.
    package { 'ceph-mon':
      ensure  => $ensure_object,
    }
    package { 'ceph-mgr':
      ensure  => $ensure_object,
    }

    # Поменять права файлу
    file { "/var/lib/ceph/mon/ceph-${monNameServerIB}/keyring":
      ensure => $ensure_object,
      group  => 'ceph',
      owner  => 'ceph',
      mode   => '0600',
    }

    # Create a default data directory (or directories) on the monitor host(s).
    # Создать директорию, если она отсутствует
    file { "/var/lib/ceph/mon/ceph-${monNameServerIB}":
      ensure => $ensure_directory,
      group  => 'ceph',
      owner  => 'ceph',
      mode   => '0755',
      force  => true,
    }

    # Отконфигурировать и запустить службу MON
    service { "ceph-mon@${monNameServerIB}":
      ensure => $ensure_running,
      enable => $ensure_enable,
      notify => Ceph::Healthcheck[monCheckHealthOk],
    }

    # Create a default data directory (or directories) on the monitor host(s).
    # Создать директорию, если она отсутствует
    file {"/var/lib/ceph/mgr/ceph-${mgrNameServerIB}":
      ensure => $ensure_directory,
      group  => 'ceph',
      owner  => 'ceph',
      mode   => '0755',
      force  => true,
    }

    # Отконфигурировать и запустить службу MGR
    service {"ceph-mgr@${mgrNameServerIB}":
      ensure => $ensure_running,
      enable => $ensure_enable,
      notify => Ceph::Healthcheck[mgrCheckHealthOk],
    }

    # Проверка, что установка ceph прошла удачно. Выполняем exec-ом команду ceph health и ожидаем, что она вернёт "HEALTH_OK".
    ceph::healthcheck{'monCheckHealthOk':}

    # Проверка, что установка ceph прошла удачно. Выполняем exec-ом команду ceph health и ожидаем, что она вернёт "HEALTH_OK".
    ceph::healthcheck{'mgrCheckHealthOk':}
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в значении параметра ensure или ensure = undef.
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure было одним из следующих [running, stopped, absent]")
  }
}
