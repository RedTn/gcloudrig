#!/usr/bin/env bash

# exit on error
set -e
set -x

# load globals
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source $DIR/globals.sh

# what zones are available in our region?
OLDIFS=$IFS
IFS=";"
ZONES=""
for ZONEURI in $(gcloud compute regions describe $REGION --format="value(zones)"); do
	ZONES=${ZONES},$(basename $ZONEURI)
done
IFS=$OLDIFS
ZONES=${ZONES:1}

# create a base instance template
gcloud beta compute instance-templates create "$INSTANCETEMPLATE-base" \
	--image=$(gcloud compute images describe-from-family $IMAGEBASEFAMILY --project $IMAGEBASEPROJECT --format "value(name)") \
	--image-project=$IMAGEBASEPROJECT \
	--machine-type=$INSTANCETYPE \
	--accelerator=$INSTANCEACCELERATOR \
	--boot-disk-size=$BOOTSIZE \
	--boot-disk-type=$BOOTTYPE \
	--maintenance-policy=TERMINATE \
	--no-boot-disk-auto-delete \
	--no-restart-on-failure \
	--quiet || echo 'blah'


# create actual instance template
gcloud beta compute instance-templates create "$INSTANCETEMPLATE" \
	--image=$IMAGE \
	--machine-type=$INSTANCETYPE \
	--accelerator=$INSTANCEACCELERATOR \
	--boot-disk-size=$BOOTSIZE \
	--boot-disk-type=$BOOTTYPE \
	--maintenance-policy=TERMINATE \
	--no-boot-disk-auto-delete \
	--no-restart-on-failure \
	--quiet || echo 'blah'

# create a managed instance group that covers all zones (GPUs tend to be oversubscribed in certain zones)
# and give it the base instance template
gcloud beta compute instance-groups managed create $INSTANCEGROUP \
	--base-instance-name=$INSTANCETEMPLATE \
	--template="$INSTANCETEMPLATE-base" \
	--size=0 \
	--region=$REGION \
	--zones="$ZONES" \
	--initial-delay=300 \
	--quiet || echo 'blah'

# turn it on
gcloudrig_start

# wait for 60 seconds, just in case
sleep 60

# get windows password
CREDENTIALS=$(gcloud compute reset-windows-password $INSTANCE \
		--user $USER \
		--zone $ZONE \
		--quiet \
		--format "table[box,title='Windows Credentials'](ip_address,username,password)" \
	)

# turn it off
gcloudrig_stop

# create boot disk snapshot with VSS
gcloud compute disks snapshot $BOOTDISK --guest-flush \
	--snapshot-names $BOOTSNAP \
	--zone $ZONE \
	--quiet

# delete boot disk
gcloud compute disks delete $BOOTDISK \
	--zone $ZONE \
	--quiet

# create boot image from boot snapshot
gcloud compute images create $IMAGE \
	--source-snapshot $BOOTSNAP \
	--guest-os-features WINDOWS \
	--quiet

# delete boot snapshot
gcloud compute snapshots delete $BOOTSNAP \
	--quiet

# set managed instance group to use the new image
gcloud compute instance-groups managed set-instance-template $INSTANCEGROUP \
	--template=$INSTANCETEMPLATE \
	--region=$REGION \
	--quiet

echo $CREDENTIALS
echo "Next steps: 
	- Create a disk called '$GAMESDISK'
	- Run \`./scale-up.sh\`
	- Use the above credentials to RDP to the instance
	- Install 'GRID® drivers for virtual workstations'
	- Enable auto login (start > run > 'control userpasswords2')
	- Install parsec, login, and set it to run on boot (right-click in the system tray)
	- Install zerotier and join a network (create a new one if you haven't used zerotier before)
	- Install TightVNC and lock it down to zerotier's IP range for difficult times
	- Reboot and try connect with parsec
	- Run \`./scale-down.sh\`"