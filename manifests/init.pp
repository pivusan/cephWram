# = Class: ceph
#
# == Назначение
#
# Манифест установки параметров, для управления и настройки модуля ceph.
#
# == Использование
#
# В виде класса в составе модуля ceph. Класс ceph должен быть расположен до классов модуля ceph в site.pp так как класс ceph устанавливает глобальные постоянные.
#
# == Параметры
#
# [*apply_ceph*]
#   Параметр указывает применять ли манифесты модуля ceph. Этот параметр сейчас нужен, для того, чтоб на ЦАГИ, где ceph установлен вручную, не повредить ceph применением модуля.
#   Возможные значения: true (применять модуль ceph), false (не применять модуль ceph).
#   Передаётся в виде boolean значения.
#   Стандартное значение: true
#
# [*check_health*]
#   Параметр указывает проводить ли проверку состояния кластера ceph во время развёртывания. Этот параметр необходим чтобы отключить проверку состояния кластера ceph во время развёртывания. Отключать проверку стоит тогда и только тогда, когда мы точно понимаем по какой причине кластер ceph не находится в состоянии HEALTH_OK. А также чётко понимаем, что это состояние, отличное от HEALTH_OK, позволит нам корректно провести развёртывание кластера ceph.
#   Возможные значения: true (проводить проверку корректности развёртывания ceph), false (не проводить).
#   Передаётся в виде boolean значения.
#   Стандартное значение: true
#
# [*all_mon_name_data*]
#   Имя сервера интерфейса для передачи данных (обычно Infiniband) только одного первого MON кластера ceph.
#   Передаётся в виде Array, например, ['pnode01ib']
#   Стандартное значение: Не существует
#
# [*Остальные параметры*]
#   Описание остальных параметров приведено в соответствующих параметрам манифестах.
#

class ceph
(
  # ==Общие параметры настройки кластера ceph==
    $apply_ceph        = true,
    $monitoring_enable = true,
    $check_health      = true,

  # ==Параметры настройки system.pp==
    $uid_cephadm  = 2100,
    $gid_cephadm  = 2100,

    $uid_ceph     = 64045,
    $gid_ceph     = 64045,

    $osd_ram_size = 2097152,

  # ==Параметры настройки mon.pp==

    $fsid = 'e6e02b3c-f73c-4512-bbba-95744311ebed',
    #$fsid = generate('/usr/bin/uuidgen -r')

    $first_mon = false,
    $first_mon_ip_data   = '10.10.10.194',
    $all_mon_name_data   = ['cephmon07ib'],
    $public_network_data = '10.10.10.0',
    $mask_public_network_data = 24,

  # ==Параметры настройки osdhdd.pp==
    $nameDisksOsdHdd   = ['/dev/sdb', '/dev/sdc', '/dev/sdd', '/dev/sde', '/dev/sdf', '/dev/sdg',],
    $forceDelLvmOsdHdd = false,

  # ==Параметры настройки osdram.pp==
    $osdramWeight = 0.00189,
    $forceDelLvmOsdRam = false,

  # ==Параметры настройки pool.pp==
    $k            = 3,
    $m            = 2,
    $max_mds_fss  = 1,

  # ==Параметры настройки defmount.pp==
    $all_mon_ip_data = ['10.10.10.173', '10.10.10.182', '10.10.10.194'],
    $cephfs_basedir  = '/var/cephfs',

  # ==Параметры настройки monitoring.pp==
    $clientid        = 'nagios',
    $keyring         = '/etc/ceph/ceph.client.nagios.keyring',

    $dfwarning       = 65.00,
    $dfcritical      = 85.00,
    $ram_data        = 'pool_erasure_ram_data',
    $ram_metadata    = 'pool_replicated_ram_metadata',
    $hdd_data        = 'pool_erasure_hdd_data',
    $hdd_metadata    = 'pool_replicated_hdd_metadata',

    $osddfwarning    = 65.00,
    $osddfcritical   = 85.00,
    $postfixibname   = 'ib',
    $numberfailedosd = 1,

)
{
  # Формальная проверка параметров модуля ceph

  # This should be a boolean.
    validate_legacy(Boolean, 'validate_bool', $apply_ceph)
    validate_legacy(Boolean, 'validate_bool', $monitoring_enable)
    validate_legacy(Boolean, 'validate_bool', $check_health)
    validate_legacy(Boolean, 'validate_bool', $first_mon)
    validate_legacy(Boolean, 'validate_bool', $forceDelLvmOsdHdd)
    validate_legacy(Boolean, 'validate_bool', $forceDelLvmOsdRam)

  # This should be a integer.
    Integer($uid_cephadm)
    Integer($gid_cephadm)
    Integer($uid_ceph)
    Integer($gid_ceph)
    Integer($osd_ram_size)
    Integer($mask_public_network_data)
    Integer($k)
    Integer($m)
    Integer($max_mds_fss)
    Integer($numberfailedosd)

  # This should be a Numeric.
    Numeric($osdramWeight)
    Numeric($dfwarning)
    Numeric($dfcritical)
    Numeric($osddfwarning)
    Numeric($osddfcritical)

    # FSID should be a UUID.
    validate_legacy(Pattern[/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/],
    'validate_re', $fsid, ['[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    'FSID должен быть UUID.'])

  # This should be a IP and Network
#    validate_ipv4_address($first_mon_ip_data)
#    validate_ipv4_address($public_network_data)
    validate_legacy(Stdlib::IP::Address::V4, 'validate_ipv4_address', $first_mon_ip_data)
    validate_legacy(Stdlib::IP::Address::V4, 'validate_ipv4_address', $public_network_data)


  # This should be a Array
    validate_legacy(Array, 'validate_array', $all_mon_name_data)
    validate_legacy(Array, 'validate_array', $nameDisksOsdHdd)
    validate_legacy(Array, 'validate_array', $all_mon_ip_data)

  # This should be a path
#    validate_absolute_path($cephfs_basedir)
#    validate_absolute_path($keyring)
    validate_legacy(Stdlib::Absolutepath, 'validate_absolute_path', $cephfs_basedir)
    validate_legacy(Stdlib::Absolutepath, 'validate_absolute_path', $keyring)


  # This should be a String
    validate_legacy(String, 'validate_string', $clientid)
    validate_legacy(String, 'validate_string', $ram_data)
    validate_legacy(String, 'validate_string', $ram_metadata)
    validate_legacy(String, 'validate_string', $hdd_data)
    validate_legacy(String, 'validate_string', $hdd_metadata)
    validate_legacy(String, 'validate_string', $postfixibname)
}
