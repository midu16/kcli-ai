# kcli-ai
IPv6 AI environment

- [kcli-ai](#kcli-ai)
  - [Preparing the environment](#preparing-the-environment)

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
- Creating the `registry.offline.redhat.lan.yaml`:
```bash
$ kcli create plan -f registry.offline.redhat.lan.yaml
```

