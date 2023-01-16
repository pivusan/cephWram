# Рекомендации по различным вопросам

[[_TOC_]]

Здесь приведены краткие рекомендации касающиеся различным аспектам связанным с ceph.


Рекомендации в выборе параметров ceph
----

1. max_mds

почему то ceph не даёт уменьшить число max_mds после его увеличения...

https://docs.ceph.com/en/latest/cephfs/multimds/

CONFIGURING MULTIPLE ACTIVE MDS DAEMONS
Also known as: multi-mds, active-active MDS

Each CephFS file system is configured for a single active MDS daemon by default. To scale metadata performance for large scale systems, you may enable multiple active MDS daemons, which will share the metadata workload with one another.

WHEN SHOULD I USE MULTIPLE ACTIVE MDS DAEMONS?
You should configure multiple active MDS daemons when your metadata performance is bottlenecked on the single MDS that runs by default.

Adding more daemons may not increase performance on all workloads. Typically, a single application running on a single client will not benefit from an increased number of MDS daemons unless the application is doing a lot of metadata operations in parallel.

Workloads that typically benefit from a larger number of active MDS daemons are those with many clients, perhaps working on many separate directories.

INCREASING THE MDS ACTIVE CLUSTER SIZE
Each CephFS file system has a max_mds setting, which controls how many ranks will be created. The actual number of ranks in the file system will only be increased if a spare daemon is available to take on the new rank. For example, if there is only one MDS daemon running, and max_mds is set to two, no second rank will be created. (Note that such a configuration is not Highly Available (HA) because no standby is available to take over for a failed rank. The cluster will complain via health warnings when configured this way.)


STANDBY DAEMONS
Even with multiple active MDS daemons, a highly available system still requires standby daemons to take over if any of the servers running an active daemon fail.

Consequently, the practical maximum of max_mds for highly available systems is at most one less than the total number of MDS servers in your system.

To remain available in the event of multiple server failures, increase the number of standby daemons in the system to match the number of server failures you wish to withstand.

Рекомендации для стабильной работы ceph
----

Наблюдать за свободным местом и не допускать переполнения

Рекомендации в установке компонент ceph
----

MON

Рекомендуется как минимум 3 MON для кластера. Желательно запускать нечетное количество мониторов. Нечетное количество мониторов более устойчиво, чем четное. Например, при развертывании с двумя мониторами нельзя допускать сбоев и при этом сохраняется кворум; с тремя мониторами можно допустить один сбой; при развертывании с четырьмя мониторами можно допустить один сбой; с пятью мониторами можно допустить два сбоя.
Количество мониторов до пяти рекомендуется для больших кластеров. Семь или больше MON бывает нужно крайне редко.

