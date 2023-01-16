# = Define: monitoring
#
# == Назначение
#
# Ресурс создания условий для выполнения проверок кластера ceph системой мониторинга (Nagios)
#
# == Использование
#
# В виде define в составе модуля ceph.
# Применяется ко всем серверам, параметры которых необходимо мониторить. А также, проверки будут создаваться на Сервере управления :(
#
# == Детали реализации
#
# Управление ресурсами посредством Puppet
#
# == Параметры
#
# [*typemonitoring*]
#   Параметр передаётся в заголовке define. Определяет экспортирование проверок, в зависимости от типа сервера.
#   Возможные значения: integral(интегральные проверки кластера ceph, экспортируются на Сервер управления), mon (проверки сервера MON, присутствуют только на серверах MON), "mds" (проверки CephFS, присутствуют только на серверах MDS), "osd*"(проверки OSD, присутствуют только на серверах OSD)
#   Передаётся в виде строки.
#   Стандартное значение: отсутствует
#
# [*enable*]
#   Параметр отвечает за поддерживаемое состояние управляемых манифестом ресурсов.
#   Возможные значения: true (ресурсы создаются), false (ресурсы не создаются), "другое" (манифест не применяется).
#   Передаётся в виде строки.
#   Стандартное значение: true
#
# [*nrpe_d_path*]
#   Параметр указывает на путь хранения шаблона команд запуска проверок.
#   Возможные значения: /etc/nrpe.d/.
#   Передаётся в виде строки.
#   Стандартное значение: /etc/nrpe.d/
#
# [*sm_hostname*]
#   FQDN сервера управления. На этот сервер экспортируются интегральные проверки кластера ceph.
#   Возможные значения: sm1.cagi.ensk
#   Передаётся в виде строки.
#   Стандартное значение: отсутствует
#
# [*clientid*]
#   ID сервисного пользователя выполняющего задачи мониторинга ceph
#   Передаётся в виде строки.
#   Стандартное значение: "nagios"
#
# [*keyring*]
#   Ключ аутентификации для сервисного пользователя
#   Передаётся в виде строки.
#   Стандартное значение: "/etc/ceph/ceph.client.nagios.keyring"
#
# [*dfwarning, dfcritical*]
#   Пороги для метрики RAW USAGE всего кластера ceph.
#   Измеряется в процентах.
#   Передаётся в виде числа с плавающей точкой
#   Стандартные значения: 65.00, 85.00
#
# [*ram_data, ram_metadata, hdd_data, hdd_metadata*]
#   Имена соответствующих pools
#   Передаётся в виде строки.
#   Стандартные значения: "pool_erasure_ram_data, pool_replicated_ram_metadata, pool_erasure_hdd_data, pool_replicated_hdd_metadata"
#
# [*osddfwarning, osddfcritical*]
#   Пороги для метрики процент использования OSD. Проверяются OSD всего кластера.
#   Измеряется в процентах.
#   Передаётся в виде числа с плавающей точкой
#   Стандартные значения: 65.00, 85.00
# 
# [*postfixibname*]
#   Постфикс имени для интерфейса передачи данных
#   Передаётся в виде строки.
#   Стандартное значение: "ib"
#
# [*numberfailedosd*]
#   Количество OSD, выход из строя которых на сервере, будет инициировать сообщение о критическом уровне ошибки
#   Передаётся в виде целого числа.
#   Стандартное значение: "1"
#
define ceph::monitoring
(
  $typemonitoring  = ${title},
  $typeosd         = undef,

  $enable          = $ceph::monitoring_enable,

  $nrpe_d_path     = $::nagios::nrpe::nrpe_d_path
  $sm_hostname     = $::sm_hostname

  $clientid        = $ceph::clientid,
  $keyring         = $ceph::keyring,

  $dfwarning       = $ceph::dfwarning,
  $dfcritical      = $ceph::dfcritical,
  $ram_data        = $ceph::ram_data,
  $ram_metadata    = $ceph::ram_metadata,
  $hdd_data        = $ceph::hdd_data,
  $hdd_metadata    = $ceph::hdd_metadata,

  $osddfwarning    = $ceph::osddfwarning,
  $osddfcritical   = $ceph::osddfcritical,
  $postfixibname   = $ceph::postfixibname,
  $numberfailedosd = $ceph::numberfailedosd,

)
{

  # Формальная проверка параметров модуля ceph
  # This should be a boolean.
    validate_legacy(Boolean, 'validate_bool', $enable)

  $typemonitoring_values = ['integral', 'mon', 'mds', 'osdram', 'osdhdd']
  unless member($typemonitoring_values, $typemonitoring) {
    fail("Модуль ${module_name}. Параметр \$typemonitoring=$typemonitoring_values, но должен иметь значения 'integral', 'mon', 'mds', 'osdram' или 'osdhdd'")
  }

  # Если принято решение применять модуль ceph штатно, то $apply_ceph = true
  if ( $ceph::apply_ceph == true ) and
    # И если параметр $enable не undef.
    (( $enable == true )  or
     ( $enable == false )) {
    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    # Составим имя сервера указывающего на интерфейс передачи данных (обычно это Infiniband интерфейс)
    $hostnameib="${::hostname}${postfixibname}"

    ####################  Ensure для разных типов  #################### 
    $ensure_object=$enable ? {
      true    => 'present',
      false   => 'absent',
    }
    $ensure=$enable ? {
      true    => 'present',
      false   => 'absent',
    }
    ###################################################################

    # Если ОС Astra Linux SE 1.6 (Smolensk)
    if ($::lsbdistid       == 'AstraLinuxSE') and
       ($::lsbdistcodename == 'smolensk'    ) and
       ($::lsbdistrelease  == '1.6'         ) {

      if $nagios::nrpe::ensure == 'present' {

        # Create an authentication key
        if ( $enable == true ) {
          ensure_resource('exec', 'MonitoringKeyNrpeAdd', {
            command => "ceph auth get-or-create client.${clientid} mon 'allow r' mgr 'allow r' mds 'allow r' -o $keyring",
            creates => "$keyring",
          })
        }
        # Del an authentication key
        elsif ( $enable == false ) {
          ensure_resource('exec', 'MonitoringKeyNrpeDel', {
            command => "/bin/rm $keyring",
            onlyif  => "/usr/bin/test -f $keyring",
          })
        }

        # Общий файл со всеми командами запуска проверок.
        ensure_resource('file', "$nrpe_d_path/ceph.cfg",  {
          ensure    => "$ensure",
          content   => template('ceph/nrpe/ceph.cfg.erb'), 
          notify    => Service['nagios-nrpe-server'],
          require   => Package['nagios-nrpe-server'],
        })
      }
      else {
        notice('Параметр $nagios::nrpe::ensure не равен "present". На сервере не сформируется шаблон с командами проверок.')
      }

      # Экспортировать проверки в зависимости от сервера, на котором применяются проверки
      case $typemonitoring {
        'integral': { # Интегральные проверки. Применяются на одном сервере кластера ceph. Сами проверки экспортируются на Сервер управления
          nagios::check { "$::fqdn-ceph-health":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => 'PM::Ceph::Cluster::Health',
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_health",
            use                 => 'local-service',
          }
          nagios::check { "$::fqdn-ceph-mgr":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => 'PM::Ceph::Cluster::Mgr::Health',
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_mgr",
            use                 => 'local-service',
          }
          nagios::check { "$::fqdn-ceph-df":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => 'PM::Ceph::Cluster::Raw usage',
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_df",
            use                 => 'local-service',
          }
          nagios::check { "$::fqdn-ceph-osd-df":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => 'PM::Ceph::Cluster::Osd::Raw usage',
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_osd_df",
            use                 => 'local-service',
          }
          nagios::check { "$::fqdn-ceph-df-${hdd_metadata}":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => "PM::Ceph::Pool::${hdd_metadata}::Raw usage",
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_df_${hdd_metadata}",
            use                 => 'local-service',
          }
          nagios::check { "$::fqdn-ceph-df-${hdd_data}":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => "PM::Ceph::Pool::${hdd_data}::Raw usage",
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_df_${hdd_data}",
            use                 => 'local-service',
          }
          nagios::check { "$::fqdn-ceph-df-${ram_metadata}":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => "PM::Ceph::Pool::${ram_metadata}::Raw usage",
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_df_${ram_metadata}",
            use                 => 'local-service',
          }
          nagios::check { "$::fqdn-ceph-df-${ram_data}":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$sm_hostname",
            service_description => "PM::Ceph::Pool::${ram_data}::Raw usage",
            check_command       => "check_nrpe_host!${::hostname}!check_ceph_df_${ram_data}",
            use                 => 'local-service',
          }
        }
        # Локальные проверки, которые необходимо применять на некоторых серверах ceph
        'mon': { # Применяются на сервере с ролью MON
          nagios::check { "$::fqdn-ceph-mon":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$::fqdn",
            service_description => 'PM::Ceph::Mon::Health',
            check_command       => "check_nrpe!check_ceph_mon",
            use                 => 'local-service',
          }
        }
        'mds': { # Применяются на сервере с ролью MDS
          nagios::check { "$::fqdn-ceph-mds":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$::fqdn",
            service_description => 'PM::Ceph::Mds::Health',
            check_command       => "check_nrpe!check_ceph_mds_typefs",
            use                 => 'local-service',
          }
        }

        # Локальные проверки, применимые на всех серверах ceph
        'osdram', 'osdhdd': { # Применяются на сервере с ролью OSD (у нас, на всех серверах)
          ensure_resource('nagios::check', "$::fqdn-ceph-osd", {
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$::fqdn",
            service_description => 'PM::Ceph::Osd::Health',
            check_command       => "check_nrpe!check_ceph_osd",
            use                 => 'local-service',
          })
          nagios::check { "$::fqdn-ceph-osd_${typeosd}":
            ensure              => "$ensure",
            exported            => true,
            host_name           => "$::fqdn",
            service_description => "PM::Ceph::Osd::${typeosd}::Health",
            check_command       => "check_nrpe_long!check_ceph_osd_${typeosd}",
            use                 => 'local-service',
          }
          # Добавить или удалить в общий файл со всеми командами запуска проверок, проверку для check_ceph_osd_${typeosd}
          file_line { "check_ceph_osd_${typeosd}":
            ensure      => $ensure_object,
            path        => "$nrpe_d_path/ceph.cfg",
            line        => "command[check_ceph_osd_${typeosd}]=/usr/lib/nagios/plugins/ceph/check_ceph_osd_typeosd          -i $clientid -k $keyring --type $typeosd",
            notify      => Service['nagios-nrpe-server'],
            require     => Package['nagios-nrpe-server'],
          }
        }
      }
    }
    else {
      notice("${module_name} в manifest ${name}: Применение текущего манифеста тестировалось только на Операционной системе специального назначения «Astra Linux Special Edition» 1.6. Ваша ОС не поддерживается. Манифест ${name} не будет применён.")
    }
  }
  else {
    # Ничего не делать, если не заданы требуемые параметры
    notice('Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: $ceph::apply_ceph - [true], $enable - [true, false], $typeosd - [ram, hdd], $typemonitoring - [integral, mon, mds, osdram, osdhdd]')
  }
}
