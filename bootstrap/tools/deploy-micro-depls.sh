#!/bin/bash
#===========================================================================
# Deploy micro-depls minima prerequisites for bootstrap
#===========================================================================

#--- Load common parameters and functions
TOOLS_PATH=$(dirname $(which $0))
. ${TOOLS_PATH}/functions.sh

#--- BOSH log level
if [ "$1" = "debug" ] ; then
  export BOSH_LOG_LEVEL=DEBUG
else
  export BOSH_LOG_LEVEL=INFO
fi

#--- Update Cloud-config
updateCloudConfig() {
  #--- Check if cloud-config has been applied
  status=$(bosh cloud-config | grep "azs:" | awk '{print $1}')
  if [ "${status}" != "" ] ; then
    display "INFO" "Bosh cloud-config already deployed"
  else
    display "INFO" "Update cloud config"
    cd ${TEMPLATE_REPO_DIR}/micro-depls/template

    case "${IAAS_TYPE}" in
      "openstack-hws")
        VARS_FILES="${IAAS_TYPE}/networks-cloud-vars-tpl.yml"
        OPERATORS_FILES="-o ${IAAS_TYPE}/disk-types-cloud-operators.yml -o ${IAAS_TYPE}/networks-cloud-operators.yml -o ${IAAS_TYPE}/vm-types-cloud-operators.yml" ;;
      "vsphere")
        VARS_FILES="${IAAS_TYPE}/azs-cloud-vars-tpl.yml ${IAAS_TYPE}/networks-cloud-vars-tpl.yml"
        OPERATORS_FILES="-o ${IAAS_TYPE}/azs-cloud-operators.yml -o ${IAAS_TYPE}/disk-types-cloud-operators.yml -o ${IAAS_TYPE}/networks-cloud-operators.yml -o ${IAAS_TYPE}/vm-types-cloud-operators.yml" ;;
    esac

    #--- Set vars files
    spruce merge --prune secrets ${SHARED_SECRETS} ${VARS_FILES} > cloud-config-vars.yml
    if [ $? != 0 ] ; then
      display "ERROR" "Generate cloud-config vars file failed"
    fi

    #--- Generate cloud-config manifest
    bosh int cloud-config-tpl.yml ${OPERATORS_FILES} --vars-store cloud-config-vars.yml > ${SECRETS_MICRO_DEPLS_DIR}/cloud-config.yml
    if [ $? != 0 ] ; then
      display "ERROR" "Generate cloud-config manifest failed"
    fi

    #--- Update cloud-config
    bosh -n update-cloud-config ${SECRETS_MICRO_DEPLS_DIR}/cloud-config.yml
    if [ $? != 0 ] ; then
      display "ERROR" "micro-depls cloud-config upload failed"
    fi
    rm -f cloud-config-vars.yml > /dev/null 2>&1

    #--- Commit updated files to secret repository
    commitGit "secrets" "set_bootstrap_cloud_config"
  fi
}

