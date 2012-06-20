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
# This script will delete an uberspace account.
#
# …
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

if [ "`grep ^${USERNAME}: /etc/passwd`" = "" ] ; then
  echo "Ein Benutzer dieses Namens ist nicht vorhanden (laut /etc/passwd)!"
  exit 1;
fi

# make sure the user isn't logged in any more and kill all processes belonging to this user
killall -u ${USERNAME}

# remove apache configs for IPv6
# if done this way the IPv6 address will be marked as deallocated
/usr/local/sbin/uberspace-account-6off.sh -u ${USERNAME};

# IPv4 apache configs can be removed without further ado
rm -f /etc/httpd/conf.d/xaliasdomain.${USERNAME}-*.conf
rm -f /etc/httpd/conf.d/virtual.${USERNAME}.conf
rm -f /etc/httpd/conf.d/ssl.${USERNAME}.conf

# make sure that the webspace can be deleted in the next step
# (this is only needed for older uberspaces which have an immutable starter)
for STARTER in /var/www/virtual/${USERNAME}/fcgi-bin/php* ; do
  chattr -i $STARTER
done

# remove the webspace
rm -rf /var/www/virtual/${USERNAME}

# this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

# remove MySQL databases

for DB in `find /var/lib/mysql/ -maxdepth 1 -type d -name ${USERNAME}_\* | cut -d "/" -f 5`; do
  mysql -u root -e "DROP DATABASE \`$DB\`;" 2>/root/uberspace-account-delete.${USERNAME}.$DB.DROP.err
done

if [ -d /var/lib/mysql/${USERNAME} ] ; then
  mysql -u root -e "DROP DATABASE \`${USERNAME}\`;" 2>/root/uberspace-account-delete.${USERNAME}.DROP.err
fi

mysql -u root -e "DROP USER \`${USERNAME}\`@\`localhost\`;" 2>/root/uberspace-account-delete.mysql.${USERNAME}.$DB.DROPUSER.err

# remove domain from qmail
rm /var/qmail/control/morercpthosts.d/${USERNAME}.${HOSTNAME};
rm /var/qmail/control/virtualdomains.d/${USERNAME}.${HOSTNAME};
#FIXME: domains added bei uberspace-account-add-domain.sh must be removed as well

# update qmail configuration
/usr/local/sbin/uberspace-update-qmail-config.sh

# this will trigger a script that will restart qmail-send within the next five minutes
touch /root/please_restart_qmail-send;

# remove system user
/usr/sbin/userdel -r ${USERNAME}

# remove local backups
rm -rf /backup/${USERNAME}

echo "OK Account wurde entfernt"

echo -e "Hello.\nThis is ${0} on ${HOSTNAME}.\nI've just deleted an uberspace account named ${USERNAME}.\nRegards,\n${0}" | mail -s "uberspace account deleted" mail@jonaspasche.com;

exit 0;
