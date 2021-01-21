#!/bin/sh

available=$(df --output=avail -BG /var/lib/docker | awk '/[0-9]+G/ { print $1 + 0 }')
if [ $available -le 55 ]; then
	docker system prune --all --force
fi
