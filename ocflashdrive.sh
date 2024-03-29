#!/bin/bash
# Author: Broly
# License: GNU General Public License v3.0
# https://www.gnu.org/licenses/gpl-3.0.txt
# This script is intended to create an OpenCore USB-installer on Linux.

# This function clears the screen and checks if the user is root. If not, it will execute the script with sudo.
welcome(){
	clear
	printf "Welcome to the OpenCore USB-installer script.\n\n"
	[[ "$(whoami)" != "root" ]] && exec sudo -- "$0" "$@"
	set -e
}

# Get the USB drive selected by the user.
get_the_drive(){
	clear
	printf "Please select the USB drive to use:\n\n"
	readarray -t lines < <((lsblk -p -no name,size,MODEL,VENDOR,TRAN | grep "usb"))
	select choice in "${lines[@]}"; do
		[[ -n "$choice" ]] || { printf ">>> Invalid Selection!\n" >&2; continue; }
		break
	done
	read -r drive _ <<<"$choice"
	if [[ -z "$choice" ]]; then
		printf "Please insert the USB Drive and try again.\n"
		exit 1
	fi
}

# Ask user to confirm and continue installation.
confirm_continue(){
	while true; do
		printf " The disk '%s' will be erased,\n and the following tools will be installed:\n wget, curl and dosfstools.\n Do you want to proceed? [y/n]: " "$drive"
		read -r yn
		case $yn in
			[Yy]*)
				break
				;;
			[Nn]*) 
				printf "Exiting the script...\n"
				exit 
				;;
			*) 
				printf "Please answer yes or no.\n" 
				;;
		esac
	done
}

# Install dependencies based on the detected distribution
install_dependencies() {
    printf "Installing dependencies...\n\n"
    sleep 2s

    if [[ -f /etc/debian_version ]]; then
        for package in "wget" "curl" "dosfstools"; do
            if ! dpkg -s "$package" > /dev/null 2>&1; then
                apt install -y "$package"
            else
                printf "Package %s is already installed.\n" "$package"
            fi
        done
    elif [[ -f /etc/fedora-release ]]; then
        for package in "wget" "curl" "dosfstools"; do
            if ! rpm -q "$package" > /dev/null 2>&1; then
                dnf install -y "$package"
            else
                printf "Package %s is already installed.\n" "$package"
            fi
        done
    elif [[ -f /etc/arch-release ]]; then
        for package in "wget" "curl" "dosfstools"; do
            if ! pacman -Q "$package" > /dev/null 2>&1; then
                pacman -Sy --noconfirm --needed "$package"
            else
                printf "Package %s is already installed.\n" "$package"
            fi
        done
    elif [[ -f /etc/alpine-release ]]; then
        for package in "wget" "curl" "dosfstools"; do
            if ! apk info "$package" > /dev/null 2>&1; then
                apk add "$package"
            else
                printf "Package %s is already installed.\n" "$package"
            fi
        done
    elif [[ -f /etc/gentoo-release ]]; then
        for package in "wget" "curl" "dosfstools"; do
            if ! emerge --search "$package" | grep -q "^$package/"; then
                emerge --nospinner --oneshot --noreplace "$package"
            else
                printf "Package %s is already installed.\n" "$package"
            fi
        done
    else
        printf "Your distro is not supported!\n"
        exit 1
    fi
}

# Extract the macOS recovery image from the downloaded DMG file.
extract_recovery_dmg() {
	recovery_dir=com.apple.recovery.boot
	recovery_file1="$recovery_dir/BaseSystem.dmg"
	recovery_file2="$recovery_dir/RecoveryImage.dmg"
	rm -rf "$recovery_dir"/*.hfs
	printf "Downloading 7zip.\n"
	wget -O - "https://sourceforge.net/projects/sevenzip/files/7-Zip/23.01/7z2301-linux-x64.tar.xz" | tar -xJf - 7zz
	chmod +x 7zz

	if [ -e "$recovery_file1" ]; then
		printf "  Extracting Recovery...\n %s $recovery_file1!\n"
		./7zz e -bso0 -bsp1 -tdmg "$recovery_file1" -aoa -o"$recovery_dir" -- *.hfs; rm -rf 7zz
	elif [ -e "$recovery_file2" ]; then
		printf "\n  Extracting Recovery...\n %s $recovery_file2!\n"
		./7zz e -bso0 -bsp1 -tdmg "$recovery_file2" -aoa -o"$recovery_dir" -- *.hfs; rm -rf 7zz
	else
		printf "Please download the macOS Recovery with macrecovery!\n"
		exit 1
	fi
}

# Format the USB drive.
format_drive(){
	printf "Formatting the USB drive...\n\n"
	umount "$drive"* || :
	sleep 2s
	wipefs -af "$drive"
	sgdisk "$drive" --new=0:0:+300MiB -t 0:ef00 && partprobe
	sgdisk "$drive" --new=0:0: -t 0:af00 && partprobe
	mkfs.fat -F 32 "$drive"1
	sleep 2s
}

# Burn the macOS recovery image to the target drive
burning_drive(){
	myhfs=$(ls com.apple.recovery.boot/*.hfs)
	printf "Installing macOS recovery image...\n"
	dd bs=8M if="$myhfs" of="$drive"2 status=progress oflag=sync
	umount "$drive"?* || :
	sleep 3s
	printf "The macOS recovery image has been burned to the drive!\n"
}

# Install OpenCore to the target drive
Install_OC() {
	printf "Installing OpenCore to the drive...\n"
	mount_point="/mnt"
	new_mount_point="ocfd15364"

	# Check if the mount point directory is not empty
	if [ -n "$(ls -A "$mount_point")" ]; then
		# Create a new mount point if it's not empty
		mount_directory="${mount_point}/${new_mount_point}"
		mkdir -p "$mount_directory"
	fi

	# Mount the target drive
	mount -t vfat "$drive"1 "${mount_point}" -o rw,umask=000
	sleep 3s

	# Copy OpenCore EFI files
	cp -r ../../X64/EFI/ "${mount_point}"
	cp -r ../../Docs/Sample.plist "${mount_point}/EFI/OC/"
	clear
	printf " OpenCore has been installed to the drive!\n Please open '/mnt' and edit OC for your machine!!\n"
	ls -1 "${mount_point}/EFI/OC"
}

main() {
	welcome "$@"
	get_the_drive "$@"
	confirm_continue "$@"
	install_dependencies "$@"
	extract_recovery_dmg "$@"
	format_drive "$@"
	burning_drive "$@"
	Install_OC "$@"
}
main "$@"
