###################################################
# INFO: deploy a ai as a pod
#
# Date updated: 04-12-2023
###################################################

#!/bin/bash


# Global Variable Definition
export OFFLINE_REG_HOSTNAME_FQDN=registry.offline.redhat.lan
export AI_HOSTNAME_FQDN=ai.offline.redhat.lan
export OCP_VERSION="4.12.2"
# check if ai already exists
if [[ -d /opt/ai/ ]]
then
  echo "/opt/ai folder detected, aborting installation"
  exit 1
fi

# create the ai.offline.redhat.lan workingdirectory
sudo mkdir -p /opt/ai/

# Install http-tools packet
if [ $(hostnamectl | grep "Operating System" | awk '{print $3 $5}') == "CentOS7" ]; then
    sudo yum update -y 
    wait
    sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    sudo yum -y install "@Development Tools"
    wait
    sudo yum install -y jq
    wait
    sudo yum install -y curl gcc make device-mapper-devel git btrfs-progs-devel conmon containernetworking-plugins containers-common glib2-devel glibc-devel glibc-static golang-github-cpuguy83-md2man gpgme-devel iptables libassuan-devel libgpg-error-devel libseccomp-devel libselinux-devel pkgconfig systemd-devel autoconf python3 python3-devel python3-pip yajl-devel libcap-devel
    wait
    sudo yum install -y wget
    curl -L https://go.dev/dl/go1.20.4.linux-amd64.tar.gz --output /opt/ai/go1.20.4.linux-amd64.tar.gz
    wait
    tar xvf /opt/ai/go1.20.4.linux-amd64.tar.gz --directory /usr/local
    export PATH=$PATH:/usr/local/go/bin
    git clone https://github.com/containers/conmon /opt/ai/conmon
    make -C /opt/ai/conmon
    sudo make -C /opt/ai/conmon podman
    git clone https://github.com/opencontainers/runc.git $GOPATH/src/github.com/opencontainers/runc
    make -C $GOPATH/src/github.com/opencontainers/runc BUILDTAGS="selinux seccomp"
    sudo cp $GOPATH/src/github.com/opencontainers/runc /usr/bin/runc
    sudo mkdir -p /etc/containers
    sudo curl -L -o /etc/containers/registries.conf https://src.fedoraproject.org/rpms/containers-common/raw/main/f/registries.conf
    wait
    sudo curl -L -o /etc/containers/policy.json https://src.fedoraproject.org/rpms/containers-common/raw/main/f/default-policy.json
    wait
    TAG=4.1.1
    curl -sSfL https://github.com/containers/podman/archive/refs/tags/v${TAG}.tar.gz --output "/opt/ai/v${TAG}.tar.gz"
    tar xvf /opt/ai/v${TAG}.tar.gz --directory /opt/ai/
    sudo yum remove  gpgme-devel -y
    sudo yum -y install https://cbs.centos.org/kojifiles/packages/gpgme/1.7.1/0.el7.centos.1/x86_64/gpgme-1.7.1-0.el7.centos.1.x86_64.rpm
    sudo yum -y install https://cbs.centos.org/kojifiles/packages/gpgme/1.7.1/0.el7.centos.1/x86_64/gpgme-devel-1.7.1-0.el7.centos.1.x86_64.rpm
    wait
    make -C /opt/ai/podman-${TAG} BUILDTAGS="selinux seccomp"
    wait
    sudo make -C /opt/ai/podman-${TAG} install PREFIX=/usr
    wait
    sudo sed -ie 's/override_kernel_check/#override_kernel_check/g' /etc/containers/storage.conf
else 
    sudo yum -y install podman httpd-tools skopeo
    wait
fi



# Adding the IPv6 /etc/hosts resolution 

echo "2620:52:0:1305::101 ${OFFLINE_REG_HOSTNAME_FQDN}" >> /etc/hosts
echo "2620:52:0:1305::102 ${AI_HOSTNAME_FQDN}" >> /etc/hosts
echo "2620:52:0:1305::253 api.someone-test.test412.com console-openshift-console.apps.someone-test.test412.com oauth-openshift.apps.someone-test.test412.com prometheus-k8s-openshift-monitoring.apps.someone-test.test412.com" >> /etc/hosts

# Obtian the certificate from the repository
echo -n | openssl s_client -connect ${OFFLINE_REG_HOSTNAME_FQDN}:5000 -servername ${OFFLINE_REG_HOSTNAME_FQDN} | openssl x509 > /opt/ai/file.crt

# Copy certificate to the cert repository
sudo cp /opt/ai/file.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# validate that the certificate is accessible from the ai.offline.redhat.lan
#status_code=$(curl --write-out %{http_code} --silent -u admin:Sup3rR3gistry --output /dev/null https://${OFFLINE_REG_HOSTNAME_FQDN}:5000/v2/_catalog)
#if [[ "$status_code" -ne 200 ]] ; then
#        echo -e "\n Response Code changed to $status_code"
#        exit 1
#    else
#        echo -e "\n Response Code is $status_code. The Offline Registry its reachable"

echo | openssl s_client -servername ${OFFLINE_REG_HOSTNAME_FQDN}:5000 -connect ${OFFLINE_REG_HOSTNAME_FQDN}:5000 2>/dev/null | openssl x509 > /opt/ai/tls-ca-bundle.pem
export AI_PEM_CA=$(cat /opt/ai/tls-ca-bundle.pem)

