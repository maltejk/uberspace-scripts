#!/bin/sh
########################################################################
# 2014-07-27 Christopher Hirschmann c.hirschmann@jonaspasche.com
########################################################################
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#
########################################################################
#
# This script will create an uberspace account. It adds a system user,
# sets the group quota, installs a SSH public key if one is supplied,
# configures the apache webserver (both for IPv4 and IPv6), generates
# a MySQL password and it will setup qmail / vmailmgr.
# A SSH password is generated if no SSH public key is supplied.
# The unique IPv6 address that is assigned to the account is echoed at
# the end.
#
# Usage:
# -h	help message
# -u	username (mandatory)
# -k	optional public SSH key, enclosed with "
#
# If no SSH public key is supplied, a password will be generated.
# A password for MySQL will be generated and stored in the users .my.cnf
# either way.
#
########################################################################

source /usr/local/sbin/uberspace-account-common

checkforrootprivs;

USAGE="Usage:\n-h\t\tthis help message\n-u string\tusername (mandatory), may contain letters and numbers, must not begin with number or contain special characters\n-k \"string\"\toptional public SSH key, must be enclosed with \" to allow for spaces in the string\n\nIf no SSH public key is supplied, a password will be generated. A password for MySQL will be generated and stored in the users .my.cnf either way.\n";

