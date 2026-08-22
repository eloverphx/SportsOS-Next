#include "CommissioningSelfTestCommand.h"
#include "CommissioningSelfTest.h"
#include "GpioButtonInput.h"
#include <Arduino.h>
#include <WiFi.h>

#include "DeviceEnrollment.h"
#include "EnrollmentClient.h"
#include "FirmwareUpdateClient.h"
#include "FirmwareUpdateReporter.h"
#include "FirmwareBootHealth.h"
#include "FirmwareInstallPolicy.h"
#include "ProvisioningManager.h"
#include "ScoreboardRuntime.h"
#include "VerifiedRuntimeGate.h"
#include "ScoreboardControlInputClient.h"
#include "ScoreboardControlRetryQueue.h"

using sportsos::DeviceEnrollment;
using sportsos::DeviceEnrollmentIdentity;
using sportsos::EnrollmentClient;
using sportsos::EnrollmentClientConfig;
using sportsos::FirmwareUpdateClient;
using sportsos::FirmwareUpdateClientConfig;
using sportsos::PersistedRuntimeConfig;
using sportsos::ProvisioningManager;
using sportsos::RuntimeConfig;
using sportsos::ScoreboardRuntime;
using sportsos::VerifiedRuntimeGate;
using sportsos::FirmwareBootHealth;
using sportsos::FirmwareInstallDecision;
using sportsos::FirmwareInstallPolicy;
using sportsos::FirmwareInstallPolicyInput;
using sportsos::FirmwareUpdateReporter;
using sportsos::FirmwareUpdateReporterConfig;
using sportsos::ButtonActiveLevel;
using sportsos::ButtonPinMode;
using sportsos::GpioButtonBinding;
using sportsos::GpioButtonEvent;
using sportsos::GpioButtonInput;
using sportsos::ScoreboardControlInput;
using sportsos::ScoreboardControlInputType;
using sportsos::ScoreboardControlInputClient;
using sportsos::ScoreboardControlInputClientConfig;
using sportsos::ScoreboardControlSubmitResult;
using sportsos::ScoreboardControlRetryQueue;

#ifndef SPORTSOS_BUTTON_HOME_PLUS_PIN
#define SPORTSOS_BUTTON_HOME_PLUS_PIN 32
#endif

#ifndef SPORTSOS_BUTTON_HOME_MINUS_PIN
#define SPORTSOS_BUTTON_HOME_MINUS_PIN 33
#endif

#ifndef SPORTSOS_BUTTON_AWAY_PLUS_PIN
#define SPORTSOS_BUTTON_AWAY_PLUS_PIN 25
#endif

#ifndef SPORTSOS_BUTTON_AWAY_MINUS_PIN
#define SPORTSOS_BUTTON_AWAY_MINUS_PIN 26
#endif

#ifndef SPORTSOS_BUTTON_CLOCK_TOGGLE_PIN
#define SPORTSOS_BUTTON_CLOCK_TOGGLE_PIN 27
#endif

#ifndef SPORTSOS_BUTTON_PERIOD_PLUS_PIN
#define SPORTSOS_BUTTON_PERIOD_PLUS_PIN 14
#endif

#ifndef SPORTSOS_BUTTON_HORN_PIN
#define SPORTSOS_BUTTON_HORN_PIN 13
#endif

constexpr uint32_t
SPORTSOS_BUTTON_DEBOUNCE_MS = 40;

