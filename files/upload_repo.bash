#!/bin/bash

case "$1" in
	main)
		user=ftpsync
		repo=ubuntu/main
		key=ros-push_id
		;;
	testing)
		user=ftpsync
		repo=ubuntu/testing
		key=ros-shadow-fixed-push_id
		;;
	rhel-main)
		user=ros
		repo=rhel/main
		key=ros-rhel-push_id
		;;
	rhel-testing)
		user=ros
		repo=rhel/testing
		key=ros-shadow-fixed-rhel-push_id
		;;
	*)
		echo "There is no upload configuration for '$1'."
		exit 1
esac

mkdir -p /var/repos/$repo/project/trace/
date -u > /var/repos/$repo/project/trace/repositories.ros.org
ssh -T -i $HOME/upload_triggers/$key $user@ftp-osl.osuosl.org
exit_code=$?
if [ $exit_code -eq 0 ]
then
    echo "exit code 0"
    date
    exit 0
fi
echo "unknown exit code $exit_code"
date
exit 1
