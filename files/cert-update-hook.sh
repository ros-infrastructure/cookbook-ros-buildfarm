#!/bin/sh

# Run after acme.sh certificate renewal to restart or reload processes which must be notified of the updated cert.
SERVICES="nginx"
for service in $SERVICES; do
	systemctl restart ${service}.service
done
