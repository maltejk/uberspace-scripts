#!/bin/bash
########################################################################
#
# 2010-10-01
# Christopher Hirschmann
# c.hirschmann@jonaspasche.com
#
########################################################################
#
#	This program is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 3 of the License, or
#	(at your option) any later version.
#
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
########################################################################
#
# This script will add a domain to an existing uberspace account and
# assign an IPv6 address to it, which will be recorded along with the
# domain and accountname in /etc/assigned-ipv6-addresses.
#
########################################################################

function ipv6off
{
	echo -e "Could not find \"/etc/httpd/conf.d/virtual6.${USERNAME}.conf\". IPv6 is probably not activated for ${USER}.";
	exit 1;
}

source  /usr/local/sbin/uberspace-account-common

checkforrootprivs;

USAGE="Usage:\n-h\t\tthis help message\n-d string\tdomain (mandatory)\n-i string\tIPv6 address (any notation that is valid for Apache configs is allowed)\n-u string\tusername (mandatory), may contain letters and numbers, must not begin with number or contain special characters\n";

if [ ! $# -ge 1 ];
then
	printf "No arguments given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

## Parse arguments
while getopts ":hd:i:u:" Option; do
	case $Option in
		h	)
				printf "$USAGE" $(basename $0);
				exit 0;
			;;
		d	)
				DOMAINGIVEN=1;
# FIXME: optionally check for valid domain
				DOMAIN=${OPTARG};
			;;
		i	)
# FIXME: check IPv6 address!
				HOSTIP6=${OPTARG};
			;;
		u	)
				checkusername ${OPTARG}
				USERNAMEGIVEN=1;
				USERNAME=${OPTARG};
			;;
		?	)
				printf "Invalid option or option without parameter: -${OPTARG}\n$USAGE" $(basename $0) >&2
				exit 2;
			;;
		*	)	# Default.
				printf "Unimplemented option: -${OPTARG}\n$USAGE" $(basename $0) >&2
				exit 2;
			;;
	esac
done

shift $(($OPTIND - 1))

if [ ! "$DOMAINGIVEN" ];
then
	printf "No domain given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

if [ ! "$USERNAMEGIVEN" ];
then
	printf "No username given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

VHOSTCONF="/etc/httpd/conf.d/virtual6.${USERNAME}.conf";
POOL="/etc/ipv6-address-pool/index.txt";

## this includes host specific variables
. /usr/local/sbin/uberspace-account-local-settings.sh;

if [ "${HOSTIP6}" == "" ]; then
	HOSTIP6=`grep ${USERNAME} ${POOL} | cut -d " " -f 1 | head -n 1;`
	if [ "${HOSTIP6}" == "" ]; then
		echo "Error. No IPv6 address was supplied, no IPv6 address could be found.";
		exit 2;
	fi
fi

## check wether domain is already assigned to host
if [ "`grep "ServerAlias ${DOMAIN} " $VHOSTCONF`" != "" ] ; then
	echo -e "Error: Domain already assigned.";
	exit 1;
fi

## add domain to VirtualHost
test -f $VHOSTCONF && sed -i -e 's/^ServerName '"${USERNAME}"'.'"$HOSTNAME"'$/&\nServerAlias '"$DOMAIN"' *.'"$DOMAIN"'/' $VHOSTCONF || ipv6off;

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

echo -e "OK Alles erledigt";
