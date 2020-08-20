#!/bin/bash

corp_domain=$1
ad_domain=$2

CORP_DOMAIN=$(echo ${corp_domain^^}) #Input uppercase
host=$(hostname)

if [ -z $1 ]; then
    echo -e "Please, input corporation domain \n\tEX:'./host-ad.sh corp.domain.com ad_domain' "
    exit
fi

# 1. Install the software packages and any dependencies.

repo=$(zypper repos | grep 'openSUSE_Leap_15.1_Update' | wc -l)
packages=$(zypper -q search -ix krb5-client samba-client openldap2-client sssd-ad | grep -E 'package' | wc -l)

if [ $repo -eq '0' ]; then
    echo -e "[WORKING] \tNecessary repo not found. Adding 'openSUSE_Leap_15.1_Update' repo..."
    zypper -q addrepo https://download.opensuse.org/repositories/openSUSE:Leap:15.1:Update/standard/openSUSE:Leap:15.1:Update.repo
fi

echo -e "[WORKING] \tZypper refreshing... Wait! "
zypper -q refresh

if [ $packages -eq '4' ]; then
    echo -e "[OK] \t\tPackages already installed. Next step..."
else
    echo "[WORKING] \tPackages not found. Installing packages...."
    zypper -q in -y krb5-client samba-client openldap2-client sssd-ad
fi

# 2. Verify the SLES host can resolve itself using the DNS service used in the target domain.
#nslookup $host $ad_domain

# 3. Verify the SLES host is synchronizing time with the NTP source in the target domain.
#ntpq -p

# 4. Make backup copies of the files (do only once, only if dir does not exists)
dir='/etc/copy'
if [ ! -d $dir ]; then
    echo -e "[WORKING] \tCopying files"
    mkdir /etc/copy-ad-files
    cp -p /etc/krb5.conf /etc/samba/smb.conf /etc/nsswitch.conf /etc/openldap/ldap.conf /etc/sssd/sssd.conf /etc/copy-ad-files/
    echo -e "[COMPLETE] \tCopy sucessfully made"
fi

# 5. Shutdown and disable the Name Service Caching Daemon (nscd).
systemctl stop nscd.service
systemctl disable nscd.service

# 6. Configure the Kerberos client (/etc/krb5.conf) to permit the kinit utility to communicate with the target domain.
echo -e "[WORKING] \tChanging files...\n\n"

sed -i "s/#CORP_DOMAIN/$CORP_DOMAIN/g" krb5.conf
sed -i "s/#corp_domain/$corp_domain/g" krb5.conf
sed -i "s/#ad_domain/$ad_domain/g" krb5.conf
sed -i "s/#ad_subdomain/`echo $ad_domain|cut -f2- -d.`/g" krb5.conf

# 7. Configure the Samba client (/etc/samba/smb.conf) to permit the net utility to communicate with the target domain.
sed -i "s/#CORP_DOMAIN/$CORP_DOMAIN/g" smb.conf
sed -i "s/#CORP/`echo $CORP_DOMAIN|awk -F. '{print $2}'`/g" smb.conf

# 8. Modify the passwd and group sources in the Name Service Switch configuration file (/etc/nsswitch.conf) to reference the SSSD when resolving users and groups.
sed -i "/#passwd/c\passwd: compat sss" nsswitch.conf
sed -i "/#group/c\group:  compat sss" nsswitch.conf

# 9. Configure the OpenLDAP client (/etc/openldap/ldap.conf) to establish runtime defaults for client utilities such as ldapsearch.
sed -i "/#URI/c\URI      ldap://$ad_domain" ldap.conf
sed -i "/#BASE/c\BASE     dc=`echo $ad_domain|awk -F. '{print $1}'`,dc=`echo $ad_domain|awk -F. '{print $2}'`,dc=`echo $ad_domain|awk -F. '{print $3}'`" ldap.conf
# 10. Use the configured Kerberos client to authenticate to the target domain as Administrator.
#kinit Administrator

# 11. Use the net utility to join the system to the domain and generate a system keytab file.
#net ads join osname=”SLES” osVersion=15 osServicePack=”Latest” –no-dns-updates -k

# 12. Use the net and ldapsearch utilities to access Active Directory using the joined system.
echo "Verify SASL connection can be instantiated using Kerberos"
ldapsearch sAMAccountName=Administrator
kdestroy

# 13. Configure the Pluggable Authentication Module (PAM) configuration on the SLES host to authenticate users using the SSSD, and create home directories for them on login if they do not already exist.
pam-config -add -sss
pam-config -add -mkhomedir

# 14. Configure the SSSD client configuration file (/etc/sssd/sssd.conf) for the target domain.
sed -i "s/#corp_domain/$corp_domain/g" sssd.conf
sed -i "s/#ad_domain/$ad_domain/g" sssd.conf

# 15. Moving directories to correct place
mv krb5.conf /etc/krb5.conf; mv smb.conf /etc/samba/smb.conf; mv nsswitch.conf /etc/nsswitch.conf; mv ldap.conf /etc/openldap/ldap.conf; mv sssd.conf /etc/sssd/sssd.conf;
chmod 600 /etc/sssd/sssd.conf

# 16. Enable and start the SSSD at system boot
systemctl enable sssd.service
systemctl start sssd.service

# 17. Ensure the SSSD can resolve and authenticate Active Directory users and groups.
id administrator
ssh administrator@sles.corp.domain.com