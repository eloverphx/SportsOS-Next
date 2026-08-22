#pragma once

#include <Arduino.h>

#include "FirmwareUpdateContract.h"

namespace sportsos {

enum class FirmwareDownloadResult : uint8_t {
  Success = 0,
  TransportError,
  HttpError,
  SizeMismatch,
  WriteError,
  Sha256Mismatch,
  FinalizeError,
};

struct FirmwareDownloadProgress {
  FirmwareUpdateState state;
  uint32_t bytesReceived;
  uint32_t totalBytes;
  uint8_t progressPercent;
  FirmwareDownloadResult result;
};

class FirmwareUpdateDownloader {
 public:
  FirmwareUpdateDownloader();

  FirmwareDownloadResult downloadAndStage(
      const char* apiBaseUrl,
      const FirmwareUpdateOffer& offer);

  const FirmwareDownloadProgress& progress() const;

 private:
  FirmwareDownloadProgress progress_;

  void resetProgress(
      uint32_t expectedSize);

  static String absoluteUrl(
      const char* apiBaseUrl,
      const char* firmwareUrl);

  static String bytesToHex(
      const uint8_t* bytes,
      size_t length);
};

}  // namespace sportsos
