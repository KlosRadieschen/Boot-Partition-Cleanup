# Boot Partition Cleanup
A script that cleans up the /boot partition on Red Hat based Linux distributions.

## Features
### Core features
- Remove old kernels, except for the two newest ones
- When the kernel is UEK, remove some unneeded dependencies
- Remove initramfs from removed kernels (including leftover kdump files)
- Remove redundant initramfs-rescue
- Check if Grub default entry is one of the remaining kernels
- If the above check fails, set the newest kernel as Grub default entry

### Additional features
- 4 levels of logging (silent, prompts only, info, debug)
- y/n confirmation for each potentially dangerous step (unless -y is set)

## Requirements
### OS requirements
This script was originally created for my company so as of right now, it is restricted to what we use:
- Any Linux distribution that has the yum/dnf package manager (Tested on RHEL and Oracle Linux)
- "kernel" or "kernel-uek". Kernels with another package name won't work
- Grub is the only supported bootloader

### Other requirements
- root permission on the machine

## Roadmap
- Better overall structure
- Support for more distros
- Support for more kernels
- Support for more bootloaders
- Additional flags for the points above
- Better comments?

## Contributions
Any contributions are welcome!

## License
You can do whatever you want with this but I am not responsible for any problems (The Unlicense)
