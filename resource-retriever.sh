#!/bin/bash -x

set -eo pipefail

ARCHIVA_VERSION=${ARCHIVA_VERSION:-2.2.4}
MYSQL_CONNECTOR_VERSION=${MYSQL_CONNECTOR_VERSION:-8.0.12}
BUILD_SNAPSHOT_RELEASE=${BUILD_SNAPSHOT_RELEASE:-false}

# RELEASE_TYPE (standard | snapshot)
# ARCHIVA_VERSION (latest)
# ALSO FOR MYSQL

# Function to verify checksum
verify_checksum() {
    testcmd=$1
    filepath=$2
    sumurl=$3
    sum_expected=`curl -s $sumurl | awk '{print $1}'`
    sum_real=`sha512sum $filepath | awk '{print $1}'`
    if [ "$sum_expected" == "$sum_got" ]; then
	return 0
    else
	return 1
    fi
}

TMPDIR=$(mktemp -d)
if [ ! -d $TMPDIR ]; then
    >&2 echo "Failed to create temp directory"
    exit 1
fi
trap "exit 1"         HUP INT PIPE QUIT TERM
trap "rm -rf $TMPDIR" EXIT
cd $TMPDIR

#
# Download and verify the archiva tarball. Then extract
# it to the default destination
#

SNAPSHOT_BASE=https://archiva-repository.apache.org/archiva/repository/snapshots/org/apache/archiva/archiva-jetty
STANDARD_BASE=https://downloads.apache.org/archiva
if [ "$ARCHIVA_VERSION" == "latest" ]; then
    if [ $BUILD_SNAPSHOT_RELEASE = true ]; then
	ARCHIVA_VERSION=$(curl -s ${SNAPSHOT_BASE}/ |\
			      sed -ne 's/^.*>\([0-9].*.*\)-SNAPSHOT.*$/\1/p' |\
			      sort -V | tail -1 )
    else
	ARCHIVA_VERSION=$(curl -s ${STANDARD_BASE}/ |\
			      sed -ne 's/^.*>\([0-9].*\)\/<.*$/\1/p' |\
			      sort -V | tail -1 )
    fi			      
fi

if [ $BUILD_SNAPSHOT_RELEASE = true ]; then
    ARCHIVA_BASE_URL=${SNAPSHOT_BASE}/${ARCHIVA_VERSION}-SNAPSHOT
    BUILD_NO=$(curl -s ${ARCHIVA_BASE_URL}/maven-metadata.xml | grep buildNumber | cut -f2 -d'>' | cut -f1 -d'<')
    ARCHIVA_RELEASE_FILENAME=$(curl -s ${ARCHIVA_BASE_URL}/ |\
				   grep archiva-jetty | grep "${BUILD_NO}-bin.tar.gz<"|\
				   awk 'BEGIN{FS="href=\""} { print $2 }' |\
				   cut -f1 -d\")
    ARCHIVA_RELEASE_URL=${ARCHIVA_BASE_URL}/${ARCHIVA_RELEASE_FILENAME}
    ARCHIVA_CHECKSUM_URL=${ARCHIVA_RELEASE_URL}.sha1
    if ! curl -O $ARCHIVA_RELEASE_URL; then
	echo "Failed to download $ARCHIVA_RELEASE_URL"
	exit 1
    fi
    if ! verify_checksum 'sha1sum' $ARCHIVA_CHECKSUM_URL $ARCHIVA_RELEASE_FILENAME; then
	echo "Failed to verify checksum for $ARCHIVA_RELEASE_FILENAME"
	exit 1
    fi
else
    ARCHIVA_BASE_URL=${STANDARD_BASE}/${ARCHIVA_VERSION}/binaries
    ARCHIVA_RELEASE_URL=${ARCHIVA_BASE_URL}/apache-archiva-${ARCHIVA_VERSION}-bin.tar.gz
    ARCHIVA_RELEASE_FILENAME=$(basename $ARCHIVA_RELEASE_URL)
    ARCHIVA_CHECKSUM_URL=${ARCHIVA_RELEASE_URL}.sha512
    ARCHIVA_KEY_URL=https://downloads.apache.org/archiva/KEYS
    ARCHIVA_ASC_URL=${ARCHIVA_RELEASE_URL}.asc
    ARCHIVA_ASC_FILENAME=$(basename $ARCHIVA_ASC_URL)
    ARCHIVA_ASC_CHECKSUM_URL=${ARCHIVA_ASC_URL}.sha512

    if ! curl -O $ARCHIVA_RELEASE_URL; then
	echo "Failed to download $ARCHIVA_RELEASE_URL"
	exit 1
    fi
    if ! verify_checksum 'sha512sum' $ARCHIVA_CHECKSUM_URL $ARCHIVA_RELEASE_FILENAME; then
	echo "Failed to verify checksum for $ARCHIVA_RELEASE_FILENAME"
	exit 1
    fi
    if ! curl -O $ARCHIVA_ASC_URL; then
	echo "Failed to download $ARCHIVA_ASC_URL"
	exit 1
    fi
    if ! verify_checksum 'sha512sum' $ARCHIVA_ASC_CHECKSUM_URL $ARCHIVA_ASC_FILENAME; then
	echo "Failed to verify checksum for $ARCHIVA_ASC_FILENAME"
	exit 1
    fi
    if ! curl $ARCHIVA_KEY_URL | gpg --homedir $TMPDIR --import; then
	echo "Failed to import gpg keys from $ARCHIVA_KEY_URL"
	exit 1
    fi
    if ! gpg --quiet --homedir $TMPDIR --verify $ARCHIVA_ASC_FILENAME $ARCHIVA_RELEASE_FILENAME; then
	echo "gpg failed to verify $ARCHIVA_ASC_FILENAME"
	exit 1
    fi
fi

echo "Building archiva from $ARCHIVA_RELEASE_URL"
mkdir -p $ARCHIVA_HOME
tar --strip-components 1 -xz -C $ARCHIVA_HOME -f ${TMPDIR}/${ARCHIVA_RELEASE_FILENAME} 

#
# Download and verify the mysql connector
#
MYSQL_CONNECTOR_BASE=https://repo1.maven.org/maven2/mysql/mysql-connector-java
if [ "$MYSQL_CONNECTOR_VERSION" == "latest" ]; then
    MYSQL_CONNECTOR_VERSION=$(curl -s ${MYSQL_CONNECTOR_BASE}/ |\
				  sed -ne 's/^.*<version>\(.*\)<\/version>.*/\1/p' |\
				  sort -V | tail -1 ) 
fi

MYSQL_CONNECTOR_BASE_URL=${MYSQL_CONNECTOR_BASE}/${MYSQL_CONNECTOR_VERSION}
MYSQL_CONNECTOR_URL=${MYSQL_CONNECTOR_BASE_URL}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar
MYSQL_CONNECTOR_CHECKSUM_URL=${MYSQL_CONNECTOR_BASE_URL}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar.sha1
MYSQL_CONNECTOR_FILENAME=$(basename $MYSQL_CONNECTOR_URL)

if ! curl -O $MYSQL_CONNECTOR_URL; then
    echo "Failed to download $MYSQL_CONNECTOR_URL"
    exit 1
fi
if ! verify_checksum 'sha1sum' $MYSQL_CONNECTOR_CHECKSUM_URL $MYSQL_CONNECTOR_FILENAME; then
    echo "Failed to verify checksum for $MYSQL_CONNECTOR_FILENAME"
    exit 1
fi
mv -v $MYSQL_CONNECTOR_FILENAME ${ARCHIVA_HOME}/lib/
chown -R archiva:archiva $ARCHIVA_HOME


