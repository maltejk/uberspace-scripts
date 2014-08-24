#!/bin/sh
########################################################################
# 2012-04-15 Christopher Hirschmann c.hirschmann@jonaspasche.com
########################################################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
########################################################################
#
# This script will remove a domain from an existing uberspace account.
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

VHOSTCONF="/etc/httpd/conf.d/virtual.${USERNAME}.conf";
DOMCONF="/etc/httpd/conf.d/xaliasdomain.${USERNAME}-$DOMAIN.conf";

## remove domain from VirtualHost (supporting both the old "www.$DOMAIN" and the new "*.$DOMAIN" syntax
## FIXME: check if this works with CentOS 6 Uberspace Hosts and their single config for IPv4 and IPv6
grep -qe "^ServerAlias $DOMAIN " $VHOSTCONF && sed -i -e '/^ServerAlias '"$DOMAIN"' .*/d' $VHOSTCONF || notinconfig

## remove domain specific config
## (for newer domains there won't be such a config)
test -f $DOMCONF && rm $DOMCONF # || noconfig;

## remove domain from morercpthosts
if [ -f /var/qmail/control/morercpthosts.d/${DOMAIN} ] ; then
  rm /var/qmail/control/morercpthosts.d/${DOMAIN}
fi

## remove domain from virtualdomains
if [ -f /var/qmail/control/virtualdomains.d/${DOMAIN} ] ; then
  rm /var/qmail/control/virtualdomains.d/${DOMAIN}
fi

## update the qmail configuration
/usr/local/sbin/uberspace-update-qmail-config.sh

## this will tell qmail-send to re-read it's config
/command/svc -h /service/qmail-send;

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

## if the following file exists, this host should be a CentOS 5 Uberspace host (on CentOS 6 IPv6 isn't configured in separate files anymore), so call uberspace-account-del-domain6.sh
if [ -e /etc/httpd/conf.d/virtual6.${USERNAME}.conf ]; then
	/usr/local/sbin/uberspace-account-del-domain6.sh -u ${USERNAME} -d ${DOMAIN}
fi

echo -e "OK Alles erledigt";
