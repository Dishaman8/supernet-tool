# Supernet Tool

Run the interactive IPv4 subnet calculator with:

```bash
./supernet-tool.sh
```

It supports equal subnetting by subnet count or usable host count, plus branch-specific VLSM subnetting. Every result lists the network ID, first and last usable addresses, and broadcast address.

For IPv6 calculations, run:

```bash
./supernetv6-tool.sh
```

The IPv6 tool supports the same equal and branch-specific workflows, including TXT export. IPv6 does not have broadcast addresses, so its table shows the last IPv6 address and subnet prefix instead.
