#!/bin/bash
########################################################################
#
# 2010-09-01
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
# This script performs a few very common tests for uberspace account
# managment.
#
# It will check for
# - root privileges
# - missing username
# - illegal characters in usernames
#
########################################################################

if [ "`/usr/bin/id -u`" != "0" ] ; then
  echo "Keine root-Rechte vorhanden"
  exit
fi

if [ "$1" = "" ] ; then
  echo "Kein Benutzername angegeben"
  exit
fi

if [ "`echo $1 | grep '[^0-9a-z]'`" != "" ] ; then
  echo "Ungueltige Zeichen im Benutzernamen"
  exit
fi

if [ "`echo $1 | grep '^[a-z]'`" != "$1" ] ; then
  echo "Benutzername beginnt nicht mit einem Buchstaben"
  exit
fi
