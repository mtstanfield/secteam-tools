#!/bin/sh

#--------------------General notes/checks for the script--------------------
#Make sure you have a reliable Internet conection before running this script
wget -q --spider http://google.com
if [ $? -eq 0 ]; 
then
    echo "Online"
else
    echo "You are offline."
    echo "Please make sure that you have a reliable Internet connection before running this script."
    exit
fi


#Make sure you are running this script as a superuser i.e. as 'root'.
if [[ $EUID -ne 0 ]];
then
   echo "Please run this script as root."
   exit
fi
#--------------------General notes/checks completed--------------------



#--------------------Variable declaration--------------------
#Define variable for OSG PGP key
export OSGSECKEYID=7FD42669

#Set IGTF_CERTS_VERSION according to the release indicated
echo "Enter the IGTF cert version according to the release indicated:"
read IGTF_CERTS_VERSION
export IGTF_CERTS_VERSION

#Set the OSG certificate distribution version 
echo "Enter our IGTF cert version i.e. n.xIGTFNEW:"
read OUR_CERTS_VERSION
export OUR_CERTS_VERSION

#Set the previous version of OUR_CERTS_VERSION for IGTF
echo "What was the previous version of OUR_CERTS_VERSION for IGTF i.e. n.xIGTFNEW?"
read PREVIOUS_IGTFNEW
export PREVIOUS_IGTFNEW
#--------------------Variable declaration completed--------------------



#--------------------Install dependencies--------------------
echo "Installing dependencies..."
yum -y update
yum -y install svn
yum -y install rpm-build
yum -y groups install "Development Tools"
yum -y install ncurses-devel


#install dpkg-deb, fakeroot, dpkg-scanpackages, debsigs
wget http://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/f/fakeroot-1.18.4-2.el7.x86_64.rpm
yum -y install epel-release
yum -y install fakeroot
svn co https://vdt.cs.wisc.edu/svn/certs/trunk/vdt-scripts/
cp vdt-scripts/build-debian-tools builddebiantools.sh
./builddebiantools.sh
source ~/debian-build-tools/setup.sh
#Verify that dpkg-deb, fakeroot, dpkg-scanpackages and debsigs are in your PATH
which dpkg-deb fakeroot dpkg-scanpackages debsigs
if [ $? -ne 0 ];
then
    echo "dpkg-deb, fakeroot, dpkg-scanpackages and debsigs are not in your PATH."
    exit
else
    echo "dpkg-deb, fakeroot, dpkg-scanpackages and debsigs are in your PATH."
fi


yum -y install dpkg
yum -y install perl
yum -y install cpan
yum -y install perl-LWP-Protocol-https
#yum -y install 'perl(IO::Socket::SSL)'		#this is only for EL6
yum -y install perl-Sys-Syslog
cpan install Date::Parse
yum -y install yum-plugin-priorities
git clone https://github.com/opensciencegrid/osg-build
cd osg-build/
PATH=$PATH:`pwd`
cd ..
yum -y install fetch-crl


echo "Dependencies are installed"
#--------------------Installation completed--------------------



#--------------------Environment setup--------------------
echo "Setting up the environment..."
echo "Checking the openssl version..."
OPENSSLVERSION=`openssl version -v`
if echo "$OPENSSLVERSION" | grep -q "OpenSSL 1.0."; 
then
    echo "OpenSSL version is good."
else
    echo "OpenSSL version is not good."
    exit
fi


echo "Verifing the key id value for OSG" 
if gpg --list-keys | grep -q "security@opensciencegrid.org";
then 
    echo "Required key for OSG is present."
else 
    echo "Required key for OSG is not present."
    exit
fi


