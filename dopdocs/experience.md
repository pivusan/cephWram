# Полученный опыт и знания

[[_TOC_]]

Здесь приведены заметки по ceph и некоторые другие полученные знания.

Ceph
----

- Опасно заполнять pool ceph более чем на 70%
- Перед удалением osd нужно оценить хватит ли места ceph сохранить данные с удаляемого osd. При этом опасно заполнять pool ceph данными, с учётом данных с удаляемого osd, более чем на 70%
- Ключ администратора ceph */etc/ceph/ceph.client.admin.keyring* не создаётся, а копируется из заранее подготовленного ключа. Это приведёт к тому, что ключ администратора будет одинаковый на всех кластерах ceph. А значит, в теории, с одного кластера ceph, можно будет управлять другим кластером ceph проведя манипуляции с файлом */etc/ceph/ceph.conf*
- При *\$k=5* и *\$m=2*, необходимо развернуть всего как минимум 7 HDD и 7 RAM на как минимум 7 серверах.
- Необходимо следить, чтоб ресурс *ceph::shareresources* был последним по порядку в "Используемые ресурсы" КСУ.

Настройка сопутствующего оборудования
----------
- Необходимо включить хотя бы один sm на управляемом Infiniband switch-е
- Если возникли проблемы с hdd ( было на двух серверах стенда 4) необходимо выполнить:

```bash
for i in b c d e f g h i j k l m n; do smartctl -a /dev/sd$i; done|grep Formatted
```

или

```bash
smartctl  --scan
smartctl -a /dev/sdX -d megaraid,1
```

и отформатировать "проблемные" диски, например так:

```bash
sg_format --format --fmtpinfo=0 /dev/sdX
```

Puppet
----------
- Если в логах при применении puppet появилось сообщение:

```
puppet-user[4343]: A duplicate resource was found while collecting exported resources, with the type and title File[/etc/ceph/ceph.conf] on node "
```

Надо удалить ранее экспортированный ресурс, файл */etc/ceph/ceph.conf* из puppetdb, оставшийся от старой установки ceph.
Чтобы удалить экспортированый ресурс */etc/ceph/ceph.conf* из puppetdb нужно зайти на сервер Puppet Master (либо с клиента от adminuser через sudo) и выполнить:

```bash
sudo puppet node deactivate <fqdn узла с которого был экспорт> , например:
sudo puppet node deactivate stendceph1.ppoi.ensk
```

- Если нужно удалить сертификаты некоторых переразвёрнутых серверов, надо с Puppet master'а выполнить:

```bash
puppet cert clean 'FQDN узла', например:
puppet cert clean stendceph1.ppoi.ensk
```

- Если после удаления сертификатов происходят ошибки соединения с puppet master. То на клиенте:

```bash
adminuser@cephmon07:~$ sudo puppet agent -t
Exiting; no certificate found and waitforcert is disabled
adminuser@cephmon07:~$ sudo rm -rf /var/lib/puppet/ssl
adminuser@cephmon07:~$ sudo puppet agent -t
```

- Если нужно локально проверить манифест на ошибки:

```bash
puppet apply --noop --modulepath=/etc/puppet/cephmon07_ppoi_ensk/modules line.pp
```
- Заметки по установке флагов ceph
https://docs.ceph.com/en/latest/rados/operations/health-checks/

OSDMAP_FLAGS
One or more cluster flags of interest has been set. These flags include:
full - the cluster is flagged as full and cannot serve writes
pauserd, pausewr - paused reads or writes
noup - OSDs are not allowed to start
nodown - OSD failure reports are being ignored, such that the monitors will not mark OSDs down
noin - OSDs that were previously marked out will not be marked back in when they start
noout - down OSDs will not automatically be marked out after the configured interval
nobackfill, norecover, norebalance - recovery or data rebalancing is suspended
noscrub, nodeep_scrub - scrubbing is disabled
notieragent - cache tiering activity is suspended

