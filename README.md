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

## Pre-built Binaries

| File | Size | Description |
|---|---|---|
| `OpenWRT-RUT956-1.16.1-stripped.gz` | 2.7 MB | **Recommended for deployment** — debug symbols stripped |
| `OpenWRT-RUT956-1.16.1.gz` | 4.3 MB | Full build with debug symbols |

## Deployment to Stock RUT956 Firmware

The RUT956's overlay filesystem has limited space (~2.4 MB free), so the binary lives in `/tmp` (tmpfs, 47 MB) and is re-downloaded on each boot by a `procd` init service. All heavy dependencies (OpenSSL, libsodium, libuv, protobuf) are statically linked — only musl libc is required from the system.

### Prerequisites

- SSH access to the RUT956 (root)
- A ziti identity file (`.json`) enrolled against your OpenZiti network
- Internet access from the router (to download the binary on boot)

### Steps

**1. Create the ziti directory and copy your identity**

```sh
ssh root@<RUT956-IP> "mkdir -p /etc/ziti"
scp your-identity.json root@<RUT956-IP>:/etc/ziti/identity.json
```

**2. Copy and run the installer**

```sh
scp install-ziti.sh root@<RUT956-IP>:/etc/ziti/
ssh root@<RUT956-IP> "chmod +x /etc/ziti/install-ziti.sh && /etc/ziti/install-ziti.sh"
```

The installer will:
- Download and decompress the stripped binary to `/tmp/ziti-edge-tunnel`
- Install `/etc/init.d/ziti` (procd service with auto-restart on crash)
- Enable the service to start on every boot
- Start the tunnel immediately

**3. Verify**

```sh
ssh root@<RUT956-IP> "logread | grep ziti"
ssh root@<RUT956-IP> "/tmp/ziti-edge-tunnel version"
```

### Service management

```sh
/etc/init.d/ziti start    # start
/etc/init.d/ziti stop     # stop
/etc/init.d/ziti restart  # restart
/etc/init.d/ziti disable  # remove from boot
logread | grep ziti        # logs
```

### How persistence works

On every reboot, the init.d service:
1. Checks if `/tmp/ziti-edge-tunnel` exists (it won't — `/tmp` is wiped on boot)
2. Downloads `OpenWRT-RUT956-1.16.1-stripped.gz` from this repo
3. Decompresses it to `/tmp/ziti-edge-tunnel`
4. Starts the tunnel with `/etc/ziti/identity.json`

The identity file and init service live in `/etc/ziti/` and `/etc/init.d/ziti`, both on the persistent jffs2 overlay partition.

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