# Create configmap-disconnected.yml
cat <<EOF | sudo tee /opt/ai/configmap-disconnected.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: config
data:
  ASSISTED_SERVICE_HOST: 2620:52:0:1305::102:8090
  ASSISTED_SERVICE_SCHEME: http
  AUTH_TYPE: none
  DB_HOST: ::1
  DB_NAME: installer
  DB_PASS: admin
  DB_PORT: "5432"
  DB_USER: admin
  DEPLOY_TARGET: onprem
  DISK_ENCRYPTION_SUPPORT: "true"
  DUMMY_IGNITION: "false"
  ENABLE_SINGLE_NODE_DNSMASQ: "true"
  HW_VALIDATOR_REQUIREMENTS: '[{"version":"default","master":{"cpu_cores":4,"ram_mib":16384,"disk_size_gb":100,"installation_disk_speed_threshold_ms":10,"network_latency_threshold_ms":100,"packet_loss_percentage":0},"worker":{"cpu_cores":2,"ram_mib":8192,"disk_size_gb":100,"installation_disk_speed_threshold_ms":10,"network_latency_threshold_ms":1000,"packet_loss_percentage":10},"sno":{"cpu_cores":8,"ram_mib":16384,"disk_size_gb":100,"installation_disk_speed_threshold_ms":10}}]'
  IMAGE_SERVICE_BASE_URL: http://2620:52:0:1305::102:8888
  IPV6_SUPPORT: "true"
  ISO_IMAGE_TYPE: "full-iso"
  LISTEN_PORT: "8888"
  NTP_DEFAULT_SERVER: ""
  OS_IMAGES: '[{"openshift_version":"4.12","cpu_architecture":"x86_64","url":"http://2620:52:0:1305::101:3000/rhcos-${OCP_VERSION}-live.x86_64.iso","version":"412.86.202301311551-0"}]'
  POSTGRESQL_DATABASE: installer
  POSTGRESQL_PASSWORD: admin
  POSTGRESQL_USER: admin
  PUBLIC_CONTAINER_REGISTRIES: 'quay.io'
  RELEASE_IMAGES: '[{"openshift_version":"4.12","cpu_architecture":"x86_64","cpu_architectures":["x86_64"],"url":"${OFFLINE_REG_HOSTNAME_FQDN}:5000/ocp-release:4.12.2-x86_64","version":"4.12.2","default":true}]'
  SERVICE_BASE_URL: http://2620:52:0:1305::102:8090
  STORAGE: filesystem
  ENABLE_UPGRADE_AGENT: "false"
  AGENT_DOCKER_IMAGE: "${OFFLINE_REG_HOSTNAME_FQDN}:5000/edge-infrastructure/assisted-installer-agent:latest"
  CONTROLLER_IMAGE: "${OFFLINE_REG_HOSTNAME_FQDN}:5000/edge-infrastructure/assisted-installer-controller:latest"
  INSTALLER_IMAGE: "${OFFLINE_REG_HOSTNAME_FQDN}:5000/edge-infrastructure/assisted-installer:latest"

  registries.conf: |
    unqualified-search-registries = ["registry.access.redhat.com", "docker.io"]
    [[registry]]
        prefix = ""
        location = "quay.io/openshift-release-dev/ocp-release"
        mirror-by-digest-only = true
        [[registry.mirror]]
        location = "${OFFLINE_REG_HOSTNAME_FQDN}:5000/ocp-release"
    [[registry]]
        prefix = ""
        location = "quay.io/openshift-release-dev/ocp-v4.0-art-dev"
        mirror-by-digest-only = true
        [[registry.mirror]]
        location = "${OFFLINE_REG_HOSTNAME_FQDN}:5000/ocp-release"
  tls-ca-bundle.pem: ${AI_PEM_CA}
EOF


# Create pod-persistent-disconnected.yml
cat <<EOF | sudo tee /opt/ai/pod-persistent-disconnected.yml
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: assisted-installer
  name: assisted-installer
spec:
  containers:
  - args:
    - run-postgresql
    image: ${OFFLINE_REG_HOSTNAME_FQDN}:5000/centos7/postgresql-12-centos7:latest
    name: db
    envFrom:
    - configMapRef:
        name: config
    volumeMounts:
      - mountPath: /var/lib/pgsql
        name: pg-data
  - image: ${OFFLINE_REG_HOSTNAME_FQDN}:5000/edge-infrastructure/assisted-installer-ui:latest
    name: ui
    ports:
    - hostPort: 8080
    envFrom:
    - configMapRef:
        name: config
  - image: ${OFFLINE_REG_HOSTNAME_FQDN}:5000/edge-infrastructure/assisted-image-service:latest
    name: image-service
    ports:
    - hostPort: 8888
    envFrom:
    - configMapRef:
        name: config
  - image: ${OFFLINE_REG_HOSTNAME_FQDN}:5000/edge-infrastructure/assisted-service:latest
    name: service
    ports:
    - hostPort: 8090
    envFrom:
    - configMapRef:
        name: config
    volumeMounts:
      - mountPath: /data
        name: ai-data
      - mountPath: /etc/containers
        name: mirror-registry-config
      - mountPath: /etc/pki/ca-trust/extracted/pem
        subPath: tls-ca-bundle.pem
        name: mirror-registry-config
  restartPolicy: Never
  volumes:
    - name: ai-data
      persistentVolumeClaim:
        claimName: ai-service-data
    - name: pg-data
      persistentVolumeClaim:
        claimName: ai-db-data
    - name: mirror-registry-config
      configMap:
        name: config
        deafultMode: 420
        items:
          - key: registries.conf
            path: registries.conf
          - key: tls-ca-bundle.pem
            path: tls-ca-bundle.pem
EOF


podman play kube --configmap /opt/ai/configmap-disconnected.yml /opt/ai/pod-persistent-disconnected.yml
