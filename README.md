# kcli-ai
IPv6 AI environment

- [kcli-ai](#kcli-ai)
  - [Preparing the environment](#preparing-the-environment)
  - [Preparing the `registry.offline.redhat.lan`](#preparing-the-registryofflineredhatlan)
  - [Preparing the `ai.offline.redhat.lan`](#preparing-the-aiofflineredhatlan)
  - [Preparing the `sno.offline.redhat.lan`](#preparing-the-snoofflineredhatlan)

## Preparing the environment

- Creating the IPv6 isolated subnet:
```bash
$ kcli create network -c "2620:52:0:1305::0/64" --domain offline.redhat.lan -i isolatednetwrk6
```

- Validating the subnet creation:
```bash
$ kcli list network
Listing Networks...
+-----------------+--------+---------------------+-------+---------------------------+----------+
| Network         |  Type  |         Cidr        |  Dhcp |           Domain          |   Mode   |
+-----------------+--------+---------------------+-------+---------------------------+----------+
| default         | routed |   192.168.122.0/24  |  True |          default          |   nat    |
| isolatednetwrk6 | routed | 2620:52:0:1305::/64 |  True |     offline.redhat.lan    | isolated |
+-----------------+--------+---------------------+-------+---------------------------+----------+
```

## Preparing the `registry.offline.redhat.lan` 

- Creating the `registry.offline.redhat.lan.yaml`:
```bash
$ kcli create plan -f registry.offline.redhat.lan.yaml
```

## Preparing the `ai.offline.redhat.lan`

- Encode the `onprem-iso-fcc.yaml`:

```bash
podman run --rm -v ./onprem-iso-fcc.yaml:/config.fcc:z quay.io/coreos/fcct:release --pretty --strict /config.fcc > onprem-iso-config.ign
```

- Append the secrets to the `onprem-iso-config.ign`:

```bash
export SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)
export PULL_SECRET_ENCODED=$(export PULL_SECRET=$(cat /apps/registry/pull-secret-connected.json); urlencode $PULL_SECRET)
export OFFLINE_REG_ENCODED_CERT=$(export OFFLINE_REG_CERT=$(echo -n | openssl s_client -connect inbacrnrdl0100.offline.oxtechnix.lan:5000 -servername inbacrnrdl0100.offline.oxtechnix.lan | openssl x509); urlencode $OFFLINE_REG_CERT)

sed -i 's#replace-with-your-ssh-public-key#'"${SSH_PUBLIC_KEY}"'#' onprem-iso-config.ign
sed -i 's#replace-with-your-urlencoded-pull-secret#'"${PULL_SECRET_ENCODED}"'#' onprem-iso-config.ign
sed -i 's#replace-with-your-offline-reg-cert#'"${OFFLINE_REG_ENCODED_CERT}"'#' onprem-iso-config.ign
```

- Download the `RHCOS-base.iso`:

```bash
wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.12/latest/rhcos-live.x86_64.iso
```

- Generate the `assisted-installer.iso`:

```bash
podman run --rm --privileged  -v /dev:/dev -v /run/udev:/run/udev -v .:/data  \
  quay.io/coreos/coreos-installer:release iso ignition embed -i /data/onprem-iso-config.ign -o /data/assisted-service.iso /data/rhcos-live.x86_64.iso
```


## Preparing the `sno.offline.redhat.lan`

