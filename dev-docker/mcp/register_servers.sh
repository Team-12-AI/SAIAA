#!/usr/bin/env bash

mcp_server_list=("calc" "email" "trello-apps" "trello-net")
app_dir="/hostmcp"
register_log_file=${app_dir}/register.log
ready=0

touch ${register_log_file}

if [ ! -f "$register_log_file" ]; then
    exit 1
fi

while [ $ready -eq 0 ]
do
    curl http://localhost:8080/metrics > ${register_log_file}
    exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        ready=1
    fi
done


if [[ $ready -eq 1 ]]; then
    for mcp_server in "${mcp_server_list[@]}"; do
        /mcpjungle register -c ${app_dir}/${mcp_server}.json >> ${register_log_file}  2>&1
    done
else
    exit 2
fi

exit 0
