<!--
  Copyright (C) 2026 tebbi
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("certificate.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <NsInlineNotification
          kind="info"
          :title="$t('certificate.intro')"
          :description="$t('certificate.intro_desc')"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>

    <!-- current signing certificate -->
    <cv-row>
      <cv-column class="page-subtitle">
        <h4>{{ $t("certificate.current") }}</h4>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-skeleton-text
            v-if="loading.getConfiguration"
            :paragraph="true"
            :line-count="4"
          ></cv-skeleton-text>
          <NsEmptyState
            v-else-if="!cert.present"
            :title="$t('certificate.no_certificate')"
          ></NsEmptyState>
          <cv-structured-list v-else>
            <template slot="items">
              <cv-structured-list-item>
                <cv-structured-list-data>{{
                  $t("certificate.subject")
                }}</cv-structured-list-data>
                <cv-structured-list-data class="break-word">{{
                  cert.subject
                }}</cv-structured-list-data>
              </cv-structured-list-item>
              <cv-structured-list-item>
                <cv-structured-list-data>{{
                  $t("certificate.root_ca")
                }}</cv-structured-list-data>
                <cv-structured-list-data class="break-word">{{
                  cert.root_ca_cn
                }}</cv-structured-list-data>
              </cv-structured-list-item>
              <cv-structured-list-item>
                <cv-structured-list-data>{{
                  $t("certificate.valid_until")
                }}</cv-structured-list-data>
                <cv-structured-list-data>{{
                  cert.not_after
                }}</cv-structured-list-data>
              </cv-structured-list-item>
              <cv-structured-list-item>
                <cv-structured-list-data>{{
                  $t("certificate.fingerprint")
                }}</cv-structured-list-data>
                <cv-structured-list-data class="break-word mono">{{
                  cert.fingerprint
                }}</cv-structured-list-data>
              </cv-structured-list-item>
            </template>
          </cv-structured-list>
          <div v-if="cert.present && certchainUrl" class="actions">
            <NsButton
              kind="ghost"
              :icon="Download20"
              @click="openCertchain"
              >{{ $t("certificate.download_chain") }}</NsButton
            >
          </div>
        </cv-tile>
      </cv-column>
    </cv-row>

    <!-- self test -->
    <cv-row>
      <cv-column class="page-subtitle">
        <h4>{{ $t("certificate.selftest") }}</h4>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <p class="helper">{{ $t("certificate.selftest_desc") }}</p>
          <div v-if="selftest" class="selftest-result">
            <NsInlineNotification
              :kind="selftestOk ? 'success' : 'warning'"
              :title="selftestOk ? $t('certificate.selftest_ok') : $t('certificate.selftest_fail')"
              :description="selftestSummary"
              :showCloseButton="false"
            />
          </div>
          <div class="actions">
            <NsButton
              kind="primary"
              :icon="Play20"
              :loading="loading.selfTest"
              :disabled="loading.selfTest"
              @click="runSelfTest"
              >{{ $t("certificate.run_selftest") }}</NsButton
            >
          </div>
        </cv-tile>
      </cv-column>
    </cv-row>

    <!-- rotate -->
    <cv-row>
      <cv-column class="page-subtitle">
        <h4>{{ $t("certificate.rotate") }}</h4>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <NsInlineNotification
            kind="warning"
            :title="$t('certificate.rotate_warning')"
            :description="$t('certificate.rotate_warning_desc')"
            :showCloseButton="false"
          />
          <cv-text-input
            :label="$t('certificate.root_cn_label')"
            v-model.trim="rootCn"
            :helper-text="$t('certificate.root_cn_helper')"
            :disabled="loading.regenerate"
            class="field"
          ></cv-text-input>
          <div v-if="error.regenerate">
            <NsInlineNotification
              kind="error"
              :title="$t('action.regenerate-certificate')"
              :description="error.regenerate"
              :showCloseButton="false"
            />
          </div>
          <div class="actions">
            <NsButton
              kind="danger"
              :icon="Renew20"
              :loading="loading.regenerate"
              :disabled="loading.regenerate"
              @click="isRotateModalOpen = true"
              >{{ $t("certificate.rotate_button") }}</NsButton
            >
          </div>
        </cv-tile>
      </cv-column>
    </cv-row>

    <!-- upload -->
    <cv-row>
      <cv-column class="page-subtitle">
        <h4>{{ $t("certificate.upload") }}</h4>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <p class="helper">{{ $t("certificate.upload_desc") }}</p>
          <cv-text-area
            :label="$t('certificate.upload_chain')"
            v-model="upload.chain"
            :placeholder="'-----BEGIN CERTIFICATE-----'"
            :helper-text="$t('certificate.upload_chain_helper')"
            :disabled="loading.upload"
            rows="6"
            class="field mono"
          ></cv-text-area>
          <div class="file-row">
            <label class="file-label">{{
              $t("certificate.upload_chain_file")
            }}</label>
            <input
              type="file"
              accept=".pem,.crt,.cer,.txt"
              :disabled="loading.upload"
              @change="onChainFile"
            />
          </div>
          <div class="file-row">
            <label class="file-label">{{
              $t("certificate.upload_key_file")
            }}</label>
            <input
              type="file"
              accept=".pem,.key,.txt"
              :disabled="loading.upload"
              @change="onKeyFile"
            />
            <span v-if="upload.keyName" class="file-name">{{
              upload.keyName
            }}</span>
          </div>
          <cv-text-input
            type="password"
            :label="$t('certificate.upload_passphrase')"
            v-model="upload.passphrase"
            :helper-text="$t('certificate.upload_passphrase_helper')"
            :disabled="loading.upload"
            class="field"
          ></cv-text-input>
          <div v-if="error.upload">
            <NsInlineNotification
              kind="error"
              :title="$t('action.upload-certificate')"
              :description="error.upload"
              :showCloseButton="false"
            />
          </div>
          <div class="actions">
            <NsButton
              kind="primary"
              :icon="Upload20"
              :loading="loading.upload"
              :disabled="loading.upload || !upload.chain || !upload.key"
              @click="uploadCertificate"
              >{{ $t("certificate.upload_button") }}</NsButton
            >
          </div>
        </cv-tile>
      </cv-column>
    </cv-row>

    <!-- rotate confirmation modal -->
    <NsModal
      size="default"
      :visible="isRotateModalOpen"
      @modal-hidden="isRotateModalOpen = false"
      @primary-click="regenerateCertificate"
    >
      <template slot="title">{{ $t("certificate.rotate_button") }}</template>
      <template slot="content">
        <NsInlineNotification
          kind="warning"
          :title="$t('certificate.rotate_warning')"
          :description="$t('certificate.rotate_confirm_desc')"
          :showCloseButton="false"
        />
      </template>
      <template slot="secondary-button">{{ $t("common.cancel") }}</template>
      <template slot="primary-button">{{
        $t("certificate.rotate_button")
      }}</template>
    </NsModal>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import Download20 from "@carbon/icons-vue/es/download/20";
import Renew20 from "@carbon/icons-vue/es/renew/20";
import Upload20 from "@carbon/icons-vue/es/upload/20";
import Play20 from "@carbon/icons-vue/es/play/20";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

export default {
  name: "Certificate",
  components: {},
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("certificate.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "certificate",
      },
      urlCheckInterval: null,
      Download20,
      Renew20,
      Upload20,
      Play20,
      certchainUrl: "",
      rootCn: "",
      isRotateModalOpen: false,
      cert: {
        present: false,
        subject: "",
        root_ca_cn: "",
        not_after: "",
        fingerprint: "",
      },
      selftest: null,
      upload: {
        chain: "",
        key: "",
        keyName: "",
        passphrase: "",
      },
      loading: {
        getConfiguration: false,
        selfTest: false,
        regenerate: false,
        upload: false,
      },
      error: {
        getConfiguration: "",
        selfTest: "",
        regenerate: "",
        upload: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    selftestOk() {
      return (
        this.selftest &&
        this.selftest.ping_ok &&
        this.selftest.granted &&
        this.selftest.verify_ok
      );
    },
    selftestSummary() {
      if (!this.selftest) return "";
      const s = this.selftest;
      const parts = [
        `/ping: ${s.ping_ok ? "OK" : "FAIL"}`,
        `HTTP: ${s.http_status || "-"}`,
        `Status: ${s.granted ? "Granted" : "-"}`,
        `verify: ${s.verify_ok ? "OK" : "FAIL"}`,
      ];
      return parts.join("  •  ") + (s.message ? `  —  ${s.message}` : "");
    },
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  created() {
    this.getConfiguration();
  },
  methods: {
    openCertchain() {
      window.open(this.certchainUrl, "_blank", "noopener");
    },
    onChainFile(event) {
      const file = event.target.files && event.target.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = (e) => {
        this.upload.chain = e.target.result;
      };
      reader.readAsText(file);
    },
    onKeyFile(event) {
      const file = event.target.files && event.target.files[0];
      if (!file) {
        this.upload.key = "";
        this.upload.keyName = "";
        return;
      }
      this.upload.keyName = file.name;
      const reader = new FileReader();
      reader.onload = (e) => {
        this.upload.key = e.target.result;
      };
      reader.readAsText(file);
    },
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    getConfigurationCompleted(taskContext, taskResult) {
      this.loading.getConfiguration = false;
      const c = taskResult.output;
      this.cert = {
        present: !!c.cert_present,
        subject: c.cert_subject || "",
        root_ca_cn: c.root_ca_cn || "",
        not_after: c.cert_not_after || "",
        fingerprint: c.cert_fingerprint || "",
      };
      this.certchainUrl = c.certchain_url || "";
      if (!this.rootCn) {
        this.rootCn = c.root_ca_cn || "";
      }
    },
    async runSelfTest() {
      this.loading.selfTest = true;
      this.error.selfTest = "";
      this.selftest = null;
      const taskAction = "self-test";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.selfTestAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.selfTestCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        this.error.selfTest = this.getErrorMessage(err);
        this.loading.selfTest = false;
      }
    },
    selfTestAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.selftest = { ping_ok: false, message: this.$t("error.generic_error") };
      this.loading.selfTest = false;
    },
    selfTestCompleted(taskContext, taskResult) {
      this.selftest = taskResult.output;
      this.loading.selfTest = false;
    },
    async regenerateCertificate() {
      this.isRotateModalOpen = false;
      this.loading.regenerate = true;
      this.error.regenerate = "";
      const taskAction = "regenerate-certificate";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.regenerateAborted
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.regenerateCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: { root_ca_cn: this.rootCn },
          extra: {
            title: this.$t("action." + taskAction),
            description: this.$t("common.processing"),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        this.error.regenerate = this.getErrorMessage(err);
        this.loading.regenerate = false;
      }
    },
    regenerateAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.regenerate = this.$t("error.generic_error");
      this.loading.regenerate = false;
    },
    regenerateCompleted() {
      this.loading.regenerate = false;
      this.selftest = null;
      this.getConfiguration();
    },
    async uploadCertificate() {
      this.loading.upload = true;
      this.error.upload = "";
      const taskAction = "upload-certificate";
      const eventId = this.getUuid();
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.uploadAborted
      );
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.uploadValidationFailed
      );
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.uploadCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: {
            chain: this.upload.chain,
            key: this.upload.key,
            passphrase: this.upload.passphrase,
          },
          extra: {
            title: this.$t("action." + taskAction),
            description: this.$t("common.processing"),
            eventId,
          },
        })
      );
      const err = res[0];
      if (err) {
        this.error.upload = this.getErrorMessage(err);
        this.loading.upload = false;
      }
    },
    uploadAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.upload = this.$t("error.generic_error");
      this.loading.upload = false;
    },
    uploadValidationFailed(validationErrors) {
      this.loading.upload = false;
      for (const e of validationErrors) {
        this.error.upload = this.$t("certificate." + e.error);
      }
    },
    uploadCompleted() {
      this.loading.upload = false;
      this.upload = { chain: "", key: "", keyName: "", passphrase: "" };
      this.selftest = null;
      this.getConfiguration();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";
.field {
  margin-top: $spacing-06;
}
.actions {
  margin-top: $spacing-06;
}
.helper {
  margin-bottom: $spacing-05;
  color: $text-02;
}
.file-row {
  margin-top: $spacing-05;
}
.file-label {
  display: block;
  margin-bottom: $spacing-03;
  font-size: 0.75rem;
  color: $text-02;
}
.file-name {
  margin-left: $spacing-03;
}
.break-word {
  word-wrap: break-word;
  max-width: 40vw;
}
.mono {
  font-family: "IBM Plex Mono", monospace;
}
.selftest-result {
  margin-bottom: $spacing-05;
}
</style>
