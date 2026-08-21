# uv

Used to service the `uv` tool for Python rules in the OneVizion platform.

## How to update installer script and prebuilt binaries

1. Go to https://github.com/astral-sh/uv/releases/ and download `uv-aarch64-unknown-linux-gnu.tar.gz` and `uv-x86_64-unknown-linux-gnu.tar.gz` from the latest release.
Then commit them to the repository.
2. Download `uv-installer.sh`: find uv-installer.sh in the latest release notes and download it.

   Pay attention that we have a modified version of the `uv-installer.sh` script to use it with prebuilt binaries from our repository.
   So, to update it, you need to download the original version and then modify it to use prebuilt binaries from our repository.
   The modified version is in the repository, so you can compare it with the original one and make necessary changes.