ceph osd set <flag>
ceph osd unset <flag>
ceph osd set-group noup,noout osd.0 osd.1
ceph osd unset-group noup,noout osd.0 osd.1
ceph osd set-group noup,noout host-foo
ceph osd unset-group noup,noout host-foo
ceph osd set-group noup,noout class-hdd
ceph osd unset-group noup,noout class-hdd

- Заметки по параметрам ratio
https://docs.ceph.com/en/latest/rados/operations/health-checks/
ceph osd dump | grep ratio
ceph osd set-nearfull-ratio <ratio>
ceph osd set-backfillfull-ratio <ratio>
ceph osd set-full-ratio <ratio>

- Заметки по квотам на pool

POOL_FULL
https://docs.ceph.com/en/latest/rados/operations/health-checks/
One or more pools has reached its quota and is no longer allowing writes.
Pool quotas and utilization can be seen with:
ceph df detail
You can either raise the pool quota with:
ceph osd pool set-quota <poolname> max_objects <num-objects>
ceph osd pool set-quota <poolname> max_bytes <num-bytes>
or delete some existing data to reduce utilization.


MOST STABLE CONFIGURATION
https://docs.ceph.com/en/mimic/cephfs/best-practices/
Some features in CephFS are still experimental. See Experimental Features for guidance on these.
For the best chance of a happy healthy filesystem, use a single active MDS and do not use snapshots. Both of these are the default.
Note that creating multiple MDS daemons is fine, as these will simply be used as standbys. However, for best stability you should avoid adjusting max_mds upwards, as this would cause multiple MDS daemons to be active at once.

Where can you expect improvements?
https://ceph.io/community/new-luminous-multiple-active-metadata-servers-cephfs/
Of course, this kind of “embarrassingly parallel” workload (multiple clients operating in independent directory trees) is somewhat artificial. Not all workloads may benefit, especially when clients cooperate on updates to a single directory or file.

IMPORTANT
https://access.redhat.com/documentation/en-us/red_hat_ceph_storage/4/pdf/file_system_guide/Red_Hat_Ceph_Storage-4-File_System_Guide-en-US.pdf
The scrubbing process is not currently supported when multiple active MDS daemons are
configured.

Выгрузить модуль ядра для RAM диска.
----------
1. Остановить RAM OSD (systemctl stop cephosd@№)
2. Удалить LVM на RAM диске (lvremove ID)
3. Выгрузить модуль (modprobe -r brd)

Увеличить скорость восстановления кластера
----------
ceph tell 'osd.*'  injectargs '--osd-max-backfills 128'

вернуть к настройкам по умолчанию
ceph tell 'osd.*'  injectargs '--osd-max-backfills 1'


Для замены/восстановления MON развёрнутого первым
----
При попытке замены/восстановления MON развёрнутого первым, в силу особенностей создания первого MON, разворачивается MON не привязанный к "основному" кластеру ceph. MON создаётся, как минимум, с ключами и fsid, отличными от "основного" кластера ceph. После такого создания связать (простым способом) первый MON и "основной" кластер ceph не представляется возможным.


Замена сложного текста в нескольких файлах
----
find ./ -type f -exec sed -i -r 's/fail\(\"\$\{module_name\}\ в\ manifest\ \$\{name\}\:/fail\(\"\$\{module_name\}\ в\ manifest\ \$\{name\}\./g' {} \;


Если сервер, являющийся first_mon выйдет из строя, интегральные параметры кластера ceph не будут мониториться.
----

Попытка преодоления блокировки клиентов, при интенсивной записи в директории на ram pool при установленной метке 2 
----
2022.10.10

/etc/ceph/ceph.conf
mds_session_blacklist_on_timeout = false
mds_session_blacklist_on_evict = false
mds_cap_revoke_eviction_timeout = 900

ceph osd blacklist ls
ceph osd blacklist rm NAME|ID

sudo ceph --admin-daemon /run/ceph/ceph-osd.0.asok config show|grep -i black


Уменьшение min_size pool-ов. Для попытки восстановления ceph 
----
ceph osd pool set "ИМЯ pool-a" min_size 5
