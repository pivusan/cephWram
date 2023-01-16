# = Class: cli
#
# == Назначение
#
# Манифест для развёртывания ceph. Развёртывание и удаление клиента ceph.
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
class ceph::cli
(
  $ensure = 'running',
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

    # Зависимости между классами. Текущий класс требуется применить после класса 'ceph::system'
    require ceph::system

    ####################  Ensure для разных типов  ####################
    $ensure_object=$ensure ? {
      'running' => 'present',
      'stopped' => 'present',
      'absent'  => 'absent',
    }
    ###################################################################

    #################  Последовательность применения  #################
    if $ensure != 'absent' {
      # Если коллектор найдёт пакет ceph-mon, значит класс 'ceph::mon' есть, тогда текущий класс следует применить после класса 'ceph::mon'.
      # Это особенно нужно, когда устанавливается первый MON
      Package <| name == 'ceph-mon' |> ->
      # Пакеты необходимые для клиента ceph
      package { ['ceph-common', 'ca-certificates', 'apt-transport-https'] :
        ensure  => $ensure_object,
      } ->

      # Получить файл /etc/ceph/ceph.conf из внешнего ресурса
      #File <<| tag == 'etc_ceph_conf' |>> ->
      # В новой реализации, взять файл /etc/ceph/ceph.conf из шаблона
      File[ '/etc/ceph/ceph.conf'] ->
      File[ '/etc/ceph/ceph.client.admin.keyring'] ->

      # Чтобы не писать sudo перед каждой командой ceph для получения информации по ceph и других задач, нужен этот блок настроек по созданию прав для пользователя cephadm для выполнения указанных действий без sudo.
      #Создать ключ для пользователя cephadm
      exec { "ceph auth get-or-create client.cephadm mon 'allow *' osd 'allow *' mds  'allow *' mgr 'allow *' -o /etc/ceph/ceph.client.cephadm.keyring":
        creates => '/etc/ceph/ceph.client.cephadm.keyring',
      }
    }
    else { # Здесь не так важна последовательность удаления, но пропишем её для единообразия, примерно так должно быть везде.
      # Оказалось, что удалять эти пакеты нельзя. Например, puppet-y нужны ca-certificates...
      # Package[ 'ceph-common', 'ca-certificates', 'apt-transport-https' ] ->

      #Exec['safelyDelCephConf'] ->
      File[ '/etc/ceph/ceph.conf'] ->
      File[ '/etc/ceph/ceph.client.admin.keyring']

      # Удалить ключ для пользователя cephadm
      # Ещё нужно будет удалить ключ из базы? который виден по команде ceph auth ls. Пока удалять из базы не будем для простоты.
      file { '/etc/ceph/ceph.client.cephadm.keyring':
        ensure => 'absent',
      }
    }
    ###################################################################
  }
  # Если принято решение не применять модуль ceph штатно, то $apply_ceph != 'true'
  else {
    # Ничего не делать, если принято решение не применять штатно модуль ceph или ошибка в значении параметра ensure или ensure = undef.
    notice("Для применения текущего манифеста необходимо, чтобы следующие параметры принимали такие значения: \$ceph::apply_ceph == true, \$ensure было одним из следующих [running, stopped, absent]")
  }
}
