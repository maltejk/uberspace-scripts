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
# This script will create an uberspace account. It adds a system user,
# disables ftp login for that user, sets the quota, installs a SSH
# public key if one is supplied, generates a password for the user if no
# SSH public key is supplied, generates a MySQL password (no matter what),
# it will setup qmail / vmailmgr, and configure the apache webserver.
#
# Usage:
# -h	help message
# -u	username (mandatory)
# -k	optional public SSH key, enclosed with "
# -n    do not create user. Must already exist.
#
# If no SSH public key is supplied, a password will be generated.
# A password for MySQL will be generated and stored in the users .my.cnf
# either way.
#
########################################################################

source  /usr/local/sbin/uberspace-account-common
source  /usr/local/sbin/uberspace-account-local-settings.sh

checkforrootprivs;

USAGE="Usage:\n-h\t\tthis help message\n-u string\tusername (mandatory), may contain letters and numbers, must not begin with number or contain special characters\n-k \"string\"\toptional public SSH key, must be enclosed with \" to allow for spaces in the string\n\nIf no SSH public key is supplied, a password will be generated. A password for MySQL will be generated and stored in the users .my.cnf either way.\n";

if [ ! $# -ge 1 ];
then
	printf "No arguments given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

## Parse arguments
while getopts ":hu:k:" Option; do
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
		k	)
				SSHPUBKEYGIVEN=1;
				SSHPUBKEY=${OPTARG};
			;;
		n   )
				USERNAMEGIVEN=1;
				USERNAME=${OPTARG};
				NOCREATEUSER=1;
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

## dont trigger usercreation if NOCREATEUSER == 1
if [ "x$NOCREATEUSER" != "x1" ] ; then 

	if [ "`grep ^${USERNAME}: /etc/passwd`" != "" ] ; then
		echo -e "Ein Benutzer dieses Namens existiert bereits (passwd)";
		exit 1;
	fi

	if [ -e /home/${USERNAME} ] ; then
		echo -e "Ein Benutzer dieses Namens existiert bereits (home)";
		exit 1;
	fi

	if [ "`grep ^${USERNAME}: /etc/group`" != "" ] ; then
		echo -e "Eine Gruppe dieses Namens existiert bereits";
		exit 1;
	fi

	## add system account, group with same name, create ~, 
	useradd -U -m -s /bin/bash ${USERNAME};

	## set quota
	setquota -g ${USERNAME} 1024000 1126400 0 0 /;
	#setquota -g ${USERNAME} 10485760 11534336 0 0 /;

	## if SSH public key was supplied, install it
	if [ "${SSHPUBKEYGIVEN}" ] ; then
		mkdir -p -m 0700 /home/${USERNAME}/.ssh/;
		echo ${SSHPUBKEY} > /home/${USERNAME}/.ssh/authorized_keys;
		chmod 0600 /home/${USERNAME}/.ssh/authorized_keys;
		chown -R ${USERNAME}:${USERNAME} /home/${USERNAME};
		echo -e "Installed SSH public key.";
	else
		## if no SSH public key was supplied, generate and set password
		PASS=`apg -a 1 -M ncl -E \|1Il0O -n 1 -m 10 -x 10 -q -d 2>&1| sed "s/ .*//;"`;
		usermod --password "`echo $PASS | mkpasswd --stdin`" ${USERNAME}
		## save user's password to file.
		echo "Your password is $PASS" > /home/${USERNAME}/your_password.txt
		chown ${USERNAME}:${USERNAME} /home/${USERNAME}/your_password.txt; 
		chmod 600 /home/${USERNAME}/your_password.txt
	fi
fi ## NOCREATEUSER != 1

## generate password for MySQL in any case
MYSQLPASS=`/usr/bin/apg -a 1 -M ncl -E \|1Il0O -n 1 -m 20 -x 20 -q -d 2>&1| sed "s/ .*//;"`;

## setup qmail
if [ ! -d /home/${USERNAME}/Maildir ]; then
	/var/qmail/bin/maildirmake /home/${USERNAME}/Maildir;
	chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/Maildir;
fi

if [ ! -d /var/qmail/control/morercpthosts.d ]; then
	mkdir /var/qmail/control/morercpthosts.d;
fi
touch /var/qmail/control/morercpthosts.d/${USERNAME}.${HOSTNAME};

if [ ! -d /var/qmail/control/virtualdomains.d ]; then
	mkdir /var/qmail/control/virtualdomains.d;
fi
echo ${USERNAME} > /var/qmail/control/virtualdomains.d/${USERNAME}.${HOSTNAME};

## update qmail configuration
/usr/local/sbin/uberspace-update-qmail-config.sh

## create default aliases
echo ${USERNAME}          > /home/${USERNAME}/.qmail-postmaster
echo ${USERNAME}          > /home/${USERNAME}/.qmail-hostmaster
echo ${USERNAME}          > /home/${USERNAME}/.qmail-abuse
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.qmail-*

## this will trigger a script that will restart qmail-send within the next five minutes
touch /root/please_restart_qmail-send;

## prepare apache vhost

mkdir -m 0750 /var/www/virtual/${USERNAME};
chown ${USERNAME}:www-data /var/www/virtual/${USERNAME};

mkdir -m 0755 /var/www/virtual/${USERNAME}/html;
chown ${USERNAME}:${USERNAME} /var/www/virtual/${USERNAME}/html;

mkdir -m 0755 /var/www/virtual/${USERNAME}/cgi-bin;
chown ${USERNAME}:${USERNAME} /var/www/virtual/${USERNAME}/cgi-bin;

mkdir -m 0755 /var/www/virtual/${USERNAME}/fcgi-bin;
chown ${USERNAME}:${USERNAME} /var/www/virtual/${USERNAME}/fcgi-bin;