if [ ! $# -ge 1 ];
then
	printf "No arguments given.\n$USAGE" $(basename $0) >&2
	exit 2;
fi

## Parse arguments
while getopts ":hu:k:" Option;
do
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

if [ "`grep ^${USERNAME}: /etc/passwd`" != "" ] ;
then
	echo -e "Ein Benutzer dieses Namens existiert bereits (passwd)";
	exit 1;
fi

if [ -e /home/${USERNAME} ] ;
then
	echo -e "Ein Benutzer dieses Namens existiert bereits (home)";
	exit 1;
fi

if [ "`grep ^${USERNAME}: /etc/group`" != "" ] ;
then
	echo -e "Eine Gruppe dieses Namens existiert bereits";
	exit 1;
fi

# get IPv6 address from pool
FREEADDRESS=`grep -e " free$" ${POOL} | head -n 1 | cut -d " " -f 1`;

# mark address as used
sed -i -e 's/^\('"$FREEADDRESS"'\) free$/\1 '"${USERNAME}"'/' ${POOL};

HOSTIP6=${FREEADDRESS};

if [ "${HOSTIP6}" == "" ];
then
	echo -e "Could not get an IPv6 address.";
	exit 1;
fi

## add system account
/usr/sbin/useradd ${USERNAME};

mkdir -p /readonly/${USERNAME}
chown root:${USERNAME} /readonly/${USERNAME}
chmod 750 /readonly/${USERNAME}

## on helium.uberspace.de we had vsftpd installed, but didn't use it for uberspace
## on all newer uberspace hosts vsftpd may have been installed, but was never used
if [ "${HOSTNAME}" == "helium.uberspace.de" ];
then
	addtoftpusers;
	addtoftpuser_list;
fi

## set quota
/usr/sbin/setquota -g ${USERNAME} 10485760 11534336 0 0 /;

if ! [ "`df | grep /mnt/non_drbd`" = "" ] ;
then
	/usr/sbin/setquota -g ${USERNAME} 204800 225280 25000 25000 /mnt/non_drbd/;
fi


## if SSH public key was supplied, install it
if [ "${SSHPUBKEYGIVEN}" ] ;
then
	mkdir -p -m 0700 /home/${USERNAME}/.ssh/;
	echo ${SSHPUBKEY} > /home/${USERNAME}/.ssh/authorized_keys;
	chmod 0600 /home/${USERNAME}/.ssh/authorized_keys;
	echo ${SSHPUBKEY} > /home/${USERNAME}/.ssh/authorized_keys2;
	chmod 0600 /home/${USERNAME}/.ssh/authorized_keys2;
	chown -R ${USERNAME}:${USERNAME} /home/${USERNAME};
	chattr +i /home/${USERNAME}/.ssh/authorized_keys2;
	echo -e "Installed SSH public key.";
else
## if no SSH public key was supplied, generate and set password
	PASS=`/usr/bin/apg -M ncl -E \|1Il0O -r /usr/share/dict/words -n 1 -m 6 -x 10 -q -d 2>&1| sed "s/ .*//;"`;
	echo $PASS | /usr/bin/passwd --stdin ${USERNAME} 2>&1 | grep -v "Changing password for user" | grep -v "passwd: all authentication tokens updated successfully";
fi

## generate password for MySQL in any case
MYSQLPASS=`/usr/bin/apg -M ncl -E \|1Il0O -r /usr/share/dict/words -n 1 -m 12 -x 20 -q -d 2>&1| sed "s/ .*//;"`;

# create own ~/etc for every user
mkdir -m 0700 /home/${USERNAME}/etc
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/etc

# create own TMPDIR for every user
mkdir -m 0700 /home/${USERNAME}/tmp
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/tmp

# create logrotate configuration (logrotate runs as root)
mkdir -p /readonly/${USERNAME}/etc
chown root:${USERNAME} /readonly/${USERNAME}/etc
chmod 750 /readonly/${USERNAME}/etc
cat > /readonly/${USERNAME}/etc/logrotate.conf <<__EOF__
/readonly/${USERNAME}/logs/*_log {
  rotate 4
  weekly
  compress
}
__EOF__
chmod 640 /readonly/${USERNAME}/etc/logrotate.conf
chown root:${USERNAME} /readonly/${USERNAME}/etc/logrotate.conf

# convenience symlink to ~/etc
pushd /home/${USERNAME}/etc
ln -s ../../../readonly/${USERNAME}/etc/logrotate.conf logrotate.conf
popd

## setup qmail
if [ ! -d /home/${USERNAME}/Maildir ];
then
	/var/qmail/bin/maildirmake /home/${USERNAME}/Maildir;
	chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/Maildir;
fi

touch /var/qmail/control/morercpthosts.d/${USERNAME}.${HOSTNAME};
chown ${USERNAME} /var/qmail/control/morercpthosts.d/${USERNAME}.${HOSTNAME};

echo ${USERNAME} > /var/qmail/control/virtualdomains.d/${USERNAME}.${HOSTNAME};
chown ${USERNAME} /var/qmail/control/virtualdomains.d/${USERNAME}.${HOSTNAME};

## update qmail configuration
/usr/local/sbin/uberspace-update-qmail-config.sh

## create default aliases
echo ${USERNAME}          > /home/${USERNAME}/.qmail-postmaster
echo ${USERNAME}          > /home/${USERNAME}/.qmail-hostmaster
echo ${USERNAME}          > /home/${USERNAME}/.qmail-abuse
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.qmail-*

## this will tell qmail-send to re-read it's config
/command/svc -h /service/qmail-send;

## prepare apache vhost

mkdir -p -m 0750 /var/www/virtual/${USERNAME};
chown ${USERNAME}:apache /var/www/virtual/${USERNAME};

mkdir -p -m 0755 /var/www/virtual/${USERNAME}/html;
chown ${USERNAME}:${USERNAME} /var/www/virtual/${USERNAME}/html;

mkdir -p -m 0755 /var/www/virtual/${USERNAME}/cgi-bin;
chown ${USERNAME}:${USERNAME} /var/www/virtual/${USERNAME}/cgi-bin;

mkdir -p -m 0755 /var/www/virtual/${USERNAME}/fcgi-bin;
chown ${USERNAME}:${USERNAME} /var/www/virtual/${USERNAME}/fcgi-bin;

mkdir -p -m 0750 /readonly/${USERNAME}/logs;
chgrp ${USERNAME} /readonly/${USERNAME}/logs;
pushd /var/www/virtual/${USERNAME}
ln -s ../../../../readonly/${USERNAME}/logs logs
popd

ln -s /var/www/virtual/${USERNAME}/* /home/${USERNAME};

{
cat <<EOF
## `date +%Y-%m-%d` $0
PHPVERSION=$DEFAULTPHP
EOF
} > /home/${USERNAME}/etc/phpversion;
chown ${USERNAME}.${USERNAME} /home/${USERNAME}/etc/phpversion;
chmod 0664 /home/${USERNAME}/etc/phpversion;

{
cat <<EOF
#!/bin/sh
## `date +%Y-%m-%d` $0
. ~/etc/phpversion
export PHPRC="/home/${USERNAME}/etc"
export USER="${USERNAME}"
export HOME="/home/${USERNAME}"
export TMPDIR="/home/${USERNAME}/tmp"
exec /package/host/localhost/php-\${PHPVERSION}/bin/php-cgi
EOF
} > /var/www/virtual/${USERNAME}/fcgi-bin/php-fcgi-starter;

chown ${USERNAME}.${USERNAME} /var/www/virtual/${USERNAME}/fcgi-bin/php-fcgi-starter;
chmod 755 /var/www/virtual/${USERNAME}/fcgi-bin/php-fcgi-starter;

{
cat <<EOF
## `date +%Y-%m-%d` $0 $@

<Directory /var/www/virtual/${USERNAME}>
AllowOverride AuthConfig FileInfo Indexes Limit Options=ExecCGI,Includes,Indexes,MultiViews,SymLinksIfOwnerMatch
Options +Includes
</Directory>

<VirtualHost ${HOSTIP}:81>
ServerName ${USERNAME}.${HOSTNAME}
ServerAlias *.${USERNAME}.${HOSTNAME}
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
} > /etc/httpd/conf.d/virtual.${USERNAME}.conf
chmod 640 /etc/httpd/conf.d/virtual.${USERNAME}.conf;

# check if pound is used
if ! [ "$SSLFRONTEND" == "pound" ];
then

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
Include /etc/httpd/conf/ssl-uberspace.conf
Include /etc/httpd/conf/dyncontent.conf

RewriteEngine On

# PHP expects a "HTTP_AUTHORIZATION" header to correctly provide PHP_AUTH_USER and PHP_AUTH_PW
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]

</VirtualHost>
EOF
} > /etc/httpd/conf.d/ssl.${USERNAME}.conf
chmod 640 /etc/httpd/conf.d/ssl.${USERNAME}.conf;

# check if pound is used (end)
fi

## this triggers a script that will restart httpd within the next five minutes
touch /root/please_restart_httpd;

## create user account and database in MySQL
mysql -u root -e "CREATE DATABASE \`${USERNAME}\`;";
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${USERNAME}\`.* TO \`${USERNAME}\`@\`localhost\` IDENTIFIED BY '$MYSQLPASS';";
mysql -u root -e "GRANT ALL PRIVILEGES ON \`${USERNAME}\_%\`.* TO \`${USERNAME}\`@\`localhost\` IDENTIFIED BY '$MYSQLPASS';";
mysql -u root -e "GRANT USAGE ON *.* TO \`${USERNAME}\`@\`localhost\` WITH MAX_USER_CONNECTIONS 20;";

# additional databases can be added (and removed) with uberspace-account-userdb-[create|delete]

chgrp ${USERNAME} /var/lib/mysql/${USERNAME};
chmod g+s /var/lib/mysql/${USERNAME};

{
cat <<EOF
## `date +%Y-%m-%d` $0 $@
[client]

# Moechtest du dein Passwort aendern, so kannst du das mit dem Befehl
#
#   SET PASSWORD = PASSWORD("...");
#
# auf der MySQL-Shell tun. Anschliessend kannst du es auch hier anpassen.
#
# Beachte, dass dies die Konfigurationsdatei des MySQL-Clients ist, nicht
# die des MySQL-Servers - das Passwort wird hier gefuehrt, damit du dich
# ohne manuelle Eingabe mit dem Server verbinden kannst. Du kannst es
# hierueber aber nicht *setzen*; das muss eben mit SET PASSWORD geschehen.
#
# Mehr dazu findest du hier:
#
# https://uberspace.de/dokuwiki/database:mysql#passwort_aendern

password=${MYSQLPASS} # NICHT ÄNDERN, ohne den obigen Text zu lesen!
port=3306
user=${USERNAME}
socket=/var/lib/mysql/mysql.sock
EOF
} > /home/${USERNAME}/.my.cnf;
chmod 0600 /home/${USERNAME}/.my.cnf;
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.my.cnf;

## we need to return the ipv6-address
echo -e "OK $HOSTIP6 $PASS";

echo -e "Hello.\nThis is ${0} on ${HOSTNAME}.\nI've just created a new uberspace account named ${USERNAME}.\nRegards,\n${0}" | mail -s "uberspace account created" mail@jonaspasche.com;
