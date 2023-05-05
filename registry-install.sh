###################################################
# INFO: deploy a local offline registry as a pod
#
# Date updated: 04-12-2023
###################################################

#!/bin/bash

# disable selinux
setenforce 0
sed -i "s/SELINUX=enforcing/SELINUX=permissive/" /etc/selinux/config

# check if registry already exists
if [[ -d /opt/registry/ ]]
then
  echo "/opt/registry folder detected, aborting installation"
  exit 1
fi


# Install http-tools packet
if [ $(hostnamectl | grep "Operating System" | awk '{print $3 $5}') == "CentOS7" ]; then
    sudo yum -y install podman httpd-tools
    wait
    sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    wait
    sudo yum install -y jq
    wait
else 
    sudo yum -y install podman httpd-tools skopeo
    wait
fi


# Creating the filesystem structure
sudo mkdir -p /opt/registry/{auth,certs,data,conf}
sudo mkdir -p /opt/rhcos_image_cache
sudo semanage fcontext -a -t httpd_sys_content_t "/opt/rhcos_image_cache(/.*)?"
sudo restorecon -Rv /opt/rhcos_image_cache/


# Configure the rhcos_image_cache

podman run -d --name rhcos_image_cache -v /opt/rhcos_image_cache:/var/www/html -p 3000:8080/tcp quay.io/centos7/httpd-24-centos7:latest
wait
podman generate systemd rhcos_image_cache > /etc/systemd/system/podman-rhcos_image_cache.service

sudo systemctl daemon-reload
sudo systemctl enable podman-rhcos_image_cache --now

sleep 40
# Configure CA certificate
export HOSTNAME_FQDN=$(hostname --long)
export CERT_C="AT"
export CERT_S="Wien"
export CERT_L="Wien"
export CERT_O="RedHat"
export CERT_OU="R&D"
export CERT_CN="${HOSTNAME_FQDN}"


podman run -d --name openssl --rm -v /opt/registry/certs:/keys:z registry.access.redhat.com/ubi8/openssl req -newkey rsa:4096 -nodes -sha256 -keyout /keys/domain.key -x509 -days 3650 -out /keys/domain.crt -addext "subjectAltName = DNS:${HOSTNAME_FQDN}" -subj "/C=${CERT_C}/ST=${CERT_S}/L=${CERT_L}/O=${CERT_O}/OU=${CERT_OU}/CN=${CERT_CN}"
wait

# Create admin user for the registry
sudo htpasswd -bBc /opt/registry/auth/htpasswd admin Sup3rR3gistry


# Create manifest: config.yml
cat <<EOF | sudo tee /opt/registry/conf/config.yml
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
compatibility:
  schema1:
    enabled: true
EOF


# Create service: podman-registry.service
podman run -d --name registry --hostname registry --net host -e REGISTRY_AUTH=htpasswd -e REGISTRY_AUTH_HTPASSWD_REALM=basic-realm -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -e REGISTRY_HTTP_SECRET=redhat -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key -e REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/registry -v /opt/registry/auth:/auth:Z -v /opt/registry/certs:/certs:z -v /opt/registry/data:/registry:z -v /opt/registry/conf/config.yml:/etc/docker/registry/config.yml:z quay.io/mavazque/registry:2.7.1
wait
podman generate systemd registry > /etc/systemd/system/podman-registry.service


# Configure podman-registry service: enable & start
sudo systemctl daemon-reload
sudo systemctl enable podman-registry --now


# Copy certificate to the cert repository
sudo cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# Adding the IPv6 /etc/hosts resolution 

echo "2620:52:0:1305::101 ${HOSTNAME_FQDN}" >> /etc/hosts
echo "2620:52:0:1305::102 ai.offline.redhat.lan" >> /etc/hosts
echo "2620:52:0:1305::253 api.someone-test.test412.com console-openshift-console.apps.someone-test.test412.com oauth-openshift.apps.someone-test.test412.com prometheus-k8s-openshift-monitoring.apps.someone-test.test412.com" >> /etc/hosts

