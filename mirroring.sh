################################################################################################################################################################################################
#
# In this section we are going to prepare the scripts for cluster-release-operators mirroring and day2-operators mirroring
#
# Updated at: 05-May-2023
################################################################################################################################################################################################
#!/bin/bash

# read three numbers and assigned them to 3 vars
read -p "Enter the path to your pull-secret.json : " n1
read -p "Enter the OCP version you want to mirror : " n2

# Preparing the global variables for this section
export REGISTRY_NAME=${HOSTNAME_FQDN}
export REGISTRY_NAMESPACE=olm-mirror
export LOCAL_REG="${REGISTRY_NAME}:5000"
export LOCAL_REPO="ocp-release"
export LOCAL_RELEASE_IMAGES_REPOSITORY="ocp4/openshift4-release-images"
export ARCHITECTURE="x86_64"
export PULLSECRET_FILE=$n1
export OCP_VERSION="$n2"
export UPSTREAM_REPO=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_VERSION/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')
oc adm release mirror -a ${PULLSECRET_FILE} --from=$UPSTREAM_REPO --to-release-image=${LOCAL_REG}/${LOCAL_REPO}:${OCP_VERSION}-${ARCHITECTURE} --to=${LOCAL_REG}/${LOCAL_REPO}
oc image mirror -a ${PULLSECRET_FILE} ${LOCAL_REG}/${LOCAL_REPO}:${OCP_VERSION}-${ARCHITECTURE} ${LOCAL_REG}/${LOCAL_RELEASE_IMAGES_REPOSITORY}:${OCP_VERSION}-${ARCHITECTURE}


