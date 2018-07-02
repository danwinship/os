text
lang en_US.UTF-8
keyboard us
timezone --utc Etc/UTC
auth --useshadow --passalgo=sha512
selinux --enforcing
rootpw --lock --iscrypted locked
# create core user for now
# https://github.com/openshift/os/issues/96
user --name=core --groups='wheel,sudo,adm,systemd-journal'

# Explicitly disable firewall since cloud providers generally provide
# higher level firewall constructs (i.e. security groups).
firewall --disabled

network --bootproto=dhcp --onboot=on
services --enabled=sshd
services --disabled=network,avahi-daemon

zerombr
clearpart --initlabel --all
# Add the following to kernel boot args:
#  - ip=dhcp           # how to get network
#  - rd.neednet=1      # tell dracut we need network
#  - enforcing=0       # ignition + selinux doesn't work
#  - $coreos_firstboot # This is actually a GRUB variable
bootloader --timeout=1 --append="no_timer_check console=tty1 console=ttyS0,115200n8 net.ifnames=0 biosdevname=0 ip=dhcp rd.neednet=1 enforcing=0 $coreos_firstboot"

part /boot --size=300 --fstype="xfs"
part pv.01 --grow
volgroup coreos pv.01
logvol / --size=3000 --fstype="xfs" --name=root --vgname=coreos

ostreesetup --nogpg --osname=rhcos --remote=rhcos --url=@@OSTREE_INSTALL_URL@@ --ref=@@OSTREE_INSTALL_REF@@


reboot

%post --erroronfail

# https://github.com/dustymabe/ignition-dracut/pull/12
touch /boot/coreos-firstboot

# Configure docker-storage-setup to resize the partition table on boot
# https://github.com/projectatomic/docker-storage-setup/pull/25
echo 'GROWPART=true' >> /etc/sysconfig/docker-storage-setup
# https://pagure.io/atomic-wg/issue/343
echo 'ROOT_SIZE=+100%FREE' >> /etc/sysconfig/docker-storage-setup

# older versions of livecd-tools do not follow "rootpw --lock" line above
# https://bugzilla.redhat.com/show_bug.cgi?id=964299
passwd -l root
# remove the user anaconda forces us to make
#userdel -r none

# although we want console output going to the serial console, we don't
# actually have the opportunity to login there. FIX.
# we don't really need to auto-spawn _any_ gettys.
echo "Getty fixes."
sed -i -e '\|#NAutoVTs=.*|a NAutoVTs=0' /etc/systemd/logind.conf

# Remove any persistent NIC rules generated by udev
rm -vf /etc/udev/rules.d/*persistent-net*.rules

echo "Network fixes."
# initscripts don't like this file to be missing.
cat <<EOF > /etc/sysconfig/network
NETWORKING=yes
NOZEROCONF=yes
EOF

# simple eth0 config, again not hard-coded to the build hardware
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
PERSISTENT_DHCLIENT="yes"
NM_CONTROLLED="yes"
EOF

# generic localhost names
cat <<EOF > /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

EOF


# Because memory is scarce resource in most cloud/virt environments,
# and because this impedes forensics, we are differing from the Fedora
# default of having /tmp on tmpfs.
systemctl mask tmp.mount

# make sure firstboot doesn't start
echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

# Anaconda is writing a /etc/resolv.conf from the generating environment.
# The system should start out with an empty file.
truncate -s 0 /etc/resolv.conf

# clean-up
echo "Removing random-seed so it's not the same in every image."
rm -f /var/lib/random-seed

echo "Removing /root/anaconda-ks.cfg"
rm -f /root/anaconda-ks.cfg
%end
