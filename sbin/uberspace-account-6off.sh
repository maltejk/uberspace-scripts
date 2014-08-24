#!/bin/sh
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
# This script will disable IPv6 for a given user account, remove all
# related configuration and mark the IPv6 address as disused.
#
########################################################################

source  /usr/local/sbin/uberspace-account-common

checkforrootprivs;

USAGE="Usage:\n-h\t\tthis help message\n-u string\tusername (mandatory), may contain letters and numbers, must not begin with number or contain special characters\n";

if [ ! $# -ge 1 ];
then
	printf "No arguments given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

## Parse arguments
while getopts ":hu:" Option; do
	case $Option in
		h	)
				printf "$USAGE" $(basename $0);
				exit 0;
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

if [ ! "$USERNAMEGIVEN" ];
then
	printf "No username given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

POOL="/etc/ipv6-address-pool/index.txt";

## check wether IPv6 was activated for this user
if [ ! -e /etc/httpd/conf.d/virtual6.${USERNAME}.conf ]; then
    echo "Error: /etc/httpd/conf.d/virtual6.${USERNAME}.conf doesn't exist.";
    exit 1;
fi

# check if pound is used
if ! [ "`grep SSLFRONTEND=pound /usr/local/sbin/uberspace-account-local-settings.sh`" ]; then
  if [ ! -e /etc/httpd/conf.d/ssl6.${USERNAME}.conf ]; then
      echo "Error: /etc/httpd/conf.d/ssl6.${USERNAME}.conf doesn't exist.";
      exit 1;
  fi
fi

## determine which IPv6 address was assigned to this user
BURNEDADDRESS=`grep -e " ${USERNAME}$" ${POOL} | cut -d " " -f 1`;

if [ "$BURNEDADDRESS" == "" ]; then
    echo "Error: Can't find the IPv6 address that was assigned to this user.";
    exit 1;
fi

## mark IPv6 address as disused, but retain information to which user it used to belong
#perl -spi -e 's!${BURNEDADDRESS} ${USERNAME} *!${FREEADDRESS} ${USERNAME} deallocated!' ${POOL};
sed -i -e 's/^\('"$BURNEDADDRESS"'\) '"${USERNAME}"'$/& deallocated/' ${POOL};

## remove all IPv6-related apache configs
rm -f /etc/httpd/conf.d/xaliasdomain6.${USERNAME}-*.conf;
rm -f /etc/httpd/conf.d/virtual6.${USERNAME}.conf;
rm -f /etc/httpd/conf.d/ssl6.${USERNAME}.conf;

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;
