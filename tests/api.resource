*** Settings ***
Library    SSHLibrary

*** Keywords ***
Run task
    [Arguments]    ${action}    ${input}    ${decode_json}=${TRUE}    ${rc_expected}=0
    ${stdout}    ${stderr}    ${rc} =     Execute Command    api-cli run ${action} --data '${input}'    return_stdout=True    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc_expected}    ${rc}    Run task ${action} failed!${\n}${stderr}
    IF    ${decode_json} and len($stdout) > 0
        ${response} =    Evaluate    json.loads(r'''${stdout}''')    modules=json
    ELSE
        ${response} =    Set Variable    ${stdout}
    END
    RETURN    ${response}

Run on node
    [Documentation]    Run a shell command on the node, fail on a non-zero exit, return stdout.
    [Arguments]    ${command}
    ${stdout}    ${stderr}    ${rc} =    Execute Command    ${command}    return_stdout=True    return_stderr=True    return_rc=True
    Should Be Equal As Integers    ${rc}    0    Command failed: ${command}${\n}${stdout}${\n}${stderr}
    RETURN    ${stdout}

Secrets are kept out of the module environment
    [Documentation]    NethServer convention: no password, token or key in
    ...                state/environment (mirrored to Redis in plain text);
    ...                they live in state/passwords.env, mode 0600.
    [Arguments]    ${mid}
    ${mode} =    Run on node    runagent -m ${mid} bash -c 'stat -c %a "$AGENT_STATE_DIR/passwords.env"'
    Should Be Equal As Strings    ${mode.strip()}    600
    ${leaks} =    Run on node    runagent -m ${mid} bash -c 'cut -d= -f1 "$AGENT_STATE_DIR/environment" | grep -Eci "PASS|SECRET|TOKEN|_KEY$|INVITATION" || true'
    Should Be Equal As Integers    ${leaks.strip()}    0    secret-looking keys left in state/environment
    ${leaks} =    Run on node    redis-cli --raw HKEYS module/${mid}/environment | grep -Eci "PASS|SECRET|TOKEN|_KEY$|INVITATION" || true
    Should Be Equal As Integers    ${leaks.strip()}    0    secret-looking keys left in the Redis environment hash

Back up the module to the cluster repository
    [Documentation]    Create a backup repository on the node's own cluster
    ...                endpoint, back the instance up once, return repo + path.
    [Arguments]    ${mid}
    ${eps} =    Run task    cluster/list-cluster-backup-endpoints    {}
    ${url} =    Set Variable    ${eps['endpoints'][0]['url']}
    ${repo} =    Run task    cluster/add-backup-repository
    ...    {"name":"ci-repo","provider":"cluster","url":"${url}","password":"","parameters":{}}
    ${repo_id} =    Set Variable    ${repo['id']}
    ${bid} =    Run task    cluster/add-backup
    ...    {"name":"ci-backup","repository":"${repo_id}","schedule":"daily","schedule_hint":{},"retention":2,"instances":["${mid}"],"enabled":true}
    Run task    cluster/run-backup    {"id": ${bid}}    decode_json=${FALSE}
    ${env} =    Run on node    runagent -m ${mid} bash -c 'echo "$IMAGE_URL $MODULE_UUID"'
    ${image_url}    ${uuid} =    Evaluate    $env.split()
    ${name} =    Evaluate    $image_url.rsplit('/', 1)[-1].split(':')[0].split('@')[0]
    RETURN    ${repo_id}    ${name}/${uuid}

Restore the module from the cluster repository
    [Arguments]    ${repo_id}    ${path}
    ${out} =    Run task    cluster/restore-module
    ...    {"repository":"${repo_id}","path":"${path}","snapshot":"","node":1,"replace":false}
    RETURN    ${out['module_id']}