#--- Update runtime-config
updateRuntimeConfig() {
  #--- Check if runtime-config has been applied
  status=$(bosh runtime-config | grep "addons:" | awk '{print $1}')
  if [ "${status}" != "" ] ; then
    display "INFO" "Bosh runtime-config already deployed"
  else
    display "INFO" "Update runtime config"
    cd ${TEMPLATE_REPO_DIR}/micro-depls/template

    case "${IAAS_TYPE}" in
      "openstack-hws")
        VARS_FILES="login-banner-runtime-vars-tpl.yml 1-transparent-proxy-runtime-vars-tpl.yml"
        OPERATORS_FILES="-o bpm-runtime-operators.yml -o ca-cert-runtime-operators.yml -o login-banner-runtime-operators.yml \
        -o 1-bosh-dns-runtime-operators.yml -o bootstrap/bootstrap-operators.yml" ;;
      "vsphere")
        VARS_FILES="login-banner-runtime-vars-tpl.yml 1-transparent-proxy-runtime-vars-tpl.yml"
        OPERATORS_FILES="-o bpm-runtime-operators.yml -o ca-cert-runtime-operators.yml -o login-banner-runtime-operators.yml \
        -o 1-bosh-dns-runtime-operators.yml -o ${IAAS_TYPE}/2-bosh-dns-aliases-runtime-operators.yml -o bootstrap/bootstrap-operators.yml" ;;
    esac

    #--- Set vars files
    pki_certs=$(cat ${INTRANET_CA_CERTS} | sed -e "s+^+    +g")
    printf "certs:\n  intranet: |\n${pki_certs}" > tmp-runtime-config-vars.yml
    bosh_ca_cert=$(cat ${INTERNAL_CA_CERT} | sed -e "s+^+    +g")
    printf "\n  internal: |\n${bosh_ca_cert}" >> tmp-runtime-config-vars.yml
    printf "\nallcerts: (( concat certs.intranet certs.internal ))\n\n" >> tmp-runtime-config-vars.yml
    META_FILE="${SECRETS_MICRO_DEPLS_DIR}/secrets/meta.yml"

    spruce merge --prune secrets ${SHARED_SECRETS} ${META_FILE} ${VARS_FILES} tmp-runtime-config-vars.yml > runtime-config-vars.yml
    if [ $? != 0 ] ; then
      display "ERROR" "Generate runtime-config vars file failed"
    fi

    #--- Generate runtime-config manifest
    bosh int runtime-config-tpl.yml ${OPERATORS_FILES} --vars-store runtime-config-vars.yml > ${SECRETS_MICRO_DEPLS_DIR}/runtime-config.yml
    if [ $? != 0 ] ; then
      display "ERROR" "Generate runtime-config manifest failed"
    fi

    #--- Update runtime-config
    bosh -n update-runtime-config ${SECRETS_MICRO_DEPLS_DIR}/runtime-config.yml
    if [ $? != 0 ] ; then
      display "ERROR" "micro-depls runtime-config upload failed"
    fi
    rm -f tmp-runtime-config-vars.yml runtime-config-vars.yml > /dev/null 2>&1

    #--- Commit updated files to secret repository
    commitGit "secrets" "set_bootstrap_runtime_config"
  fi
}

