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

# Install http-tools packet
sudo yum -y install podman 
# create the ai.offline.redhat.lan workingdirectory
sudo mkdir -p /opt/ai/

# Adding the IPv6 /etc/hosts resolution 

echo "2620:52:0:1305::101 ${OFFLINE_REG_HOSTNAME_FQDN}" >> /etc/hosts
echo "2620:52:0:1305::102 ${AI_HOSTNAME_FQDN}" >> /etc/hosts
echo "2620:52:0:1305::253 api.someone-test.test412.com console-openshift-console.apps.someone-test.test412.com oauth-openshift.apps.someone-test.test412.com prometheus-k8s-openshift-monitoring.apps.someone-test.test412.com" >> /etc/hosts

# Obtian the certificate from the repository
echo -n | openssl s_client -connect ${OFFLINE_REG_HOSTNAME_FQDN}:5000 -servername ${OFFLINE_REG_HOSTNAME_FQDN} | openssl x509 > $(pwd)/file.crt

# Copy certificate to the cert repository
sudo cp $(pwd)/file.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

# validate that the certificate is accessible from the ai.offline.redhat.lan
status_code=$(curl --write-out %{http_code} --silent -u admin:Sup3rR3gistry --output /dev/null https://${OFFLINE_REG_HOSTNAME_FQDN}:5000/v2/_catalog)
if [[ "$status_code" -ne 200 ]] ; then
        echo -e "\n Response Code changed to $status_code"
        exit 1
    else
        echo -e "\n Response Code is $status_code. The Offline Registry its reachable"

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

