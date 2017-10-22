#!/bin/bash

action="$@"

actions=(info create renew);

if [[ ${actions[*]} =~ $action ]]; then
    cmd="ruby /ssl-agent/home/acme-agent.rb $action"
else
    cmd=$action
fi

$cmd
