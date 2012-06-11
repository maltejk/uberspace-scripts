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
# This script will add a domain to an existing uberspace account.
#
########################################################################

source  /usr/local/sbin/uberspace-account-common

checkforrootprivs;

USAGE="Usage:\n-h\t\tthis help message\n-d string\tdomain (mandatory)\n-u string\tusername (mandatory), may contain letters and numbers, must not begin with number or contain special characters\n-e string\textension (optional), map domain to user-extension in virtualdomains\n";

if [ ! $# -ge 1 ];
then
	printf "No arguments given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

## Parse arguments
while getopts ":hd:u:e:" Option; do
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
		u	)
				checkusername ${OPTARG}
				USERNAMEGIVEN=1;
				USERNAME=${OPTARG};
			;;
		e	)
				EXTENSIONGIVEN=1;
				EXTENSION=${OPTARG};
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

## this includes host specific variables
. /usr/local/sbin/uberspace-account-local-settings.sh;

## check wether domain is already assigned to host
if [ "`grep "ServerAlias ${DOMAIN} " $VHOSTCONF`" != "" ] ; then
	echo -e "Error: Domain already assigned.";
	exit 1;
fi

## add domain to VirtualHost
sed -i -e 's/^ServerName '"${USERNAME}"'.'"$HOSTNAME"'$/&\nServerAlias '"$DOMAIN"' *.'"$DOMAIN"'/' $VHOSTCONF;

## setup qmail
if [ ! -d /var/qmail/control/morercpthosts.d ]; then
	mkdir /var/qmail/control/morercpthosts.d;
fi
touch /var/qmail/control/morercpthosts.d/${DOMAIN};

if [ ! -d /var/qmail/control/virtualdomains.d ]; then
	mkdir /var/qmail/control/virtualdomains.d;
fi
if [ ${EXTENSION} ] ; then
  echo ${USERNAME}-${EXTENSION} > /var/qmail/control/virtualdomains.d/${DOMAIN};
else
  echo ${USERNAME} > /var/qmail/control/virtualdomains.d/${DOMAIN};
fi

## update the qmail configuration
/usr/local/sbin/uberspace-update-qmail-config.sh

## this will trigger a script that will restart qmail-send within the next five minutes
touch /root/please_restart_qmail-send;

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

## if the following file exists, asume that IPv6 is enabled for that account and call uberspace-account-add-domain6.sh
if [ -e /etc/httpd/conf.d/virtual6.${USERNAME}.conf ]; then
	/usr/local/sbin/uberspace-account-add-domain6.sh -u ${USERNAME} -d ${DOMAIN}
fi

echo -e "OK Alles erledigt";