#Download, import, and verify the IGTF signing key 
echo "Downloading the IGTF key..."
wget https://dist.igtf.net/distribution/current/GPG-KEY-EUGridPMA-RPM-3
echo "Importing the IGTF key..."
gpg --import GPG-KEY-EUGridPMA-RPM-3
echo "Verifying the keys..."
gpg --recv-key 3CDBBC71
gpg --check-sigs 3CDBBC71
gpg --default-key $OSGSECKEYID --lsign-key 3CDBBC71


#Checkout a copy of the svn repository
echo "Checking out the SVN repository..." 
svn co https://vdt.cs.wisc.edu/svn/certs


echo "Environment setup is completed."
#--------------------Environment setup completed--------------------



#--------------------Prepare for multiple caches--------------------
#--------------------Process for IGTF CA i.e. IGTFNEW--------------------
echo "Preparing for IGTFNEW..."
#Change to an empty working directory and set $CAWORKDIR to the path
cd `mktemp -d`
export CAWORKDIR=`pwd`

#Checkout or update the OSG svn directories
cd /certs/trunk/cadist/CA-Certificates-Base
svn update
export CABASEDIR=`pwd`

#Create a new distribution directory for the release
cd $CABASEDIR
mkdir -p $OUR_CERTS_VERSION/certificates
export CADIST=$CABASEDIR/$OUR_CERTS_VERSION/certificates

#Download the new IGTF distribution tarball (and PGP signature) from http://dist.eugridpma.info/distribution/igtf/current/
cd $CAWORKDIR
wget http://dist.eugridpma.info/distribution/igtf/current/igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz
wget http://dist.eugridpma.info/distribution/igtf/current/igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz.asc

#Verify the PGP signature on the tarball
gpg --verify igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz.asc
if [ $? -ne 0 ];
then
    echo "PGP signature verification failed."
    exit
else
    echo "Signature is good."
fi

#Unpack the certificates
tar xzf igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz

#Select the CAs and install to temporary location
cd igtf-policy-installation-bundle-$IGTF_CERTS_VERSION
./configure --prefix=$CADIST --with-profile=classic --with-profile=mics --with-profile=slcs --with-profile=iota
make install

