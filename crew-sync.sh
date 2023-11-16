#!/bin/bash

{ read tractoradmin_un; read tractoradmin_pw; } < <(cat /run/secrets/tractor_admin)

# switch to config directory
cd "${CONFIG_DIR}"

function getGroupAsJsonList {
    # get users in format: "user1","user2","user3"
    getent group $1 \
    | cut -d ':' -f 4 \
    | sed 's/,/","/g' \
    | echo '"'$(cat)'"'
}

function cleanup {
    exit 0
}

trap cleanup SIGINT SIGTERM
touch ./admins
touch ./wranglers

function update {
    new_wranglers=$(getGroupAsJsonList "${WRANGLER_GROUP}")
    new_admins=$(getGroupAsJsonList "${ADMIN_GROUP}")

    RELOAD_CONFIG=false

    if ! echo "${new_wranglers}" | cmp -s - "./wranglers"; then
        # if new_wranglers does not match current list
        RELOAD_CONFIG=true
        echo "${new_wranglers}" > "./wranglers"
    fi

    if ! echo "${new_admins}" | cmp -s - "./admins"; then
        # if new_wranglers does not match current list
        RELOAD_CONFIG=true
        echo "${new_admins}" > "./admins"
    fi

    if [ "${RELOAD_CONFIG}" = true ]; then
        echo "Reloading crews config..."
        /opt/pixar/Tractor-2.4/bin/tq \
            --no-save-session \
            --user "${TRACTORADMIN_UN}" \
            --pw "${TRACTORADMIN_PW}" \
            --engine "engine:8080" \
            reloadconfig --crews
    fi
}

while true; do
    update
    sleep 60 &
    wait $!
done
