# = Define: healthcheck
#
# == Назначение
#
# Ресурс для проверки успешности прохождения отдельных стадий установки ceph
#
# == Использование
#
# В виде define в составе модуля ceph.
#
# == Детали реализации
#
# Управление ресурсами посредством Puppet
#

define ceph::healthcheck
(
)
{
  # Если принято решение применять модуль ceph штатно, то $apply_ceph = true
  if ( $ceph::apply_ceph == true ) and
    # И если принято решение проводить проверку состояния кластера ceph во время развёртывания
    ( $ceph::check_health == true ) {
    # Добавление параметра path сразу во все ресурсы exec в этом манифесте
    Exec { path => [ '/usr/bin', '/usr/sbin', '/usr/local/sbin', '/usr/local/bin', '/sbin', '/bin' ] }

    # Количество секунд равное (timeout+try_sleep)*tries ожидать появления статуса HEALTH_OK у кластера ceph
    exec { "${title}":
      command     => 'ceph health|grep HEALTH_OK',
      timeout     => 300,
      tries       => 3,
      try_sleep   => 60,
      refreshonly => true,
    }
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph
    notice('Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: $ceph::apply_ceph - [true], $check_health - [true]')
  }
}
