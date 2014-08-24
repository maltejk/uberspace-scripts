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
#########################################################################
#
# This script will disable a Uberspace.
#
#########################################################################

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


USERHOME="/home/${USERNAME}";
USERWEBHOME="/var/www/virtual/${USERNAME}";
 
if (`test -d ${USERHOME}` && `test -d ${USERWEBHOME}`) ; then 
  DISABLED=

  # cron
  crontab -u ${USERNAME} -l > ${USERHOME}/.crontab-disabled
  crontab -u ${USERNAME} -r

  # ~/service
  if (`test -d /etc/run-svscan-${USERNAME}`) ; then
    /usr/local/bin/svc -d /service/svscan-${USERNAME}
    sleep 3
    touch /etc/run-svscan-${USERNAME}/down
  fi

  # killall jobs from user
  pkill -u ${USERNAME}


  # homedir
  if [ "`stat --printf=%U ${USERHOME}`" = "${USERNAME}" ] ; then
    chown root.root ${USERHOME}
  else
    DISABLED=1
  fi
  chmod 700 ${USERHOME}

  # webdir
  if [ "`stat --printf=%U ${USERWEBHOME}`" = "${USERNAME}" ] ; then
    chown root.root ${USERWEBHOME}
  else
    DISABLED=1
  fi
  chmod 700 ${USERWEBHOME}


  # just to be safe
  pkill -9 -u ${USERNAME}

  if [ $DISABLED ] ; then
    echo -e "OK Uberspace wurde bereits deaktiviert"
    exit 0;
  else 
    echo -e "OK Uberspace ist deaktiviert"
    exit 0;
  fi
else
  echo "No userdir ${USERHOME} or userwebdir ${USERWEBHOME} found!"
  exit 2;
fi