mkdir -m 0750 /var/www/virtual/${USERNAME}/logs;
chgrp ${USERNAME} /var/www/virtual/${USERNAME}/logs;

ln -s /var/www/virtual/${USERNAME}/* /home/${USERNAME};

mkdir -m 0700 /home/${USERNAME}/.etc;
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.etc;

{
cat <<EOF
## `date +%Y-%m-%d` $0 
PHPVERSION=5
EOF
} > /home/${USERNAME}/.etc/phpversion;
chown ${USERNAME}.${USERNAME} /home/${USERNAME}/.etc/phpversion;
chmod 0664 /home/${USERNAME}/.etc/phpversion;

{
cat <<EOF
#!/bin/bash
## `date +%Y-%m-%d` $0 
. ~/.etc/phpversion
export PHPRC="/home/${USERNAME}/.etc"
exec /package/host/localhost/php-\${PHPVERSION}/bin/php-cgi
EOF
} > /var/www/virtual/${USERNAME}/fcgi-bin/php-fcgi-starter;

chown ${USERNAME}.${USERNAME} /var/www/virtual/${USERNAME}/fcgi-bin/php-fcgi-starter;
chmod 755 /var/www/virtual/${USERNAME}/fcgi-bin/php-fcgi-starter;

{
cat <<EOF
## `date +%Y-%m-%d` $0 $@
<Directory /var/www/virtual/${USERNAME}>
AllowOverride All
Options +Includes
</Directory>

<VirtualHost ${HOSTIP}:80>
ServerName ${USERNAME}.${HOSTNAME}
ServerAdmin $SERVERADMIN
SuexecUserGroup ${USERNAME} ${USERNAME}
DocumentRoot /var/www/virtual/${USERNAME}/html
ScriptAlias /cgi-bin /var/www/virtual/${USERNAME}/cgi-bin
ScriptAlias /fcgi-bin /var/www/virtual/${USERNAME}/fcgi-bin
Include /etc/apache2/dyncontent

RewriteEngine On

# PHP expects a "HTTP_AUTHORIZATION" header to correctly provide PHP_AUTH_USER and PHP_AUTH_PW
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

# If there is a host-specific pseudo-DocumentRoot, use it instead of the default one
RewriteCond %{REQUEST_URI} !^/f?cgi-bin/
RewriteCond /var/www/virtual/${USERNAME}/%{HTTP_HOST} -d
RewriteRule (.*) /var/www/virtual/${USERNAME}/%{HTTP_HOST}/\$1

</VirtualHost>
EOF
} > /etc/apache2/sites-available/virtual.${USERNAME}.conf
chmod 640 /etc/apache2/sites-available/virtual.${USERNAME}.conf;

# enable vhost
a2ensite virtual.${USERNAME}.conf

{
cat <<EOF
## `date +%Y-%m-%d` $0 $@
<VirtualHost ${HOSTIP}:443>
ServerName ${USERNAME}.${HOSTNAME}
ServerAdmin $SERVERADMIN
SuexecUserGroup ${USERNAME} ${USERNAME}
DocumentRoot /var/www/virtual/${USERNAME}/html
ScriptAlias /cgi-bin /var/www/virtual/${USERNAME}/cgi-bin
ScriptAlias /fcgi-bin /var/www/virtual/${USERNAME}/fcgi-bin
Include /etc/apache2/ssl-uberspace
Include /etc/apache2/dyncontent

RewriteEngine On

# PHP expects a "HTTP_AUTHORIZATION" header to correctly provide PHP_AUTH_USER and PHP_AUTH_PW
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

</VirtualHost>
EOF
} > /etc/apache2/sites-available/ssl.${USERNAME}.conf
chmod 640 /etc/apache2/sites-available/ssl.${USERNAME}.conf;

# enable ssl vhost. not nao, we have no ssl cert.
#a2ensite ssl.${USERNAME}.conf

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

# no setup IPv6
#/usr/local/sbin/uberspace-account-6on.sh -u ${USERNAME}

## we need to return the ipv6-address 
#POOL="/etc/ipv6-address-pool/index.txt";
#BURNEDADDRESS=`grep -e " ${USERNAME}$" ${POOL} | cut -d " " -f 1`;

#if [ "$BURNEDADDRESS" == "" ]; then
#  echo -e "OK $PASS";
#else 
#  echo -e "OK $BURNEDADDRESS $PASS";
#fi

## create user account and database in MySQL 
mysql -u root -e "CREATE DATABASE \`${USERNAME}\`;";
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${USERNAME}\`.* TO \`${USERNAME}\`@\`localhost\` IDENTIFIED BY '$MYSQLPASS';";
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${USERNAME}\_%\`.* TO \`${USERNAME}\`@\`localhost\` IDENTIFIED BY '$MYSQLPASS';";

chgrp ${USERNAME} /var/lib/mysql/${USERNAME};
chmod g+s /var/lib/mysql/${USERNAME};

{
cat <<EOF
## `date +%Y-%m-%d` $0 $@
[client]
# Do NOT change your password here! It is meant to *access* your MySQL databases,
# not to *set* the password. 
password=${MYSQLPASS}
port=3306
user=${USERNAME}
socket=/var/run/mysqld/mysqld.sock
EOF
} > /home/${USERNAME}/.my.cnf;
chmod 0600 /home/${USERNAME}/.my.cnf;
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.my.cnf;

echo -e "Hello.\nThis is ${0} on ${HOSTNAME}.\nI've just created a new uberspace account named ${USERNAME}.\nRegards,\n${0}" | mail -s "uberspace account created" $SERVERADMIN;

exit 0;
