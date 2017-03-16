#!/bin/bash

##
# S Script
##

# Specify the path to the s.conf file
S_CONFIG="$HOME/.s.conf"

### Do not modify below line

# Pull in Config

if [ ! -f "$S_CONFIG" ]; then
  echo -e "Could not find Configuration file at \"$S_CONFIG\", Do I have permissions to read this file?\n";
  exit 1;
fi

source "$S_CONFIG"

# Banner
if [ -n "$S_BANNER" ]; then
  echo -e "\n:: kerbyourssh ::"
else
  echo
fi

## Sort Command Line Options
USERSERVER="$1"

## Do we have a user?
if [ -z "$S_USER" ]; then
  echo -e "No user specified, this shouldn't happen?\n"
  exit 1
fi

## Do we have a server?
if [ -z "$USERSERVER" ]; then
  echo -e "Server not specified, Please specify a server to continue\n"
  exit 1;
fi

## Prep Stuff
MACHINEDOMAINENTRY="`grep '^[ ]*domain' /etc/resolv.conf | awk '{ print $2 }'`"
MACHINESEARCHENTRIES="`grep '^[ ]*search' /etc/resolv.conf | awk '{for(i=2;i<=NF;i++){printf "%s ", $i}; printf "\n"}'`"
MACHINEHOSTNAMETLD="`echo "$HOSTNAME" | sed 's/^[^.]\{1,\}\.//g'`"

## Find our Realm
# If we have a default realm specified and no REALM already, Use it
if [[ -z "$REALM" && -n "$DEFAULT_REALM" ]]; then
  REALM="$DEFAULT_REALM";
fi

# If we don't have a realm, try the domain provided by DHCP
if [ -z "$REALM" ]; then
  # Try to grab a domain
  CONFIGCHANGE="Picked up REALM from domain entry in /etc/resolv.conf"
  REALM="$MACHINEDOMAINENTRY"
fi

# If we don't have a realm, try the first search domain provided by DHCP
if [ -z "$REALM" ]; then
  # Try to grab a domain
  CONFIGCHANGE="Picked up REALM from search entry in /etc/resolv.conf"
  REALM="`echo "$MACHINESEARCHENTRIES" | awk '{ print $1 }'`"
fi

# If we don't have a realm, Lets try our hostname
if [ -z "$REALM" ]; then
  # Try to grab a domain
  CONFIGCHANGE="Picked up REALM from local hostname"
  REALM="`echo "$HOSTNAME" | sed 's/^[^.]\{1,\}\.//g'`"
fi

# We don't have a realm, somehow.
if [ -z "$REALM" ]; then
  echo -e " !! No Realm could be found, Please review manual for further assistance.\n"
  exit 1;
fi

## Find our KDC
if [[ -z "$KDC" && -n "$DEFAULT_KDC" ]]; then
  KDC="$DEFAULT_KDC"
fi

# We still don't have one?
if [ -z "$KDC" ]; then
  echo -e "Could not find KDC for site, Cannot continue."
  exit 1
fi

## Create Kerberos Configuration
# Ensure we have a tempdir specified, if not, use /tmp
if [ -z "$KRB5_TEMP" ]; then
  KRB5_TEMP="/tmp"
fi

# Generate krb5.conf
KRB5CONF="$KRB5_TEMP/s-krb5-$S_USER-$RANDOM";
echo "[libdefaults]
        default_realm = $REALM
        forwardable = true
        proxiable = true
        ticket_lifetime = 90000
        renew_lifetime = 432000
	renewable = true
        kdc_timeout = 5
        max_retries = 3
        allow_weak_crypto = TRUE
      [realms]
        $REALM = {
                kdc = $KDC
                default_domain = $REALM
        }
      [domain_realm]
        .$REALM = $REALM
        $(echo "$REALM" | tr '[A-Z]' '[a-z]') = $REALM
" > $KRB5CONF

## Lets Work it ;)

if [ -n "$CONFIGCHANGE" ]; then
  echo -e "Attention! Configuration Change: $CONFIGCHANGE"
fi

# Do we need to Login?
if [ -z "`klist 2>&1 | grep krbtgt | grep -i "$REALM" | grep -vi expired`" ]; then
  echo -e "Welcome $S_USER, You require a login."
  loggedin=""
  while [ -z "$loggedin" ]; do
    env KRB5_CONFIG="$KRB5CONF" kinit $S_USER@$REALM
    if [ $? -eq 0 ]; then
      echo -e "Successfully logged in!\n";
      loggedin="yes"
    fi
  done
fi

# Can we get to the server?
HOSTRESULT="`host "$USERSERVER"`"
if [ $? -eq 0 ]; then
  # We do this to make the DNS full for it ;)
  SERVER="`echo "$HOSTRESULT" | awk '{ print $1 }'`"
else 
  for suffix in $MACHINEDOMAINENTRY $MACHINESEARCHENTRIES $MACHINEHOSTNAMETLD $DEFAULT_DOMAINS; do
    HOSTRESULT="`host "$USERSERVER.$suffix"`"
    if [ $? -eq 0 ]; then
      SERVER="`echo "$HOSTRESULT" | awk '{ print $1 }'`"
      break
    fi
  done
fi

if [ -z "$SERVER" ]; then
  echo -e "Could not locate the specified server in DNS!\n"
  exit 1;
fi

# Log into server
echo -e "Logging into $SERVER as $S_USER\n"
env KRB5_CONFIG="$KRB5CONF" ssh $SSH_OPTS $S_USER@$SERVER

# Clean up ;)
rm -f "$KRB5CONF"
