#!/bin/sh
#===========================================================================
# Init minio buckets and directories
#===========================================================================

#--- Colors and styles
export RED='\033[1;31m'
export YELLOW='\033[1;33m'
export GREEN='\033[1;32m'
export STD='\033[0m'
export BOLD='\033[1m'
export REVERSE='\033[7m'

#--- Log to minio
log-credhub
propertie="/micro-bosh/minio-private-s3/s3_secretkey"
S3_ACCESS_KEY=$(credhub g -n ${propertie} | grep 'value:' | awk '{print $2}')
if [ $? != 0 ] ; then
  printf "\n%bERROR: Propertie \"%s\" unknown in \"credhub\".%b\n\n" "${REVERSE}${RED}" "${propertie}" "${STD}" ; exit 1
fi

mc config host add minio http://private-s3.internal.paas:9000 private-s3 "${S3_ACCESS_KEY}"
if [ $? != 0 ] ; then
  printf "\n%bERROR : Minio access failed.%b\n\n" "${RED}" "${STD}"
else
  current_dir=$(basedir "$0")
  "${current_dir}"/setup-bucket.sh  # We externalize buckets creation to share code with upgrade pipeline
fi
