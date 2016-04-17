#!/bin/bash

# shared functions library

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )


function pause(){
    read -p "$*"
}


function sshkey(){
# add ssh key to *.toml files
echo " "
echo "Reading ssh key from $HOME/.ssh/id_rsa.pub  "
file="$HOME/.ssh/id_rsa.pub"

while [ ! -f "$file" ]
do
echo " "
echo "$file not found."
echo "please run 'ssh-keygen -t rsa' before you continue !!!"
pause 'Press [Enter] key to continue...'
done

echo " "
echo "$file found, updating configuration files ..."
echo "   sshkey = '$(cat $HOME/.ssh/id_rsa.pub)'" >> ~/coreos-osx/settings/core-01.toml
#
}


function release_channel(){
# Set release channel
LOOP=1
while [ $LOOP -gt 0 ]
do
    VALID_MAIN=0
    echo " "
    echo "Set CoreOS Release Channel:"
    echo " 1)  Alpha (may not always function properly) "
    echo " 2)  Beta "
    echo " 3)  Stable (recommended)"
    echo " "
    echo -n "Select an option: "

    read RESPONSE
    XX=${RESPONSE:=Y}

    if [ $RESPONSE = 1 ]
    then
        VALID_MAIN=1
        sed -i "" 's/channel = "stable"/channel = "alpha"/g' ~/coreos-osx/settings/*.toml
        sed -i "" 's/channel = "beta"/channel = "alpha"/g' ~/coreos-osx/settings/*.toml
        channel="Alpha"
        LOOP=0
    fi

    if [ $RESPONSE = 2 ]
    then
        VALID_MAIN=1
        sed -i "" 's/channel = "stable"/channel = "beta"/g' ~/coreos-osx/settings/*.toml
        sed -i "" 's/channel = "alpha"/channel = "beta"/g' ~/coreos-osx/settings/*.toml
        channel="Beta"
        LOOP=0
    fi

    if [ $RESPONSE = 3 ]
    then
        VALID_MAIN=1
        sed -i "" 's/channel = "beta"/channel = "stable"/g' ~/coreos-osx/settings/*.toml
        sed -i "" 's/channel = "alpha"/channel = "stable"/g' ~/coreos-osx/settings/*.toml
        channel="Stable"
        LOOP=0
    fi

    if [ $VALID_MAIN != 1 ]
    then
        continue
    fi
done
}


create_data_disk() {
# path to the bin folder where we store our binary files
export PATH=${HOME}/coreos-osx/bin:$PATH

# create persistent disk
cd ~/coreos-osx/
echo "  "
echo "Please type Data disk size in GBs followed by [ENTER]:"
echo -n "[default is 15]: "
read disk_size
if [ -z "$disk_size" ]
then
    echo " "
    echo "Creating 15GB disk (it could take a while for big disks)..."
#    mkfile 15g data.img
    pv -s 15g -S < /dev/zero > data.img
#    echo "-"
    echo "Created 15GB Data disk"
else
    echo " "
    echo "Creating "$disk_size"GB disk (it could take a while for big disks)..."
#    mkfile "$disk_size"g data.img
    pv -s "$disk_size"g -S < /dev/zero > data.img
#    echo "-"
    echo "Created "$disk_size"GB Data disk"
fi
#

}

function download_osx_docker() {

CHECK_DOCKER_RC=$(echo $DOCKER_VERSION | grep rc)
if [ -n "$CHECK_DOCKER_RC" ]
then
    # docker RC release
    if [ -n "$(curl -s --head https://test.docker.com/builds/Darwin/x86_64/docker-$DOCKER_VERSION | head -n 1 | grep "HTTP/1.[01] [23].." | grep 200)" ]
    then
        # we check if RC is still available
        echo " "
        echo "Downloading docker $DOCKER_VERSION client for OS X"
        curl -o ~/coreos-osx/bin/docker https://test.docker.com/builds/Darwin/x86_64/docker-$DOCKER_VERSION
    else
        # RC is not available anymore, so we download stable release
        echo " "
        DOCKER_VERSION_STABLE=$(echo $DOCKER_VERSION | cut -d"-" -f1)
        echo "Downloading docker $DOCKER_VERSION_STABLE client for OS X"
        curl -o ~/coreos-osx/bin/docker https://get.docker.com/builds/Darwin/x86_64/docker-$DOCKER_VERSION_STABLE
    fi
else
# docker stable release
echo "Downloading docker $DOCKER_VERSION client for OS X"
curl -o ~/coreos-osx/bin/docker https://get.docker.com/builds/Darwin/x86_64/docker-$DOCKER_VERSION
fi
# Make it executable
chmod +x ~/coreos-osx/bin/docker

}


function download_osx_clients() {
# download fleetctl file
FLEETCTL_VERSION=$("${res_folder}"/bin/corectl ssh core-01 'fleetctl --version' | awk '{print $3}' | tr -d '\r')
# check if the binary exists
if [ ! -f ~/coreos-osx/bin/fleetctl ]; then
    cd ~/coreos-osx/bin
    echo "Downloading fleetctl v$FLEETCTL_VERSION for OS X"
    curl -L -o fleet.zip "https://github.com/coreos/fleet/releases/download/v$FLEETCTL_VERSION/fleet-v$FLEETCTL_VERSION-darwin-amd64.zip"
    unzip -j -o "fleet.zip" "fleet-v$FLEETCTL_VERSION-darwin-amd64/fleetctl" > /dev/null 2>&1
    rm -f fleet.zip
    osx_clients_upgrade=1
else
    # we check the version of the binary
    INSTALLED_VERSION=$(~/coreos-osx/bin/fleetctl --version | awk '{print $3}' | tr -d '\r')
    MATCH=$(echo "${INSTALLED_VERSION}" | grep -c "${FLEETCTL_VERSION}")
    if [ $MATCH -eq 0 ]; then
        # the version is different
        cd ~/coreos-osx/bin
        echo "Downloading fleetctl v$FLEETCTL_VERSION for OS X"
        curl -L -o fleet.zip "https://github.com/coreos/fleet/releases/download/v$FLEETCTL_VERSION/fleet-v$FLEETCTL_VERSION-darwin-amd64.zip"
        unzip -j -o "fleet.zip" "fleet-v$FLEETCTL_VERSION-darwin-amd64/fleetctl" > /dev/null 2>&1
        rm -f fleet.zip
        osx_clients_upgrade=1
    else
        echo " "
        echo "OS X fleetctl client is up to date with VM's version ..."
    fi
fi

# download docker file
# check docker server version
DOCKER_VERSION=$("${res_folder}"/bin/corectl ssh core-01 'docker version' | grep 'Version:' | awk '{print $2}' | tr -d '\r' | sed -n 2p )
# check if the binary exists
if [ ! -f ~/coreos-osx/bin/docker ]; then
    cd ~/coreos-osx/bin
    download_osx_docker
    osx_clients_upgrade=1
else
    # docker client version
    INSTALLED_VERSION=$(~/coreos-osx/bin/docker version | grep 'Version:' | awk '{print $2}' | tr -d '\r' | head -1 )
    MATCH=$(echo "${INSTALLED_VERSION}" | grep -c "${DOCKER_VERSION}")
    if [ $MATCH -eq 0 ]; then
        # the version is different
        cd ~/coreos-osx/bin
        download_osx_docker
        osx_clients_upgrade=1
    else
        echo " "
        echo "OS X docker client is up to date with VM's version ..."
    fi
fi


}


function deploy_fleet_units() {
# deploy fleet units from ~/coreos-osx/fleet
if [ "$(ls ~/coreos-osx/fleet | grep -o -m 1 service)" = "service" ]
then
    cd ~/coreos-osx/fleet
    echo "Starting all fleet units in ~/coreos-osx/fleet:"
    fleetctl submit *.service
    fleetctl start *.service
    echo " "
fi
}


function deploy_my_fleet_units() {
# deploy fleet units from ~/coreos-osx/fleet
if [ "$(ls ~/coreos-osx/my_fleet | grep -o -m 1 service)" = "service" ]
then
    cd ~/coreos-osx/my_fleet
    echo "Starting all fleet units in ~/coreos-osx/my_fleet:"
    fleetctl start *.service
    echo " "
fi
}


function save_password {
# save user's password to Keychain
echo "  "
echo "Your Mac user's password will be saved in to 'Keychain' "
echo "and later one used for 'sudo' command to start VM !!!"
echo " "
echo "This is not the password to access VM via ssh or console !!!"
echo " "
echo "Please type your Mac user's password followed by [ENTER]:"
read -s -r my_password
passwd_ok=0

# check if sudo password is correct
while [ ! $passwd_ok = 1 ]
do
    # reset sudo
    sudo -k
    # check sudo
    printf '%s\n' "$my_password" | sudo -Sv > /dev/null 2>&1
    CAN_I_RUN_SUDO=$(sudo -n uptime 2>&1|grep "load"|wc -l)
    if [ ${CAN_I_RUN_SUDO} -gt 0 ]
    then
        echo "The sudo password is fine !!!"
        echo " "
        passwd_ok=1
    else
        echo " "
        echo "The password you entered does not match your Mac user password !!!"
        echo "Please type your Mac user's password followed by [ENTER]:"
        read -s -r my_password
    fi
done

security add-generic-password -a coreos-osx-app -s coreos-osx-app -w $my_password -U

}


function clean_up_after_vm {
sleep 1

# path to the bin folder where we store our binary files
export PATH=${HOME}/coreos-osx/bin:$PATH

# get App's Resources folder
res_folder=$(cat ~/coreos-osx/.env/resouces_path)

# get password for sudo
my_password=$(security find-generic-password -wa coreos-osx-app)
# reset sudo
sudo -k
# enable sudo
printf '%s\n' "$my_password" | sudo -Sv > /dev/null 2>&1

# send halt to VM
sudo "${res_folder}"/bin/corectl halt core-01 > /dev/null 2>&1

# Stop docker registry
"${res_folder}"/docker_registry.sh stop
kill $(ps aux | grep "[r]egistry config.yml" | awk {'print $2'})

# kill all other scripts
pkill -f [C]oreOS GUI.app/Contents/Resources/fetch_latest_iso.command
pkill -f [C]oreOS GUI.app/Contents/Resources/update_osx_clients_files.command
pkill -f [C]oreOS GUI.app/Contents/Resources/change_release_channel.command

}