# List registry catalog
sleep 60
curl -u admin:Sup3rR3gistry https://${HOSTNAME_FQDN}:5000/v2/_catalog

################################################################################################################################################################################################
#
# In this section we are going to populate the environment with openshift-cli based binaries, RHCOS based images and mirroring the container-based-images for deploying the AssistedInstaller
#
# Updated at: 05-May-2023
################################################################################################################################################################################################
# Downloading the OpenShift binaries cli:
export OCP_VERSION="4.12.2"

curl -sSfL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_VERSION}/oc-mirror.tar.gz | tar  zxvf - oc-mirror
curl -sSfL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz | tar  zxvf -
curl -sSfL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz | tar  zxvf -
sudo cp -r kubectl oc oc-mirror openshift-install /usr/local/bin/
sudo chmod a+x /usr/local/bin/*
wait
# Preparing the global variables for this section

export MACHINE_OS=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/release.txt | grep 'machine-os' | awk -F ' ' '{print $2}'| head -1)
export QCOW2_RHCOS=$(openshift-install coreos print-stream-json | jq '.architectures.x86_64.artifacts.openstack.formats."qcow2.gz".disk.location' | tr -d '"')
export LIVE_RHCOS=$(openshift-install coreos print-stream-json | jq '.architectures.x86_64.artifacts.metal.formats.iso.disk.location' | tr -d '"')
export ROOTFS_RHCOS=$(openshift-install coreos print-stream-json | jq '.architectures.x86_64.artifacts.metal.formats.pxe.rootfs.location' | tr -d '"')

# defining array section 
declare -a arr=(
    "rhcos-${OCP_VERSION}-openstack.x86_64.qcow2.gz" 
    "rhcos-${OCP_VERSION}-live.x86_64.iso" 
    "rhcos-${OCP_VERSION}-live-rootfs.x86_64.img")

args=()

touch /opt/rhcos_image_cache/hello
echo "Hello there" >> /opt/rhcos_image_cache/hello
# Checking if the images required for the release are existing on the path or shall be downloaded
for i in "${arr[@]}"
do
    if [ -f "/opt/rhcos_image_cache/$i" ]; then
        echo "$i exists."
    else 
        echo "$i does not exist."
        args+=("$i")
    fi
done
# echo "${args[@]}"
# Making sure that we download only the missing images 
for index in "${args[@]}"
do
    if [[ "$(echo "$index" | cut -d '_' -f 2)" == "64.qcow2.gz" ]]; then
        curl -L ${QCOW2_RHCOS} --output "/opt/rhcos_image_cache/$index"
        wait
    elif [[ "$(echo "$index" | cut -d '_' -f 2)" == "64.iso" ]]; then
        curl -L ${LIVE_RHCOS} --output "/opt/rhcos_image_cache/$index"
        wait
    else
        curl -L ${ROOTFS_RHCOS} --output "/opt/rhcos_image_cache/$index"
        wait
    fi
done

podman login -u admin -p Sup3rR3gistry ${HOSTNAME_FQDN}:5000
wait
# Mirroring all the images required for Disconnected AI:
export QUAY_IO="quay.io"
export OFFLINE_REG="${HOSTNAME_FQDN}:5000"
declare -a arr=(
    "/karmab/aicli" 
    "/edge-infrastructure/assisted-installer-controller:latest" 
    "/edge-infrastructure/assisted-installer-agent:latest"
    "/edge-infrastructure/assisted-installer-ui:latest"
    "/edge-infrastructure/assisted-installer:latest"
    "/edge-infrastructure/assisted-image-service:latest"
    "/edge-infrastructure/assisted-service:latest"
    "/centos7/postgresql-12-centos7:latest"
    "/vrutkovs/okd-rpms:4.11")

## now loop through the above array
for i in "${arr[@]}"
do
   echo "${QUAY_IO}$i"
   podman pull "${QUAY_IO}$i"
   podman tag "${QUAY_IO}$i" "${OFFLINE_REG}$i"
   podman push "${OFFLINE_REG}$i"
   # or do whatever with individual element of the array
done

