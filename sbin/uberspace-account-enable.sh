#!/bin/sh
########################################################################
#
# 2011-21-21
# Andreas Beintken
# abeintken@jonaspasche.com
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
# This script will enable an Uberspace (http only).
#
########################################################################

source  /usr/local/sbin/uberspace-account-common

checkforrootprivs;

USAGE="Usage:\n-h\t\tthis help message\n-u string\tusername\n";

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

VHOSTCONF="/etc/httpd/conf.d/virtual.${USERNAME}.conf";

VHOSTCOUNT=`grep -c "^<VirtualHost" $VHOSTCONF`
VHOSTDISABLED=`sed -n '/^DocumentRoot/{n;p;}' $VHOSTCONF | grep -c "Include /etc/httpd/conf/uberspace-disabled.conf"`
if [ $VHOSTDISABLED = $VHOSTCOUNT ] ; then
  perl -pi -e "s/^Include \/etc\/httpd\/conf\/uberspace-disabled.conf\n//g" $VHOSTCONF;
  ## this triggers a script that will restart httpd within the next five minutes
  touch /root/please_restart_httpd;
  echo -e "OK Alles erledigt"
  exit 0;
elif [ $VHOSTDISABLED = 0 ] ; then
  echo -e "OK Uberspace ist derzeit aktiv"
  exit 0;
else
  perl -pi -e "s/^Include \/etc\/httpd\/conf\/uberspace-disabled.conf\n//g;" $VHOSTCONF;
  echo -e "OK Alles erledigt (gefundene VirtualHosts: $VHOSTCOUNT, davon waren deaktiviert: $VHOSTDISABLED)"
  ## this triggers a script that will restart httpd within the next five minutes
  touch /root/please_restart_httpd;
  exit 0;
fi

## if the following file exists, asume that IPv6 is enabled for that account and call uberspace-account-add-domain6.sh
#if [ -e /etc/httpd/conf.d/virtual6.${USERNAME}.conf ]; then
#	/usr/local/sbin/uberspace-account-add-domain6.sh -u ${USERNAME} -d ${DOMAIN}
#fi

