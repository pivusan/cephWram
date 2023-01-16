sudo systemctl disable ${1}
sudo mv ${1}  /etc/systemd/system/
sudo systemctl enable ${1}
sudo systemctl daemon-reload
sudo systemctl status ${1}
systemctl cat ${1}
tail /var/log/syslog