GpioButtonBinding scoreboardButtonBindings[] = {
    {
        SPORTSOS_BUTTON_HOME_PLUS_PIN,
        ScoreboardControlInputType::ScoreHomeIncrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_HOME_MINUS_PIN,
        ScoreboardControlInputType::ScoreHomeDecrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_AWAY_PLUS_PIN,
        ScoreboardControlInputType::ScoreAwayIncrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_AWAY_MINUS_PIN,
        ScoreboardControlInputType::ScoreAwayDecrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_CLOCK_TOGGLE_PIN,
        ScoreboardControlInputType::ClockToggle,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_PERIOD_PLUS_PIN,
        ScoreboardControlInputType::PeriodIncrement,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
    {
        SPORTSOS_BUTTON_HORN_PIN,
        ScoreboardControlInputType::HornTrigger,
        ButtonActiveLevel::Low,
        ButtonPinMode::InputPullup,
        SPORTSOS_BUTTON_DEBOUNCE_MS,
    },
};

ScoreboardControlRetryQueue scoreboardControlRetryQueue;

ScoreboardControlInputClient* scoreboardControlInputClient =
    nullptr;

uint32_t scoreboardControlSequence =
    0;

GpioButtonInput scoreboardButtons(
    scoreboardButtonBindings,
    sizeof(scoreboardButtonBindings) /
        sizeof(scoreboardButtonBindings[0]));

void onScoreboardButtonEvent(
    const GpioButtonEvent& event,
    void*) {
  /*
   * Milestone 14.2 intentionally emits only PRESS edges.
   * Transport/API submission is introduced in Milestone 14.3.
   */
  if (!event.pressed) {
    return;
  }

  if (
      scoreboardControlInputClient != nullptr
  ) {
    scoreboardControlSequence += 1;

    const auto submitResult =
        scoreboardControlInputClient->submit(
            event.type,
            scoreboardControlSequence,
            event.occurredAtMs);

    if (
        submitResult ==
          ScoreboardControlSubmitResult::TransportError ||
        submitResult ==
          ScoreboardControlSubmitResult::InvalidResponse
    ) {
      const bool queued =
          scoreboardControlRetryQueue.enqueue(
              event.type,
              scoreboardControlSequence,
              event.occurredAtMs,
              millis());

      Serial.print(
          "[CONTROL] queued=");

      Serial.println(
          queued
            ? "yes"
            : "queue-full");
    }

    Serial.print(
        "[CONTROL] submit=");

    Serial.println(
        static_cast<int>(
            submitResult));
  }

  Serial.print(
      "[CONTROL] pin=");

  Serial.print(
      event.pin);

  Serial.print(
      " type=");

  Serial.print(
      ScoreboardControlInput::typeText(
          event.type));

  Serial.print(
      " occurredAtMs=");

  Serial.println(
      event.occurredAtMs);
}


#ifndef SPORTSOS_FIRMWARE_VERSION
#define SPORTSOS_FIRMWARE_VERSION "0.13.4"
#endif

#ifndef SPORTSOS_API_BASE_URL
#define SPORTSOS_API_BASE_URL "http://192.168.5.3:4001"
#endif

ProvisioningManager provisioning;

ScoreboardRuntime* runtime =
    nullptr;

EnrollmentClient* enrollmentClient =
    nullptr;

FirmwareUpdateClient* firmwareUpdateClient =
    nullptr;

FirmwareUpdateReporter* firmwareUpdateReporter =
    nullptr;

VerifiedRuntimeGate runtimeGate;

FirmwareBootHealth bootHealth;

bool runtimeStarted =
    false;

PersistedRuntimeConfig persistedConfig;

void startAuthoritativeRuntime() {
  if (runtimeStarted) {
    return;
  }

  RuntimeConfig runtimeConfig{
      persistedConfig.deviceId.c_str(),
      persistedConfig.wifiSsid.c_str(),
      persistedConfig.wifiPassword.c_str(),
      persistedConfig.mqttHost.c_str(),
      persistedConfig.mqttPort,
      persistedConfig.mqttUsername.c_str(),
      persistedConfig.mqttPassword.c_str(),
      5000,
      3000,
      30000,
  };

  runtime =
      new ScoreboardRuntime(
          runtimeConfig);

  runtime->begin();

  runtimeStarted =
      true;

  if (
      bootHealth.requiresValidation()
  ) {
    bootHealth.confirmHealthy();
  }
}


static bool handleCommissioningSelfTestCommand(
    const String& payload,
    const String& localDeviceId,
    bool connectivityAvailable,
    String& telemetryJson) {
  sportsos::CommissioningSelfTestCommand command;

  if (
      !sportsos::CommissioningSelfTestCommandCodec::decode(
          payload,
          command)
  ) {
    return false;
  }

  if (
      command.deviceId !=
      localDeviceId
  ) {
    return false;
  }

  const auto telemetry =
      sportsos::CommissioningSelfTest::run(
          connectivityAvailable);

  telemetryJson =
      sportsos::CommissioningSelfTest::toJson(
          localDeviceId,
          command.commandId,
          telemetry);

  return true;
}

void setup() {
  scoreboardButtons.setCallback(
      onScoreboardButtonEvent,
      nullptr);

  scoreboardButtons.begin();

  ScoreboardControlInputClientConfig
      controlInputClientConfig{
          SPORTSOS_API_BASE_URL,
          persistedConfig.deviceId.c_str(),
      };

  scoreboardControlInputClient =
      new ScoreboardControlInputClient(
          controlInputClientConfig);

  bootHealth.begin();
  Serial.begin(
      115200);

  provisioning.begin();

  if (
      !provisioning.hasValidConfig()
  ) {
    return;
  }

  persistedConfig =
      provisioning.config();

  /*
   * Wi-Fi is required for enrollment transport, but authoritative
   * MQTT/game runtime is intentionally not started yet.
   */
  WiFi.mode(
      WIFI_STA);

  WiFi.begin(
      persistedConfig.wifiSsid.c_str(),
      persistedConfig.wifiPassword.c_str());

  const DeviceEnrollmentIdentity
      identity =
          DeviceEnrollment::buildIdentity(
              persistedConfig.deviceId.c_str());

  EnrollmentClientConfig
      enrollmentConfig{
          SPORTSOS_API_BASE_URL,
          10000,
      };

  enrollmentClient =
      new EnrollmentClient(
          enrollmentConfig,
          identity);

  enrollmentClient->begin();

  FirmwareUpdateClientConfig
      updateConfig{
          SPORTSOS_API_BASE_URL,
          persistedConfig.deviceId.c_str(),
          SPORTSOS_FIRMWARE_VERSION,
          "stable",
          "esp32dev",
          60000,
      };

  firmwareUpdateClient =
      new FirmwareUpdateClient(
          updateConfig);

  firmwareUpdateClient->begin();

  FirmwareUpdateReporterConfig
      reporterConfig{
          SPORTSOS_API_BASE_URL,
          persistedConfig.deviceId.c_str(),
          SPORTSOS_FIRMWARE_VERSION,
      };

  firmwareUpdateReporter =
      new FirmwareUpdateReporter(
          reporterConfig);
}

void loop() {
  if (
      scoreboardControlInputClient != nullptr
  ) {
    scoreboardControlRetryQueue.process(
        *scoreboardControlInputClient,
        millis());
  }

  scoreboardButtons.poll(
      millis());

  provisioning.loop();

  if (enrollmentClient != nullptr) {
    enrollmentClient->loop(
        WiFi.status() ==
        WL_CONNECTED);

    runtimeGate.evaluate(
        enrollmentClient->state());

    if (
        runtimeGate
          .allowAuthoritativeRuntime()
    ) {
      startAuthoritativeRuntime();
    }
  }

    if (
      firmwareUpdateClient != nullptr &&
      enrollmentClient != nullptr
  ) {
    firmwareUpdateClient->loop(
        WiFi.status() ==
          WL_CONNECTED,
        enrollmentClient->isVerified());
  }

if (
      runtimeStarted &&
      runtime != nullptr
  ) {
    runtime->loop();
  }

  /*
   * Milestone 13.6:
   * A staged image is activated only when enrollment is verified and
   * the runtime policy considers the reboot safe.
   */
  if (
      firmwareUpdateClient != nullptr &&
      enrollmentClient != nullptr &&
      firmwareUpdateClient->updateAvailable()
  ) {
    const auto& progress =
        firmwareUpdateClient->downloadProgress();

    const bool staged =
        progress.state ==
        sportsos::FirmwareUpdateState::ReadyToInstall;

    const FirmwareInstallPolicyInput
        policyInput{
            enrollmentClient->isVerified(),
            runtimeStarted,
            false,
            firmwareUpdateClient->updateAvailable(),
            staged,
            firmwareUpdateClient->offer().mandatory,
        };

    const auto decision =
        FirmwareInstallPolicy::evaluate(
            policyInput);

    if (
        decision ==
        FirmwareInstallDecision::ReadyToInstall
    ) {
      bootHealth.markPendingValidation();

      delay(100);

      ESP.restart();
    }
  }


  delay(5);
}
