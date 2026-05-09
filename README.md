# nicfragale-rut956

Cross-compiler script for building [OpenZiti](https://openziti.io/) `ziti-edge-tunnel` on the **Teltonika RUT956** router.

Based on [NicFragale/NetFoundry OpenZITI-OWRT](https://github.com/NicFragale/NetFoundry/tree/main/Utilities/OpenZITI-OWRT), adapted for the RUT956's MIPS little-endian architecture and Teltonika GPL SDK toolchain.

---

## Target Device

| Property | Value |
|---|---|
| Device | Teltonika RUT956 |
| CPU | MediaTek MT7628 — MIPS little-endian 24Kc (`mipsel_24kc`) |
| OS | OpenWRT (ramips/mt76x8) |
| libc | musl 1.2.4 |
| Toolchain | GCC 8.4.0 (`mipsel-openwrt-linux-musl`) |

## Pre-built Binary

`OpenWRT-RUT956-1.16.1.gz` — `ziti-edge-tunnel` v1.16.1, gzip-compressed.

```sh
# On the RUT956:
gunzip OpenWRT-RUT956-1.16.1.gz
chmod +x ziti-edge-tunnel
./ziti-edge-tunnel version
```

## Building from Source

### Prerequisites

- Teltonika GPL SDK at `/home/affan/teltonika/RUT9M_R_GPL_00.07.22.1/` (adjust path in script if different)
- Ubuntu/Debian host with standard build tools
- Internet access (clones VCPKG and ziti-tunnel-sdk-c)
- No `sudo` required at build time

### Usage

```sh
bash build_rut956.bash [version|latest] [branch]

# Examples:
bash build_rut956.bash           # build latest release
bash build_rut956.bash 1.16.1    # build specific version
bash build_rut956.bash latest main
```

Output is written to `~/teltonika/rut956-builds/OpenWRT-RUT956-{version}.gz`.

## Key Adaptations from Upstream

| Issue | Fix |
|---|---|
| Upstream uses `mips` triplet; RUT956 GCC triple is `mipsel-*` | Custom `mipsel-linux` VCPKG triplet and `ci-linux-mipsel` CMakePreset |
| OpenSSL perlasm MIPS routines do unaligned loads → SIGBUS on musl | OpenSSL overlay port injects `no-asm` |
| cmake 4.x rejects `target_link_libraries()` before target definition (protobuf + GCC 8 cross-compile) | Protobuf overlay forces `HAVE_BUILTIN_ATOMICS=ON` |
| 32-bit MIPS lacks native 64-bit atomic instructions | `VCPKG_LINKER_FLAGS=-latomic` in triplet |
| VCPKG Meson doesn't know `mipsel` arch (`stc` package) | Custom Meson cross-compilation INI file |
| `pcap/pcap.h` not in toolchain sysroot (pcap is dlopen'd at runtime) | Downloads `libpcap0.8-dev` headers via `apt-get download` (no sudo) and injects into VCPKG include path |
| VCPKG packages not found by cmake `FindOpenSSL`/`FindZLIB` | `CMAKE_FIND_ROOT_PATH` includes VCPKG install root in toolchain cmake |

## License

Build script is provided as-is. OpenZiti is licensed under the [Apache 2.0 License](https://github.com/openziti/ziti-tunnel-sdk-c/blob/main/LICENSE).