#--- Download and upload bosh release in micro-bosh director
uploadRelease() {
  DOWLOAD_TYPE="$1"
  BOSH_RELEASE_NAME="$2"
  BOSH_RELEASE_NAME_VERSION="$3"
  BOSH_RELEASE_URL="$4"

  BOSH_RELEASE_VERSION="$5"
  GIT_TAG="$6"

  #--- Check if bosh release version is defined in micro-depls-versions
  if [ "${DOWLOAD_TYPE}" = "http" ] ; then
    if [ "${BOSH_RELEASE_VERSION}" = "" ] ; then
      releaseVersionName="${BOSH_RELEASE_NAME_VERSION}-version"
      BOSH_RELEASE_VERSION=$(grep "${releaseVersionName}:" ${MICRO_DEPLS_VERSION_FILE} | awk '{print $2}' | sed -e "s+\"++g")
      if [ "${BOSH_RELEASE_VERSION}" = "" ] ; then
        display "ERROR" "Bosh release \"${BOSH_RELEASE_NAME}\" version unknown in \"${MICRO_DEPLS_VERSION_FILE}\""
      fi
    fi
  fi

  #--- Check if bosh release is loaded
  status=$(echo "${BOSH_RELEASES_LIST}" | grep "${BOSH_RELEASE_NAME}:${BOSH_RELEASE_VERSION}")
  if [ "${status}" = "" ] ; then
    display "INFO" "Download bosh release \"${BOSH_RELEASE_NAME}\" version \"${BOSH_RELEASE_VERSION}\""
    case "${DOWLOAD_TYPE}" in
      "http")
        BOSH_RELEASE="$(echo "${BOSH_RELEASE_URL}" | sed -e "s+.*/++g")${BOSH_RELEASE_VERSION}"
        curl ${CURL_OPTION} ${BOSH_RELEASE_URL}${BOSH_RELEASE_VERSION} -L -s -o ${BOSH_RELEASE} > /dev/null 2>&1
        if [ $? != 0 ] ; then
          display "ERROR" "Download bosh release \"${BOSH_RELEASE_NAME}\" version \"${BOSH_RELEASE_VERSION}\" failed"
        fi ;;

      "git")
        BOSH_RELEASE="releases/${BOSH_RELEASE_NAME}/${BOSH_RELEASE_NAME}-${BOSH_RELEASE_VERSION}.yml"
        CLONE_DIR=~/.bosh/$(echo "${BOSH_RELEASE_URL}" | sed -e "s+.*/++g")
        if [ -d ${CLONE_DIR} ] ; then
          rm -fr ${CLONE_DIR} > /dev/null 2>&1
        fi

        if [ "${IAAS_TYPE}" = "vsphere" ] ; then
          git -c "http.proxy=${PROXY_URL}" clone -b ${GIT_TAG} ${BOSH_RELEASE_URL}.git > /dev/null 2>&1
        else
          git clone -b ${GIT_TAG} ${BOSH_RELEASE_URL}.git > /dev/null 2>&1
        fi

        if [ $? != 0 ] ; then
          rm -fr ${CLONE_DIR} > /dev/null 2>&1
          printf "\n%bERROR: Download bosh release \"${BOSH_RELEASE_NAME}\" version \"${BOSH_RELEASE_VERSION}\" failed.%b\n\n" "${RED}" "${STD}" ; exit 1
        fi
        cd ${CLONE_DIR} ;;

      *) display "ERROR" "Download type \"${DOWLOAD_TYPE}\" unknown" ;;
    esac

    display "INFO" "Upload bosh release \"${BOSH_RELEASE_NAME}\" version \"${BOSH_RELEASE_VERSION}\""
    bosh -n upload-release ${BOSH_RELEASE}
    status=$?
    rm -fr ${BOSH_RELEASE} ${CLONE_DIR} > /dev/null 2>&1
    if [ ${status} != 0 ] ; then
      display "ERROR" "Upload bosh release \"${BOSH_RELEASE_NAME}\" version \"${BOSH_RELEASE_VERSION}\" failed"
    fi
  fi
}

