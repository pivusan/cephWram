# = Class: mount
#
# == Назначение
#
# Манифест для развёртывания ceph. Монтирование FS
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
# [*ensure_hdd и ensure_ram*]
#   Параметр отвечает за монтирование hdd и ram pools соответственно.
#   Возможные значения: running (запущен), stopped (остановлен), absent (удалён), undef (манифест не применяется).
#   Передаётся в виде строки.
#   Стандартное значение: undef
#
class ceph::mount
(
  $ensure_hdd = undef,
  $ensure_ram = undef,
)
{

  # Формальная проверка параметров модуля ceph
  $ensure_values = ['running', 'stopped', 'absent']
  unless (member($ensure_values, $ensure_hdd) or ($ensure_hdd == undef) ) {
    fail("Модуль ${module_name}. Параметр \$ensure_hdd=$ensure_hdd, но должен иметь значения 'running', 'stopped', 'absent', or 'undef'")
  }
  unless (member($ensure_values, $ensure_ram) or ($ensure_ram == undef) ) {
    fail("Модуль ${module_name}. Параметр \$ensure_ram=$ensure_ram, но должен иметь значения 'running', 'stopped', 'absent', or 'undef'")
  }

  # Если принято решение применять модуль ceph штатно, то $apply_ceph = true
  if (( $ceph::apply_ceph == true ) and (
    # И если какой либо параметр ensure_* не undef.
     ( $ensure_hdd in [ 'running', 'stopped', 'absent' ] ) or
     ( $ensure_ram in [ 'running', 'stopped', 'absent' ] ) ) ) {
    # Для тех $ensure_*, которые имеют значения 'running', 'stopped' или 'absent', "вызываем" define. Это создаст ресурсы puppet, которые в зависимости от ensure_* смонтируют, отмонтируют или удалят точку монтирования для hdd и/или ram.
    if $ensure_hdd in [ 'running', 'stopped', 'absent' ] {
      ceph::defmount{'hdd': ensure => $ensure_hdd }
    }
    if $ensure_ram in [ 'running', 'stopped', 'absent' ] {
      ceph::defmount{'ram': ensure => $ensure_ram }
    }
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != true
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в параметрах или оба параметра ensure_* - undef
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure_hdd и \$ensure_ram было одним из следующих [running, stopped, absent]")
  }
}