#Compare differences with previous version
#Make sure appropriate extra CA files from $CABASEDIR/non-igtf-certificates are included or removed from the distribution directory $CADIST
cd $CADIST
for ca in * ; do echo $ca; diff $ca $CABASEDIR/$PREVIOUS_IGTFNEW/certificates; done
for ca in $CABASEDIR/$PREVIOUS_IGTFNEW/certificates/* ; do echo $ca; diff $ca . ; done 

#Generate the index files 
cd $CABASEDIR
OPENSSL_LOCATION=`which openssl`
./mk-index.pl --version $OUR_CERTS_VERSION --dir $CADIST --out $CADIST/INDEX --ssl1 $OPENSSL_LOCATION -format 1 --style new
TOTAL_CA=$(./mk-index.pl --version $OUR_CERTS_VERSION --dir $CADIST --out $CADIST/INDEX --ssl1 $OPENSSL_LOCATION -format 1 --style new | tail -1)
export NUMBER_OF_CA=$(echo $TOTAL_CA | grep -o -E '[0-9]+')

#Verify that $CADIST/INDEX.html[.txt] contains the right number of CAs
#You should agree with the number of CAs listed in $CADIST/INDEX.html and $CADIST/INDEX.txt
ls $CADIST/*.pem | wc 
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Make the MD5 checksums
cd $CABASEDIR/$OUR_CERTS_VERSION
( cd $CADIST; md5sum *.0 *.pem ) > cacerts_md5sum.txt
cp cacerts_md5sum.txt $CADIST
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Update the $CADIST/CHANGES file 
cp $CABASEDIR/$PREVIOUS_IGTFNEW/certificates/CHANGES $CADIST
echo "edit $CADIST/CHANGES and remove any temporary editor files like #CHANGES# or CHANGES~"
nano $CADIST/CHANGES
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Add new distribution to repository
cd $CADIST; chmod 644 * 
ls -l
echo "Hit Enter if the permissions are OK i.e. rw- r-- r-- else hit CTRL+c."
read USER_INPUT
cd $CABASEDIR
svn add $OUR_CERTS_VERSION

#Commit all the changes
svn commit -m "Updated to IGTF version $IGTF_CERTS_VERSION, OSG version $OUR_CERTS_VERSION"



#--------------------Check the CA certificates and CRLs--------------------
#Run fetch-crl
pushd $CADIST
FETCH_CRL_lOCATION=`which fetch-crl`
$FETCH_CRL_lOCATION -l `pwd` --out `pwd`

#Check expired or near-expired CRLs
$CABASEDIR/check-crl-expiry.pl *.r0

#Check expired or near-expired CAs
$CABASEDIR/check-ca-expiry.pl *.pem

#Cleanup
rm -f *.r0
popd



#--------------------Make the CA tarball distribution--------------------
#Make sure the $CABASEDIR directory in your svn workspace is up-to-date and contains no local modifications
cd $CABASEDIR
svn status

#Create the tarball
cd $CABASEDIR/$OUR_CERTS_VERSION
tar cvfz osg-certificates-$OUR_CERTS_VERSION.tar.gz --exclude .svn certificates 

#Sign it with the security@opensciencegrid.org PGP key
export OSGSECKEYID=7FD42669 
#Check both the variables
echo "Hit Enter if both the variables are correct, else hit CTRL+c."
echo "i.e. OUR_CERTS_VERSION = $OUR_CERTS_VERSION and OSGSECKEYID = $OSGSECKEYID ?"
read VARIABLES
gpg --default-key $OSGSECKEYID -b osg-certificates-$OUR_CERTS_VERSION.tar.gz



#--------------------Make the DEB--------------------
echo "Hit Enter if both the variables are correct, else hit CTRL+c."
echo "i.e. OUR_CERTS_VERSION = $OUR_CERTS_VERSION and IGTF_CERTS_VERSION = $IGTF_CERTS_VERSION ?"
read VARIABLES

#Make sure CWD is correct
cd $CABASEDIR/$OUR_CERTS_VERSION

#Run the make-deb script
../make-deb



#--------------------Make manifest and save the distribution files in SVN--------------------
cd $CABASEDIR/$OUR_CERTS_VERSION

#Make the manifest
../make-manifest 

#Visually inspect the manifest file (ca-certs-version) #need to fix this

#Set the svn release directory
export SVNDIR=$CABASEDIR/../release

#Copy the files to the svn release directory
cd $CABASEDIR/$OUR_CERTS_VERSION
cp osg-certificates-$OUR_CERTS_VERSION.tar.gz osg-certificates-$OUR_CERTS_VERSION.tar.gz.sig osg-ca-certs-$OUR_CERTS_VERSION-0.deb $SVNDIR
cp ca-certs-version $SVNDIR/ca-certs-version-$OUR_CERTS_VERSION 

#new step [07/05/17]
cp ca-certs-version $CADIST

cp cacerts_md5sum.txt $SVNDIR/cacerts_md5sum-$OUR_CERTS_VERSION.txt

#Change to the svn release directory
cd $SVNDIR

#Commit the files
svn add osg-certificates-$OUR_CERTS_VERSION.tar.gz osg-certificates-$OUR_CERTS_VERSION.tar.gz.sig osg-ca-certs-$OUR_CERTS_VERSION-0.deb ca-certs-version-$OUR_CERTS_VERSION cacerts_md5sum-$OUR_CERTS_VERSION.txt;
svn commit -m "OSG certificates distribution $OUR_CERTS_VERSION"

echo "Process for IGTFNEW is completed."
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#--------------------Process for IGTF CA i.e. IGTFNEW is completed.--------------------



#--------------------Process for OSG CA i.e. NEW--------------------
echo "Preparing for OSG CA i.e. NEW..."
#Change to an empty working directory and set $CAWORKDIR to the path
cd `mktemp -d`
export CAWORKDIR=`pwd`

#Set $IGTF_CERTS_VERSION according to the release indicated
echo "Enter the IGTF cert version according to the release indicated:"
read IGTF_CERTS_VERSION
export IGTF_CERTS_VERSION

#Checkout or update the OSG svn directories
cd /certs/trunk/cadist/CA-Certificates-Base
svn update
export CABASEDIR=`pwd`

#Set the OSG certificates distribution version
echo "Enter our OSG cert version i.e. n.xNEW:"
read OUR_CERTS_VERSION
export OUR_CERTS_VERSION

#Create a new distribution directory for the release
cd $CABASEDIR
mkdir -p $OUR_CERTS_VERSION/certificates
export CADIST=$CABASEDIR/$OUR_CERTS_VERSION/certificates

#Download the new IGTF distribution tarball (and PGP signature) from http://dist.eugridpma.info/distribution/igtf/current 
cd $CAWORKDIR
wget http://dist.eugridpma.info/distribution/igtf/current/igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz
wget http://dist.eugridpma.info/distribution/igtf/current/igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz.asc

#Verify the PGP signature on the tarball
gpg --verify igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz.asc
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Unpack the certificates
tar xzf igtf-policy-installation-bundle-$IGTF_CERTS_VERSION.tar.gz

#Select the CAs and install to temporary location
cd igtf-policy-installation-bundle-$IGTF_CERTS_VERSION
./configure --prefix=$CADIST --with-profile=classic --with-profile=mics --with-profile=slcs --with-profile=iota
make install
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Compare differences with previous version
#Make sure appropriate extra CA files from $CABASEDIR/non-igtf-certificates are included or removed from the distribution directory $CADIST
cd $CADIST
echo "What was the previous version of OUR_CERTS_VERSION for OSG?"
read PREVIOUS_NEW
export PREVIOUS_NEW
for ca in * ; do echo $ca; diff $ca $CABASEDIR/$PREVIOUS_NEW/certificates; done
for ca in $CABASEDIR/$PREVIOUS_NEW/certificates/* ; do echo $ca; diff $ca . ; done
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Generate the index files
cd $CABASEDIR
OPENSSL_LOCATION=`which openssl`
./mk-index.pl --version $OUR_CERTS_VERSION --dir $CADIST --out $CADIST/INDEX --ssl1 $OPENSSL_LOCATION -format 1 --style new

#Verify that $CADIST/INDEX.html[.txt] contains the right number of CAs
#You should agree with the number of CAs listed in $CADIST/INDEX.html and $CADIST/INDEX.txt
ls $CADIST/*.pem | wc
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Make the MD5 checksums
cd $CABASEDIR/$OUR_CERTS_VERSION
( cd $CADIST; md5sum *.0 *.pem ) > cacerts_md5sum.txt
cp cacerts_md5sum.txt $CADIST
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Update the $CADIST/CHANGES file
cp $CABASEDIR/$PREVIOUS_NEW/certificates/CHANGES $CADIST
#Updated step [07/03/17]
echo "edit $CADIST/CHANGES and remove any temporary editor files like #CHANGES# or CHANGES~"
nano $CADIST/CHANGES
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Add new distribution to repository
cd $CADIST; chmod 644 *
ls -l
echo "Hit Enter if the permissions are OK i.e. rw- r-- r-- else hit CTRL+c."
read USER_INPUT
cd $CABASEDIR
svn add $OUR_CERTS_VERSION

#Commit all the changes
svn commit -m "Updated to IGTF version $IGTF_CERTS_VERSION, OSG version $OUR_CERTS_VERSION"



#--------------------Check the CA certificates and CRLs--------------------
#Run fetch-crl
pushd $CADIST
FETCH_CRL_lOCATION=`which fetch-crl`
$FETCH_CRL_lOCATION -l `pwd` --out `pwd`

#Check expired or near-expired CRLs
$CABASEDIR/check-crl-expiry.pl *.r0

#Check expired or near-expired CAs
$CABASEDIR/check-ca-expiry.pl *.pem

#Cleanup
rm -f *.r0
popd



#--------------------Make the CA tarball distribution--------------------
#Make sure the $CABASEDIR directory in your svn workspace is up-to-date and contains no local modifications
cd $CABASEDIR
svn status

#Create the tarball
cd $CABASEDIR/$OUR_CERTS_VERSION
tar cvfz osg-certificates-$OUR_CERTS_VERSION.tar.gz --exclude .svn certificates

#Sign it with the security@opensciencegrid.org PGP key
export OSGSECKEYID=7FD42669
#Check both the variables
echo "Hit Enter if both the variables are correct, else hit CTRL+c."
echo "i.e. OUR_CERTS_VERSION = $OUR_CERTS_VERSION and OSGSECKEYID = $OSGSECKEYID ?"
read VARIABLES
gpg --default-key $OSGSECKEYID -b osg-certificates-$OUR_CERTS_VERSION.tar.gz



#--------------------Make the DEB--------------------
echo "Hit Enter if both the variables are correct, else hit CTRL+c."
echo "i.e. OUR_CERTS_VERSION = $OUR_CERTS_VERSION and IGTF_CERTS_VERSION = $IGTF_CERTS_VERSION ?"
read VARIABLES

#Make sure CWD is correct
cd $CABASEDIR/$OUR_CERTS_VERSION

#Run the make-deb script
../make-deb



#--------------------Make manifest and save the distribution files in SVN--------------------
cd $CABASEDIR/$OUR_CERTS_VERSION

#Make the manifest
../make-manifest

#Visually inspect the manifest file (ca-certs-version) #need to fix this
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Set the svn release directory
export SVNDIR=$CABASEDIR/../release

#Copy the files to the svn release directory
cd $CABASEDIR/$OUR_CERTS_VERSION
cp osg-certificates-$OUR_CERTS_VERSION.tar.gz osg-certificates-$OUR_CERTS_VERSION.tar.gz.sig osg-ca-certs-$OUR_CERTS_VERSION-0.deb $SVNDIR
cp ca-certs-version $SVNDIR/ca-certs-version-$OUR_CERTS_VERSION

#new step [07/05/17]
cp ca-certs-version $CADIST

cp cacerts_md5sum.txt $SVNDIR/cacerts_md5sum-$OUR_CERTS_VERSION.txt

#Change to the svn release directory
cd $SVNDIR

#Commit the files
svn add osg-certificates-$OUR_CERTS_VERSION.tar.gz osg-certificates-$OUR_CERTS_VERSION.tar.gz.sig osg-ca-certs-$OUR_CERTS_VERSION-0.deb ca-certs-version-$OUR_CERTS_VERSION cacerts_md5sum-$OUR_CERTS_VERSION.txt;
svn commit -m "OSG certificates distribution $OUR_CERTS_VERSION"

echo "Process for OSG CA i.e. NEW is completed."
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#--------------------Process for NEW is completed.--------------------
#--------------------Processes for multiple caches are completed--------------------



#--------------------Create a release using Koji--------------------
echo "Creating a release using Koji..."

#--------------------Setup/Preparation--------------------
#Install EPEL (command only for RHEL 7, CentOS 7, and SL 7) 
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

#Install the Yum priorities package (command only for RHEL 7, CentOS 7, and SL 7) 
yum -y install yum-plugin-priorities
#Ensure that /etc/yum.conf has the following line in the [main] section, thereby enabling Yum plugins, including the priorities one: plugins=1
if grep -q plugins=1 /etc/yum.conf; then
    echo "yum.conf file is good."
else
    echo "Set plugins=1 in yum.conf file." 
fi
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Install OSG repositories (command only for RHEL 7, CentOS 7, and SL 7)
rpm -Uvh https://repo.grid.iu.edu/osg/3.3/osg-3.3-el7-release-latest.rpm

#Check out the package source from subversion
svn co https://vdt.cs.wisc.edu/svn/native/redhat 



#--------------------Building RPM packages--------------------
#Copy the tar balls to VDT upsteam machine
echo "Perform the following 3 steps on VDT machine i.e. on library.cs.wisc.edu."
echo "1. SSH library.cs.wisc.edu;"
echo "2. mkdir /p/vdt/public/html/upstream/osg-ca-certs/n.nn/;"	
echo "			     					     where, n.nn = osg-ca-cert version"
echo "3. mkdir /p/vdt/public/html/upstream/igtf-ca-certs/m.mm;"
echo "						 	 	     where, m.mm = igtf-ca-cert version"
echo "Are you done? Hit Enter if yes, else hit CTRL+c."
read VARIABLES

#Run following command in the same terminal where you did all the previous steps
cd $SVNDIR
echo "Enter the version number of OSG CA cert i.e. n.nn:"
read NNN
echo "Enter the version number of IGTF CA cert i.e. m.mm:"
read MMM
echo "Enter your user name for VDT machine i.e. for library.cs.wisc.edu:"
read USERNAME_VDT
scp osg-certificates-${NNN}NEW.tar.gz ${USERNAME_VDT}@library.cs.wisc.edu:/p/vdt/public/html/upstream/osg-ca-certs/$NNN/;
scp osg-certificates-${NNN}IGTF*.tar.gz ${USERNAME_VDT}@library.cs.wisc.edu:/p/vdt/public/html/upstream/igtf-ca-certs/$MMM/

#Do svn update  
cd /root/redhat/trunk/; 
svn update;

#Edit the spec and upstream files for both the rpm packages we produce to point to new release. 
#The rpms to be updated include osg-ca-certs & igtf-ca-certs. 
#For spec file you need to update Version:, Release:, Source0: and add comment in change log. 
#For upstream file you need to update the tarball location.

#----------For osg-ca-certs----------
cd osg-ca-certs;   
echo "Edit Version to n.nn; release to 1; edit Source0 to osg-certificates-n.nnNEW.tar.gz; and add appropriate entry to changelog"
echo "Hit Enter to continue, else hit CTRL+c."
read VARIABLES
nano osg/osg-ca-certs.spec
echo "Update location to osg-ca-certs/n.nn/osg-certificates-n.nnNEW.tar.gz"
echo "Hit Enter to continue, else hit CTRL+c."
read VARIABLES
nano upstream/osg-certificates-NEW.source;

#Create a test build on local environment and Koji
osg-build rpmbuild .; 
#step for brach 3.3: 
osg-build --repo=3.3 rpmbuild .;
#Create a hidden directory with name ‘globus’
mkdir /root/.globus
echo "Export the OSG user certificate (.p12) from your local system and import it in this system and store in '/root/.globus' directory."
echo "Hit Enter once it is done, else hit CTRL+c."
read VARIABLES
echo "What is the name of a OSG user certificate (.p12) file?"
read USER_CERTIFICATE_AND_KEY
#Convert user certificate (.p12) file into userkey.pem file without the certificate
openssl pkcs12 -in /root/.globus/$USER_CERTIFICATE_AND_KEY -out /root/.globus/userkey.pem -nodes -nocerts
#Convert user certificate (.p12) file into usercert.pem file without the key
openssl pkcs12 -in /root/.globus/$USER_CERTIFICATE_AND_KEY -out /root/.globus/usercert.pem -nodes -nokeys

grid-proxy-init 
osg-build --scratch koji .
#step for branch 3.3: 
osg-build --repo=3.3 --scratch koji .
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT
 
#----------For igtf-ca-certs----------
cd .. 
cd igtf-ca-certs
echo "Edit Version to m.mm; edit release to 1; edit Source0 to osg-certificates-n.nnIGTFNEW.tar.gz; and add appropriate entry to changelog"
echo "Hit Enter to continue, else hit CTRL+c."
read VARIABLES
nano osg/igtf-ca-certs.spec 
echo "Update location to igtf-ca-certs/m.mm/osg-certificates-n.nnIGTFNEW.tar.gz;"
echo "Hit Enter to continue, else hit CTRL+c."
read VARIABLES
nano upstream/osg-certificates-IGTFNEW.source; 

#Create a test build on local environment and Koji
osg-build rpmbuild .;
#step for branch 3.3:
osg-build --repo=3.3 rpmbuild .;
osg-build --scratch koji .
#step for brach 3.3: 
osg-build --repo=3.3 --scratch koji .
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Check in the changes to SVN 
cd /root/redhat/trunk/; 
echo "What is the Jira ticket number i.e. SOFTWARE-XXXX?"
read JIRA_TICKET 
svn commit -m "OSG certificates distribution $OUR_CERTS_VERSION. (Jira Ticket: $JIRA_TICKET)"
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

#Create official builds on Koji for EL6 and EL7
cd /root/redhat/trunk/
osg-build koji --el6 osg-ca-certs; osg-build koji --el7 osg-ca-certs; osg-build koji --el6 igtf-ca-certs; osg-build koji --el7 igtf-ca-certs; 

#----------Steps for osg 3.3--------------
echo “Performing the steps for OSG repo 3.3”

cd /root/redhat/branches
svn up .
cd /root/redhat
svn up trunk/osg-ca-certs
svn up trunk/igtf-ca-certs

#To see your latest commit revision number:
svn log -l 5 trunk/osg-ca-certs

#Find the latest revision number and get all the differences between it and the previous one in SVN.
#Purpose: to find the difference in `trunk/osg-ca-certs` before and after your change 
#and merge that change into `branches/osg-3.3/osg-ca-certs` For example, revision 23621 
#was a copy of osg-ca-certs before your update and 23622 was your update. So, the 
#difference between 23622 and 23621 encompasses all the changes you made

echo “Enter the latest version since the previous commit”
read LATESTVERSION

#Get previous version
LATESTVERSIONMINUSONE=`expr $LATESTVERSION - 1`

cd /root/redhat/branches/osg-3.3/osg-ca-certs
svn merge -r${LATESTVERSIONMINUSONE}:${LATESTVERSION} ../../../trunk/osg-ca-certs .
cd /root/redhat/branches/osg-3.3/igtf-ca-certs
svn merge -r${LATESTVERSIONMINUSONE}:${LATESTVERSION} ../../../trunk/igtf-ca-certs .

cd /root/redhat/branches/osg-3.3
svn commit -m "OSG certificates distribution $OUR_CERTS_VERSION. (Jira Ticket: $JIRA_TICKET)"
osg-build koji --el6 --repo=3.3 osg-ca-certs; osg-build koji --el7 --repo=3.3 osg-ca-certs; osg-build koji --el6 --repo=3.3 igtf-ca-certs; osg-build koji --el7 --repo=3.3 igtf-ca-certs;

echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT
#----------Steps for osg 3.3 are done--------------

#Check in the changes to SVN
cd /root/redhat/trunk/; 
svn commit -m "OSG certificates distribution $OUR_CERTS_VERSION. (Jira Ticket: $JIRA_TICKET)"
echo "Hit Enter to continue, else hit CTRL+c."
read USERINPUT

echo "Update the Jira ticket, mention that you have created the builds."
echo "Before promoting the Koji builds, perform extensive testing." 
echo "On the fresh SL6 & SL7 VMs, run kojibuild_testing_sl6.sh and kojibuild_testing_sl7.sh respectively."
echo "Hit Enter once it is done."
read VARIABLES
