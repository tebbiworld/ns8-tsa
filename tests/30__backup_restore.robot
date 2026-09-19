*** Settings ***
Library     SSHLibrary
Resource    api.resource

*** Test Cases ***
Back up the module
    ${fp} =    Run on node    runagent -m ${module_id} bash -c 'sha256sum "$AGENT_STATE_DIR/certs/tsa-chain.pem" | cut -d" " -f1'
    Set Global Variable    ${CHAIN_ORIG}    ${fp}
    ${repo}    ${path} =    Back up the module to the cluster repository    ${module_id}
    Set Global Variable    ${BACKUP_REPO}    ${repo}
    Set Global Variable    ${BACKUP_PATH}    ${path}

Remove the original instance
    # the restored instance takes over the same host name
    Run on node    remove-module --no-preserve ${module_id}

Restore into a new instance
    ${rid} =    Restore the module from the cluster repository    ${BACKUP_REPO}    ${BACKUP_PATH}
    Set Global Variable    ${restored_id}    ${rid}
    Set Global Variable    ${module_id}    ${rid}

The restored authority signs with the original key
    ${fp} =    Run on node    runagent -m ${restored_id} bash -c 'sha256sum "$AGENT_STATE_DIR/certs/tsa-chain.pem" | cut -d" " -f1'
    Should Be Equal    ${fp}    ${CHAIN_ORIG}
    Wait Until Keyword Succeeds    30 times    10 seconds    Restored timestamp is granted
    Secrets are kept out of the module environment    ${restored_id}

*** Keywords ***
Restored timestamp is granted
    ${res} =    Run task    module/${restored_id}/self-test    {}
    Should Be True    ${res['granted']}    ${res}
    Should Be True    ${res['verify_ok']}    ${res}
