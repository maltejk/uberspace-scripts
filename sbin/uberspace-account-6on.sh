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
# This script will assign an IPv6 address to a given user account.
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

## check if config already exist
if [ -e "/etc/httpd/conf.d/virtual6.${USERNAME}.conf" ]; then
        echo -e "IPv6 configuration virtual6.${USERNAME}.conf already exists for this account.";
        exit 1;
fi
if [ -e "/etc/httpd/conf.d/ssl6.${USERNAME}.conf" ]; then
        echo -e "IPv6 configuration ssl6.${USERNAME}.conf already exists for this account.";
        exit 1;
fi


POOL="/etc/ipv6-address-pool/index.txt";

## this includes host specific variables
. /usr/local/sbin/uberspace-account-local-settings.sh;

# get IPv6 address from pool
FREEADDRESS=`grep -e " free$" ${POOL} | head -n 1 | cut -d " " -f 1`;

#perl -spi -e 's!${FREEADDRESS} free *!${FREEADDRESS} ${USERNAME}!' ${POOL};
sed -i -e 's/^\('"$FREEADDRESS"'\) free$/\1 '"${USERNAME}"'/' ${POOL};

HOSTIP6=${FREEADDRESS};

if [ "${HOSTIP6}" == "" ]; then
	echo -e "Could not get an IPv6 address.";
	exit 1;
fi

## add IPv6 address to apache vhost
{
cat <<EOF
## `date +%Y-%m-%d` $0 $@
NameVirtualHost [${HOSTIP6}]:80

<Directory /var/www/virtual/${USERNAME}>
AllowOverride All
Options +Includes
</Directory>

<VirtualHost [${HOSTIP6}]:80>
ServerName ${USERNAME}.${HOSTNAME}
ServerAdmin $SERVERADMIN
SuexecUserGroup ${USERNAME} ${USERNAME}
DocumentRoot /var/www/virtual/${USERNAME}/html
ScriptAlias /cgi-bin /var/www/virtual/${USERNAME}/cgi-bin
ScriptAlias /fcgi-bin /var/www/virtual/${USERNAME}/fcgi-bin
Include /etc/httpd/conf/dyncontent.conf

RewriteEngine On

# PHP expects a "HTTP_AUTHORIZATION" header to correctly provide PHP_AUTH_USER and PHP_AUTH_PW
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

# If there is a host-specific pseudo-DocumentRoot, use it instead of the default one
RewriteCond %{REQUEST_URI} !^/f?cgi-bin/
RewriteCond /var/www/virtual/${USERNAME}/%{HTTP_HOST} -d
RewriteRule (.*) /var/www/virtual/${USERNAME}/%{HTTP_HOST}/\$1

</VirtualHost>
EOF
} > /etc/httpd/conf.d/virtual6.${USERNAME}.conf
chmod 640 /etc/httpd/conf.d/virtual6.${USERNAME}.conf;

{
cat <<EOF
## `date +%Y-%m-%d` $0 $@
<VirtualHost [${HOSTIP6}]:443>
ServerName ${USERNAME}.${HOSTNAME}
ServerAdmin $SERVERADMIN
SuexecUserGroup ${USERNAME} ${USERNAME}
DocumentRoot /var/www/virtual/${USERNAME}/html
ScriptAlias /cgi-bin /var/www/virtual/${USERNAME}/cgi-bin
ScriptAlias /fcgi-bin /var/www/virtual/${USERNAME}/fcgi-bin
Include /etc/httpd/conf/ssl-uberspace.conf
Include /etc/httpd/conf/dyncontent.conf

RewriteEngine On

# PHP expects a "HTTP_AUTHORIZATION" header to correctly provide PHP_AUTH_USER and PHP_AUTH_PW
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

</VirtualHost>
EOF
} > /etc/httpd/conf.d/ssl6.${USERNAME}.conf
chmod 640 /etc/httpd/conf.d/ssl6.${USERNAME}.conf;

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

## find out wether this user already has additional domains and configure them for IPv6
DOMAINS=`grep -e "^ServerAlias " /etc/httpd/conf.d/virtual.${USERNAME}.conf | cut -d " " -f 2`;
for DOMAIN in $DOMAINS; do
    /usr/local/sbin/uberspace-account-add-domain6.sh -u ${USERNAME} -d ${DOMAIN} -i ${HOSTIP6}; 
done