#--- Upload all bosh release needed by micro-depls bootstrap deployments
uploadBoshReleases() {
  display "INFO" "Bosh release already loaded:"
  BOSH_RELEASES_LIST=$(bosh releases --json | sed 's/ //g' | sed 's/\"//g' | sed 's/,//g' | sed 's/*/ /g' | grep -E "name:|version:" | grep -vE "name:Name|version:Version" | awk -F ":" '{if($1 == "name") {name=$2} ; if($1 == "version") {print name ":" $2}}')
  echo "${BOSH_RELEASES_LIST}"
  uploadRelease "http" "bosh-${CPI_IAAS_TYPE}-cpi" "bosh-${CPI_IAAS_TYPE}-cpi-release" "https://bosh.io/d/github.com/cloudfoundry-incubator/bosh-${CPI_IAAS_TYPE}-cpi-release?v"
  uploadRelease "http" "bosh-dns" "bosh-dns" "https://bosh.io/d/github.com/cloudfoundry/bosh-dns-release?v="
  uploadRelease "http" "bosh-dns-aliases" "bosh-dns-aliases" "https://bosh.io/d/github.com/cloudfoundry/bosh-dns-aliases-release?v="
  uploadRelease "http" "bosh-errand-resource" "bosh-errand-resource-boshrelease" "https://bosh.io/d/github.com/starkandwayne/bosh-errand-resource-boshrelease?v="
  uploadRelease "http" "bpm" "bpm" "https://bosh.io/d/github.com/cloudfoundry-incubator/bpm-release?v="
  uploadRelease "http" "credhub" "credhub" "https://bosh.io/d/github.com/pivotal-cf/credhub-release?v="
  uploadRelease "http" "docker" "docker-incubator-boshrelease" "https://bosh.io/d/github.com/cloudfoundry-incubator/docker-boshrelease?v="
  uploadRelease "http" "garden-runc" "garden-runc-release" "https://bosh.io/d/github.com/cloudfoundry/garden-runc-release?v="
  uploadRelease "http" "haproxy" "haproxy-boshrelease" "https://bosh.io/d/github.com/cloudfoundry-community/haproxy-boshrelease?v="
  uploadRelease "http" "minio" "minio" "https://bosh.io/d/github.com/minio/minio-boshrelease?v="
  uploadRelease "http" "networking" "networking-release" "https://bosh.io/d/github.com/cloudfoundry/networking-release?v="
  uploadRelease "http" "ntp" "ntp_boshrelease" "https://bosh.io/d/github.com/cloudfoundry-community/ntp-release?v="
  uploadRelease "http" "os-conf" "os-conf" "https://bosh.io/d/github.com/cloudfoundry/os-conf-release?v="
  uploadRelease "http" "postgres" "postgres" "https://bosh.io/d/github.com/cloudfoundry/postgres-release?v="
  uploadRelease "http" "routing" "cf-routing" "https://bosh.io/d/github.com/cloudfoundry-incubator/cf-routing-release?v="
  uploadRelease "http" "uaa" "uaa" "https://bosh.io/d/github.com/cloudfoundry/uaa-release?v="

  #--- Upload specific releases
  uploadRelease "http" "bpm" "bpm" "https://bosh.io/d/github.com/cloudfoundry/bpm-release?v=" "1.1.1"
  uploadRelease "http" "concourse" "concourse" "https://bosh.io/d/github.com/concourse/concourse-bosh-release?v=" "5.3.0"
  uploadRelease "git" "squid" "squid" "https://github.com/cloudfoundry-community/squid-boshrelease" "1.0.1" "v1.0.1"
}

#--- Deploy a micro-depls bosh deployment
deploy() {
  #--- Check if instances is deployed
  deployment=$1
  status=$(bosh -d ${deployment} instances 2> /dev/null)
  status1=$(echo "${status}" | grep "failing")
  status2=$(echo "${status}" | grep "running")

  if [ "${status1}" != "" ] ; then
    status="ko"
  else
    if [ "${status2}" != "" ] ; then
      status="ok"
    else
      status="ko"
    fi
  fi

  if [ "${status}" = "ok" ] ; then
    display "INFO" "Bosh deployment \"${deployment}\" already running"
  else
    cd ${TEMPLATE_REPO_DIR}/micro-depls/${deployment}/bootstrap
    deploy.sh
    if [ $? != 0 ] ; then
      exit 1
    fi
  fi
}

#--- log to micro-bosh director
display "INFO" "Log into micro-bosh"
cd ${MICRO_BOSH_BOOTSTRAP_DIR}
export BOSH_CLIENT="admin"
export BOSH_CLIENT_SECRET=$(getValue ${SHARED_SECRETS} /secrets/bosh/admin/password)
export BOSH_ENVIRONMENT="192.168.10.10"
export BOSH_CA_CERT="${INTERNAL_CA_CERT}"
bosh alias-env micro
bosh log-in
if [ $? != 0 ] ; then
  display "ERROR" "Log to micro-bosh director failed"
fi

#--- Update Cloud Config
updateCloudConfig

#--- Update Runtime Config
updateRuntimeConfig

#--- Download stemcell and upload it to bosh director
downloadStemcell "inception" "uploadStemcell"

#--- Upload needed bosh releases
uploadBoshReleases

#--- Deploy minimal micro-depls dns-recursor
deploy "dns-recursor"

#---- Deploy minimal internet-proxy
deploy "internet-proxy"

#--- Deploy minimal micro-depls credhub
deploy "credhub-ha"

#--- Deploy minimal micro-depls minio-private-s3
deploy "minio-private-s3"

#--- Deploy minimal micro-depls concourse
deploy "concourse"

display "OK" "Create micro-depls deployments succeeded"