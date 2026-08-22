#include "SegmentDisplayBackend.h"

#include <Arduino.h>

namespace sportsos {

SegmentDisplayBackend::SegmentDisplayBackend(
    const ScoreboardHardwareProfile& profile,
    const SegmentBusConfig& bus)
    : NumericScoreboardDisplayDriver(profile),
      bus_(bus) {}

bool SegmentDisplayBackend::begin() {
  if (
      !validOutputPin(bus_.dataPin) ||
      !validOutputPin(bus_.clockPin) ||
      !validOutputPin(bus_.latchPin)
  ) {
    return false;
  }

  pinMode(bus_.dataPin, OUTPUT);
  pinMode(bus_.clockPin, OUTPUT);
  pinMode(bus_.latchPin, OUTPUT);

  digitalWrite(bus_.dataPin, LOW);
  digitalWrite(bus_.clockPin, LOW);
  digitalWrite(bus_.latchPin, LOW);

  return NumericScoreboardDisplayDriver::begin();
}

void SegmentDisplayBackend::writeNumericSnapshot(
    const NumericDisplaySnapshot& snapshot) {
  const uint8_t values[] = {
      static_cast<uint8_t>(snapshot.homeScore / 10),
      static_cast<uint8_t>(snapshot.homeScore % 10),
      static_cast<uint8_t>(snapshot.awayScore / 10),
      static_cast<uint8_t>(snapshot.awayScore % 10),
      snapshot.hasPeriod ? snapshot.period : 0,
      static_cast<uint8_t>(snapshot.clockMinutes / 10),
      static_cast<uint8_t>(snapshot.clockMinutes % 10),
      static_cast<uint8_t>(snapshot.clockSeconds / 10),
      static_cast<uint8_t>(snapshot.clockSeconds % 10),
  };

  digitalWrite(bus_.latchPin, LOW);

  for (const uint8_t value : values) {
    writeByte(encodeDigit(value));
  }

  digitalWrite(bus_.latchPin, HIGH);
}

void SegmentDisplayBackend::writeHornOutput(bool) {}

void SegmentDisplayBackend::writeHealthOutput(
    DisplayHealthState) {}

void SegmentDisplayBackend::writeByte(
    uint8_t value) {
  if (!bus_.activeHigh) {
    value = static_cast<uint8_t>(~value);
  }

  shiftOut(
      bus_.dataPin,
      bus_.clockPin,
      MSBFIRST,
      value);
}

uint8_t SegmentDisplayBackend::encodeDigit(
    uint8_t digit) {
  static constexpr uint8_t digits[] = {
      0b00111111,
      0b00000110,
      0b01011011,
      0b01001111,
      0b01100110,
      0b01101101,
      0b01111101,
      0b00000111,
      0b01111111,
      0b01101111,
  };

  if (digit > 9) {
    return 0;
  }

  return digits[digit];
}

bool SegmentDisplayBackend::validOutputPin(
    int8_t pin) {
  return pin >= 0 && pin <= 33;
}

}  // namespace sportsos
