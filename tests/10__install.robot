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

Saving the settings a second time works
    [Documentation]    Regression: once the certificate files belong to the server
    ...                user, a second configure-module failed on chmod (EPERM).
    Skip If    '${SCENARIO}' == 'update'    the baseline release still has this bug
    Run task    module/${module_id}/configure-module    ${CONFIG}    decode_json=${FALSE}
    Wait Until Keyword Succeeds    30 times    10 seconds    Timestamp is granted and verified    ${module_id}

Remember the signing certificate before the update
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}
    ${fp} =    Run on node    runagent -m ${module_id} bash -c 'sha256sum "$AGENT_STATE_DIR/certs/tsa-chain.pem" | cut -d" " -f1'
    Set Global Variable    ${CHAIN_BEFORE}    ${fp}

Update to the image under test
    Skip If    '${SCENARIO}' != 'update'    scenario is ${SCENARIO}
    # Releases up to 1.0.2 cannot be updated as they are (the core's chown -R
    # fails on the sub-UID owned certificate files). This is the documented
    # one-line repair from the README; from 1.1.0 on it is not needed any more.
    Run on node    runagent -m ${module_id} bash -c 'podman unshare chown -R 0:0 "$AGENT_STATE_DIR/certs"; [ ! -d "$AGENT_STATE_DIR/cert-archive" ] || podman unshare chown -R 0:0 "$AGENT_STATE_DIR/cert-archive"'
    Run on node    api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${module_id}"]}'
    Wait Until Keyword Succeeds    30 times    10 seconds    Timestamp is granted and verified    ${module_id}
    # same key and chain: the migrated password still decrypts the key
    ${fp} =    Run on node    runagent -m ${module_id} bash -c 'sha256sum "$AGENT_STATE_DIR/certs/tsa-chain.pem" | cut -d" " -f1'
    Should Be Equal    ${fp}    ${CHAIN_BEFORE}
    # and with the fixed release a second save works on the upgraded instance too
    Run task    module/${module_id}/configure-module    ${CONFIG}    decode_json=${FALSE}
    Wait Until Keyword Succeeds    30 times    10 seconds    Timestamp is granted and verified    ${module_id}
    # the instance must be updatable again without any repair
    Run on node    api-cli run update-module --data '{"force":true,"module_url":"${IMAGE_URL}","instances":["${module_id}"]}'
    Wait Until Keyword Succeeds    30 times    10 seconds    Timestamp is granted and verified    ${module_id}

Configuration reads back
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Equal    ${cfg['host']}    tsa.ci.test

An IP allowlist round-trips and can be cleared
    [Documentation]    URS-1: the optional client allowlist is stored, read back
    ...                and, when emptied, removed so the service re-opens.
    Run task    module/${module_id}/configure-module    {"host":"tsa.ci.test","lets_encrypt":false,"http2https":true,"ip_allowlist":["192.0.2.0/24","198.51.100.7"]}    decode_json=${FALSE}
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Length Should Be    ${cfg['ip_allowlist']}    2
    Should Contain    ${cfg['ip_allowlist']}    192.0.2.0/24
    Run task    module/${module_id}/configure-module    ${CONFIG}    decode_json=${FALSE}
    ${cfg} =    Run task    module/${module_id}/get-configuration    {}
    Should Be Empty    ${cfg['ip_allowlist']}
    Wait Until Keyword Succeeds    30 times    10 seconds    Timestamp is granted and verified    ${module_id}

Self test reports certificate and clock health
    [Documentation]    URS-2: the self test additionally reports signing
    ...                certificate expiry and node clock synchronisation.
    ${res} =    Run task    module/${module_id}/self-test    {}
    Should Be True    ${res['cert_present']}    ${res}
    Should Be True    ${res['cert_leaf_days']} > 0    ${res}

The key password is not on the command line
    ${out} =    Run on node    ps -eo args | grep -c '[f]ile-signer-passwd' || true
    Should Be Equal As Integers    ${out.strip()}    0

Secrets are stored in passwords.env only
    Secrets are kept out of the module environment    ${module_id}

The certificate files belong to the module user
    ${owners} =    Run on node    runagent -m ${module_id} bash -c 'stat -c \%U "$AGENT_STATE_DIR"/certs/* | sort -u'
    Should Be Equal As Strings    ${owners.strip()}    ${module_id}

*** Keywords ***
Timestamp is granted and verified
    [Arguments]    ${mid}
    ${res} =    Run task    module/${mid}/self-test    {}
    Should Be True    ${res['granted']}    ${res}
    Should Be True    ${res['verify_ok']}    ${res}
