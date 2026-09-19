*** Settings ***
Library     SSHLibrary
Resource    api.resource

*** Variables ***
${CONFIG}    {"host":"tsa.ci.test","lets_encrypt":false,"http2https":true}

*** Test Cases ***
Install the module
    IF    '${SCENARIO}' == 'update'
        ${output}  ${rc} =    Execute Command    add-module ${UPDATE_FROM} 1    return_rc=True
    ELSE
        ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1    return_rc=True
    END
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Global Variable    ${module_id}    ${output.module_id}

Configure the module
    Run task    module/${module_id}/configure-module    ${CONFIG}    decode_json=${FALSE}

The authority signs a timestamp
    Wait Until Keyword Succeeds    30 times    10 seconds    Timestamp is granted and verified    ${module_id}

Remember the signing certificate before the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}
    ${fp} =    Run on node    runagent -m ${module_id} bash -c 'sha256sum "$AGENT_STATE_DIR/certs/tsa-chain.pem" | cut -d" " -f1'
    Set Global Variable    ${CHAIN_BEFORE}    ${fp}

Update to the image under test
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}
    Run on node    api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${module_id}"]}'
    Wait Until Keyword Succeeds    30 times    10 seconds    Timestamp is granted and verified    ${module_id}
    # same key and chain: the migrated password still decrypts the key
    ${fp} =    Run on node    runagent -m ${module_id} bash -c 'sha256sum "$AGENT_STATE_DIR/certs/tsa-chain.pem" | cut -d" " -f1'
    Should Be Equal    ${fp}    ${CHAIN_BEFORE}

Configuration reads back
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${cfg['host']}    tsa.ci.test

The key password is not on the command line
    ${out} =    Run on node    ps -eo args | grep -c '[f]ile-signer-passwd' || true
    Should Be Equal As Integers    ${out.strip()}    0

Secrets are stored in passwords.env only
    Secrets are kept out of the module environment    ${module_id}

*** Keywords ***
Timestamp is granted and verified
    [Arguments]    ${mid}
    ${res} =    Run task    module/${mid}/self-test    {}
    Should Be True    ${res['granted']}    ${res}
    Should Be True    ${res['verify_ok']}    ${res}
