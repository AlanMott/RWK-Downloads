#!/bin/ash

### Waiting for NTP time set flag
NTP_TIME_SET_FILE=/tmp/ntp.timeset
INTERVAL_WAIT_NTP=5
while [ ! -f "$NTP_TIME_SET_FILE" ]
do
	sleep $INTERVAL_WAIT_NTP
done

FILESAM=/etc/init.d/sam
if [ ! -f "$FILESAM" ]; then
	# FIRST - put init_script in /etc/init.d/sam
	curl -4 https://static-files.demo.sam.securingsam.io/askey_sam_init.sh -o /usr/bin/askey_sam_init.sh
	chmod +x /usr/bin/askey_sam_init.sh
	
	# Askey: Generate /etc/init.d/sam
	echo "#!/bin/sh /etc/rc.common" > $FILESAM
	echo "#init script sam" >> $FILESAM
	echo "" >> $FILESAM
	echo "START=99" >> $FILESAM
	echo "" >> $FILESAM
	echo "start() {" >> $FILESAM
	echo "	/usr/bin/askey_sam_init.sh start &" >> $FILESAM
	echo "}" >> $FILESAM
	echo "" >> $FILESAM
	echo "stop() {" >> $FILESAM
	echo "	ps | grep askey_sam_init | grep -v grep | awk '{cmd=\"kill -9 \"$1;system(cmd)}'" >> $FILESAM
	echo "}" >> $FILESAM
	
	chmod +x /etc/init.d/sam
	# Make sure /etc/rc.d/S98sysntpd exist - so we being put after it
	ln -s /etc/init.d/sam /etc/rc.d/S99_sam
	# Execute sam
	/etc/init.d/sam start
fi

TOKEN=<ADD_ANANDA_TOKEN_HERE>
DIRANANDA=/opt/ananda/core
if [ ! -d "$DIRANANDA" ]; then
	# Download the binary and install
	curl -4 https://s3.us-west-2.amazonaws.com/gitlab-release-artifacts.8e14.net/Release/openwrt-askey-15/ananda-core-openwrt-askey-15.ipq.ipk -o ananda-core-openwrt-askey-15.ipq.ipk
	opkg install ananda-core-openwrt-askey-15.ipq.ipk
	sleep 2
	
	# Start ananda service
	/etc/init.d/ananda-core start
	sleep 3
	/opt/ananda/core/ananda-cli --login "$TOKEN"
fi

### Askey: add ananda interface to openwrt system.
sleep 10
WAN_ANANDA="ananda"
ANANDA_IP=`ifconfig 8e14-0 |grep  "inet addr:" | awk '{print $2}' | cut -d ":" -f 2`
CHECK_ANANDA=$(uci -q get network.$WAN_ANANDA)
if [ -z "$CHECK_ANANDA" ]; then
	uci set network.$WAN_ANANDA=interface
	uci set network.$WAN_ANANDA.ifname='8e14-0'
	uci set network.$WAN_ANANDA.netmask='255.255.0.0'
	uci set network.$WAN_ANANDA.ifname="$ANANDA_IP"
	uci commit network

#	remove the default dropbear config
	rm /etc/config/dropbear
	touch /etc/config/dropbear

#	add dropbear listener for local lan
	uci add dropbear dropbear
	uci set dropbear.@dropbear[-1].RootPasswordAuth='on'
	uci set dropbear.@dropbear[-1].PasswordAuth='on'
	uci set dropbear.@dropbear[-1].Port='22'
	uci set dropbear.@dropbear[-1].Interface='lan'
	uci set dropbear.@dropbear[-1].enable='1'

#	add dropbear listener for Ananda network
	uci add dropbear dropbear
	uci set dropbear.@dropbear[-1].RootPasswordAuth='on'
	uci set dropbear.@dropbear[-1].PasswordAuth='on'
	uci set dropbear.@dropbear[-1].Port='22'
	uci set dropbear.@dropbear[-1].Interface="$WAN_ANANDA"
	uci set dropbear.@dropbear[-1].enable='1'
	uci commit dropbear

#	allow for remote SSH to the Askey router
	/bin/wup_uci -q set pwd.subscriber.remote_ssh=1
	/bin/wup_uci commit

#	set firewall rules for Ananda ping and SSH 
	uci add firewall zone
	uci set firewall.@zone[-1].name="$WAN_ANANDA"
	uci set firewall.@zone[-1].network="$WAN_ANANDA"
	uci set firewall.@zone[-1].output='ACCEPT'
	uci set firewall.@zone[-1].input='ACCEPT'
	uci set firewall.@zone[-1].forward='ACCEPT'
	
	uci add firewall rule
	uci set firewall.@rule[-1].target='ACCEPT'
	uci set firewall.@rule[-1].proto='icmp'
	uci set firewall.@rule[-1].family='ipv4'
	uci set firewall.@rule[-1].icmp_type='echo-request'
	uci set firewall.@rule[-1].name='Allow-Ping-Ananda'
	uci set firewall.@rule[-1].src="$WAN_ANANDA"

	uci add firewall rule
	uci set firewall.@rule[-1].target='ACCEPT'
	uci set firewall.@rule[-1].proto='tcp udp'
	uci set firewall.@rule[-1].dest_port='22'
	uci set firewall.@rule[-1].family='ipv4'
	uci set firewall.@rule[-1].name='Allow-SSH-Ananda'
	uci set firewall.@rule[-1].src="$WAN_ANANDA"
	
	uci del_list firewall.zone_wan.network="$WAN_ANANDA"
#	uci add_list firewall.zone_wan.network="$WAN_ANANDA"
	uci commit firewall
	
	echo "Create interface/firewall for $WAN_ANANDA success."
	sync
fi

reboot