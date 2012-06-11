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
# This script will remove a domain assigned to an IPv6 address from an
# existing uberspace account and mark the IPv6 address as disused in
# /etc/assigned-ipv6-addresses.
#
########################################################################

source  /usr/local/sbin/uberspace-account-common

checkforrootprivs;

USAGE="Usage:\n-h\t\tthis help message\n-d string\tdomain (mandatory)\n-u string\tusername (mandatory), may contain letters and numbers, must not begin with number or contain special characters\n";

if [ ! $# -ge 1 ];
then
	printf "No arguments given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

## Parse arguments
while getopts ":hd:u:" Option; do
	case $Option in
		h	)
				printf "$USAGE" $(basename $0);
				exit 0;
			;;
		d	)
				DOMAINGIVEN=1;
				DOMAIN=${OPTARG};
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

VHOSTCONF="/etc/apache2/vhosts.d/virtual6.${USERNAME}.conf";
DOMCONF="/etc/apache2/vhosts.d/xaliasdomain6.${USERNAME}-${DOMAIN}.conf";

## remove domain from VirtualHost (supporting both the old "www.$DOMAIN" and the new "*.$DOMAIN" syntax
grep -qe "^ServerAlias $DOMAIN " $VHOSTCONF && sed -i -e '/^ServerAlias '"$DOMAIN"' .*/d' $VHOSTCONF || notinconfig

## remove domain specific config
## (for newer domains there won't be such a config)
test -f $DOMCONF && rm $DOMCONF # || noconfig;

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

echo -e "OK Alles erledigt";
