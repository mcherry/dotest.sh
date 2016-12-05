#!/bin/bash
#
# Simple test script to inspect a host and see if it's up or working
#
# Mostly written by Mike Cherry <mcherry@inditech.org>
# With random code borrowed from the tubes

if [ "$1" == "" ]; then
	echo "Usage: $0 <ipaddress || hostname>"
	echo ""
	exit
fi

no_ip=0
do_ftp=0
do_ssh=0
do_ssl=0
do_http=0
do_vnc=0
dns_fail=0
dns_message=""
openssl_opts=""

function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

if ! valid_ip $1; then
	if [[ "$1" =~ [^a-zA-Z0-9] ]]; then
		host_name="$1"
		ip_address=`host $host_name|head -n1|awk '{print $4}'`

		if [ $ip_address == "found:" ]; then
			dns_fail=1

			dns_message="Not Found"
			host_name="$ip_address"
			no_ip=1
		fi

		openssl_opts="-servername $host_name"
	else
		echo "Invalid host: $1";
		exit;
	fi
else
	ip_address="$1"
	host_name=`host $ip_address|head -n1|awk '{print $5}'|sed -e 's/\.$//'`

	ip_test=`host $host_name|head -n1|awk '{print $5}'|sed -e 's/\.$//'`

	if [ "$ip_test" == "3(NXDOMAIN)" ]; then
		dns_fail=1

		dns_message="$ip_test"
		host_name="$ip_address"
	elif [ "$ip_test" == "2(SERVFAIL)" ]; then
		dns_fail=1

		dns_message="$ip_test"
		host_name="$ip_address"
	elif [ "$ip_test" == "5(REFUSED)" ]; then
		dns_fail=1

		dns_message="$ip_test"
		host_name="$ip_address"
	fi
fi

if [ "$dns_fail" == "1" ]; then
	echo "*** DNS LOOKUP FAILED WITH: $dns_message ***"
	echo

	if [ "$no_ip" == "1" ]; then
		exit;
	fi
fi

IFS=$'\n'
ping_test=`ping -c5 $host_name`
if [[ "$ping_test" =~ "0 received" ]]; then
	nmap_opts="-Pn"
fi

if [ ! "$nmap_opts" == "" ]; then
	echo "*** $host_name down or blocking ICMP ***"
else
	for a in $ping_test; do echo $a; done
fi
echo

nmap_test=`nmap $nmap_opts $host_name|grep -v "Starting Nmap\|Not shown"`
for a in $nmap_test; do
	if [[ "$a" == 21/tcp*open* ]]; then
		do_ftp="1"
	fi

	if [[ "$a" == 22/tcp*open* ]]; then
		do_ssh="1"
	fi

	if [[ "$a" == 222/tcp*open* ]]; then
		do_ssh="1"
	fi

	if [[ "$a" == 2222/tcp*open* ]]; then
		do_ssh="1"
	fi

	if [[ "$a" == 2022/tcp*open* ]]; then
		do_ssh="1"
	fi

	if [[ "$a" == 80/tcp*open* ]]; then
		do_http="1"
	fi

	if [[ "$a" == 443/tcp*open* ]]; then
		do_ssl="1"
	fi

	if [[ "$a" == 5900/tcp*open* ]]; then
		do_vnc="1"
	fi

	if [[ "$a" == 5901/tcp*open* ]]; then
		do_vnc="1"
	fi

	if [[ "$a" == 5902/tcp*open* ]]; then
		do_vnc="1"
	fi

	echo $a;
done
echo

if [ "$do_ftp" == "1" ]; then
	echo "FTP Verification:"
	timeout 5 nc $host_name 21 2> /dev/null
	echo
fi

IFS=$' '

if [ "$do_ssh" == "1" ]; then
	ssh_ports="22 222 2022 2222"
	echo "SSH Verification:"
	for a in $ssh_ports; do
		ssh_test=`echo |timeout 5 nc $host_name $a 2> /dev/null|grep -v mismatch`
		if [[ $ssh_test == SSH* ]]; then
			echo "Port $a $ssh_test"
		fi
	done
	echo
fi

if [ "$do_http" == "1" ]; then
	http_headers=`timeout 5 curl -s -I -L http://$host_name`
	http_content=`timeout 30 curl -s -L -X GET http://$host_name | html2text`

	if [ ! "$http_headers" == "" ]; then
		echo "HTTP headers:"
		echo "$http_headers"
		echo
	fi

	if [ ! "$http_content" == "" ]; then
		echo "HTTP content:"
		echo "$http_content"
		echo
	fi
fi

if [ "$do_vnc" == "1" ]; then
	vnc_ports="5900 5901 5902"
	echo "VNC Verification:"
	for a in $vnc_ports; do
		vnc_test=`echo |timeout 5 nc $host_name $a 2> /dev/null`
		if [[ $vnc_test == RFB* ]]; then
			echo "Port $a $vnc_test"
		fi
	done
	echo
fi


if [ "$do_ssl" == "1" ]; then
	echo "SSL Verification:"
	echo "x"|timeout 5 openssl s_client -connect $host_name:443 $openssl_opts|sed '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/{//!d}'|grep -v "BEGIN CERTIFICATE\|END CERTIFICATE"
	echo
fi

echo "Traceroute results:"
timeout 15 traceroute $host_name
echo
echo

echo "MTR results:"
timeout 15 mtr -c 5 -r $host_name
echo
