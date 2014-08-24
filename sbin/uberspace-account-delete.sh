#!/bin/sh
########################################################################
# 2014-03-07 Christopher Hirschmann c.hirschmann@jonaspasche.com
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
# This script will delete an uberspace account.
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

## this includes host specific variables
. /usr/local/sbin/uberspace-account-local-settings.sh;

if [ "`grep ^${USERNAME}: /etc/passwd`" = "" ] ; then
  echo "Ein Benutzer dieses Namens ist nicht vorhanden (laut /etc/passwd)!"
  exit 1;
fi

# stop and remove svscan process for a local ~/service directory
SVSCANSYMLINK=/service/svscan-${USERNAME}
if [ -e ${SVSCANSYMLINK} ] ; then
  OLDDIR=`pwd`
  cd ${SVSCANSYMLINK}
  rm -f ${SVSCANSYMLINK}
  /command/svc -dx .
  cd ${OLDDIR}
  # we need to wait a moment to allow svscan processes to exit
  sleep 1
  rm -rf /etc/run-svscan-${USERNAME}
fi

# close all ports that have been opened for this user
if [ -d /etc/sysconfig/ports ] ; then
  /usr/local/sbin/uberspace-account-close-port -u ${USERNAME};
fi

# make sure the user isn't logged in any more and kill all processes belonging to this user
killall -9 -u ${USERNAME}

## determine which IPv6 address was assigned to this user
BURNEDADDRESS=`grep -e " ${USERNAME}$" ${POOL} | cut -d " " -f 1`;

## if there is an IPv6 address, deallocate it
if [ "$BURNEDADDRESS" != "" ]; then
  ## mark IPv6 address as disused, but retain information to which user it used to belong
  sed -i -e 's/^\('"$BURNEDADDRESS"'\) '"${USERNAME}"'$/& deallocated/' ${POOL};
fi

# these apache configs can be removed without further ado
# note that some of these aren't created anymore with current versions of uberspace-account-create.sh etc.
rm -f /etc/httpd/conf.d/xaliasdomain.${USERNAME}-*.conf;
rm -f /etc/httpd/conf.d/virtual.${USERNAME}.conf;
rm -f /etc/httpd/conf.d/virtual6.${USERNAME}.conf;
rm -f /etc/httpd/conf.d/ssl.${USERNAME}.conf;
rm -f /etc/httpd/conf.d/ssl6.${USERNAME}.conf;
rm -f /etc/httpd/conf.d/wildcard.${USERNAME}.conf;

if [ -d /etc/httpd/domains.d ] ; then
  find /etc/httpd/domains.d/ -maxdepth 1 -type f -user ${USERNAME} -exec rm -f {} \;
fi

# make sure that the webspace can be deleted in the next step
# (this is only needed for older uberspaces which have an immutable starter)
chattr -R -i /var/www/virtual/${USERNAME}/fcgi-bin

# remove the separate user directory in /readonly
rm -rf /readonly/${USERNAME}

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
find /var/qmail/control/{morercpthosts.d,virtualdomains.d}/ -maxdepth 1 -type f -user ${USERNAME} -exec rm -f {} \;

# update qmail configuration
/usr/local/sbin/uberspace-update-qmail-config.sh

## this will tell qmail-send to re-read it's config
/command/svc -h /service/qmail-send;

# remove user specific pound configuration
MUSTRESTARTPOUND=0;
if [ -e /etc/pound.d/user-backends/${USERNAME} ];
then
	rm -f /etc/pound.d/user-backends/${USERNAME};
	/usr/local/sbin/uberspace-concat-userbackends;
	MUSTRESTARTPOUND=1;
fi
if [ -e /etc/pound.d/user-backends-http/${USERNAME} ];
then
	rm -f /etc/pound.d/user-backends-http/${USERNAME};
	/usr/local/sbin/uberspace-concat-userbackends;
	MUSTRESTARTPOUND=1;
fi
if [ -e /etc/pound.d/user-backends-https/${USERNAME} ];
then
	rm -f /etc/pound.d/user-backends-https/${USERNAME};
	/usr/local/sbin/uberspace-concat-userbackends;
	MUSTRESTARTPOUND=1;
fi
if [ -e /etc/pound.d/user-certificates/${USERNAME} ];
then
	rm -f /etc/pound.d/user-certificates/${USERNAME};
	/usr/local/sbin/uberspace-concat-usercertificates;
	MUSTRESTARTPOUND=1;
fi
if [ "$MUSTRESTARTPOUND" == "1" ];
then
	/usr/local/sbin/uberspace-reload-pound;
fi

## on helium.uberspace.de we had vsftpd installed, but didn't use it for uberspace
## on all newer uberspace hosts vsftpd may have been installed, but was never used
if [ "${HOSTNAME}" == "helium.uberspace.de" ]; then
# remove FTP configuration
    rm -f /etc/vsftpd/userconf/${USERNAME}
    removefromftpusers;
    removefromftpuser_list;
fi

# remove system user
AUTHKEYS2="/home/${USERNAME}/.ssh/authorized_keys2"
if [ -e ${AUTHKEYS2} ] ; then
  chattr -i ${AUTHKEYS2};
fi
/usr/sbin/userdel -r ${USERNAME}

echo "OK Account wurde entfernt"

echo -e "Hello.\nThis is ${0} on ${HOSTNAME}.\nI've just deleted an uberspace account named ${USERNAME}.\nRegards,\n${0}" | mail -s "uberspace account deleted" mail@jonaspasche.com;
