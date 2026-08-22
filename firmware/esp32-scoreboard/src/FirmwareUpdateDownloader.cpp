#include "FirmwareUpdateDownloader.h"

#include <HTTPClient.h>
#include <Update.h>
#include <WiFiClient.h>
#include <mbedtls/sha256.h>

namespace sportsos {

FirmwareUpdateDownloader::FirmwareUpdateDownloader() {
  resetProgress(0);
}

FirmwareDownloadResult
FirmwareUpdateDownloader::downloadAndStage(
    const char* apiBaseUrl,
    const FirmwareUpdateOffer& offer) {
  resetProgress(
      offer.firmwareSizeBytes);

  if (
      !FirmwareUpdateContract::validateOffer(
          offer)
  ) {
    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::SizeMismatch;

    return progress_.result;
  }

  HTTPClient http;

  const String url =
      absoluteUrl(
          apiBaseUrl,
          offer.firmwareUrl);

  if (!http.begin(url)) {
    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::TransportError;

    return progress_.result;
  }

  const int status =
      http.GET();

  if (
      status < 200 ||
      status >= 300
  ) {
    http.end();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::HttpError;

    return progress_.result;
  }

  const int contentLength =
      http.getSize();

  if (
      contentLength > 0 &&
      static_cast<uint32_t>(
          contentLength) !=
          offer.firmwareSizeBytes
  ) {
    http.end();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::SizeMismatch;

    return progress_.result;
  }

  if (
      !Update.begin(
          offer.firmwareSizeBytes)
  ) {
    http.end();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::WriteError;

    return progress_.result;
  }

  progress_.state =
      FirmwareUpdateState::Downloading;

  WiFiClient* stream =
      http.getStreamPtr();

  mbedtls_sha256_context
      sha256;

  mbedtls_sha256_init(
      &sha256);

  mbedtls_sha256_starts_ret(
      &sha256,
      0);

  uint8_t buffer[1024];

  while (
      http.connected() &&
      progress_.bytesReceived <
          offer.firmwareSizeBytes
  ) {
    const size_t available =
        stream->available();

    if (available == 0) {
      delay(1);
      continue;
    }

    const size_t remaining =
        offer.firmwareSizeBytes -
        progress_.bytesReceived;

    const size_t toRead =
        min(
            sizeof(buffer),
            min(
                available,
                remaining));

    const int read =
        stream->readBytes(
            buffer,
            toRead);

    if (read <= 0) {
      Update.abort();
      http.end();
      mbedtls_sha256_free(
          &sha256);

      progress_.state =
          FirmwareUpdateState::Failed;
      progress_.result =
          FirmwareDownloadResult::TransportError;

      return progress_.result;
    }

    mbedtls_sha256_update_ret(
        &sha256,
        buffer,
        static_cast<size_t>(
            read));

    const size_t written =
        Update.write(
            buffer,
            static_cast<size_t>(
                read));

    if (
        written !=
        static_cast<size_t>(
            read)
    ) {
      Update.abort();
      http.end();
      mbedtls_sha256_free(
          &sha256);

      progress_.state =
          FirmwareUpdateState::Failed;
      progress_.result =
          FirmwareDownloadResult::WriteError;

      return progress_.result;
    }

    progress_.bytesReceived +=
        static_cast<uint32_t>(
            read);

    progress_.progressPercent =
        static_cast<uint8_t>(
            (
                progress_.bytesReceived *
                100ULL
            ) /
            offer.firmwareSizeBytes);
  }

  http.end();

  if (
      progress_.bytesReceived !=
      offer.firmwareSizeBytes
  ) {
    Update.abort();
    mbedtls_sha256_free(
        &sha256);

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::SizeMismatch;

    return progress_.result;
  }

  progress_.state =
      FirmwareUpdateState::Verifying;

  uint8_t digest[32];

  mbedtls_sha256_finish_ret(
      &sha256,
      digest);

  mbedtls_sha256_free(
      &sha256);

  const String actualSha256 =
      bytesToHex(
          digest,
          sizeof(digest));

  if (
      !actualSha256.equalsIgnoreCase(
          offer.firmwareSha256)
  ) {
    Update.abort();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::Sha256Mismatch;

    return progress_.result;
  }

  progress_.state =
      FirmwareUpdateState::ReadyToInstall;

  /*
   * Update.end(true) is deliberately the final operation.
   * The OTA partition is not finalized/selected until after both
   * byte-count and SHA-256 verification succeed.
   */
  if (!Update.end(true)) {
    Update.abort();

    progress_.state =
        FirmwareUpdateState::Failed;
    progress_.result =
        FirmwareDownloadResult::FinalizeError;

    return progress_.result;
  }

  progress_.progressPercent =
      100;
  progress_.result =
      FirmwareDownloadResult::Success;

  return progress_.result;
}

const FirmwareDownloadProgress&
FirmwareUpdateDownloader::progress() const {
  return progress_;
}

void FirmwareUpdateDownloader::resetProgress(
    uint32_t expectedSize) {
  progress_ = {
      FirmwareUpdateState::Idle,
      0,
      expectedSize,
      0,
      FirmwareDownloadResult::Success,
  };
}

String FirmwareUpdateDownloader::absoluteUrl(
    const char* apiBaseUrl,
    const char* firmwareUrl) {
  const String candidate =
      firmwareUrl;

  if (
      candidate.startsWith(
          "http://") ||
      candidate.startsWith(
          "https://")
  ) {
    return candidate;
  }

  String base =
      apiBaseUrl;

  if (
      base.endsWith("/") &&
      candidate.startsWith("/")
  ) {
    base.remove(
        base.length() - 1);
  } else if (
      !base.endsWith("/") &&
      !candidate.startsWith("/")
  ) {
    base += "/";
  }

  return
      base +
      candidate;
}

String FirmwareUpdateDownloader::bytesToHex(
    const uint8_t* bytes,
    size_t length) {
  static const char* HEX_DIGITS =
      "0123456789abcdef";

  String result;

  result.reserve(
      length * 2);

  for (
      size_t index = 0;
      index < length;
      index += 1
  ) {
    result +=
        HEX_DIGITS[
            (
                bytes[index] >>
                4
            ) &
            0x0F];

    result +=
        HEX_DIGITS[
            bytes[index] &
            0x0F];
  }

  return result;
}

}  // namespace sportsos
