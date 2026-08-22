#include "GpioButtonInput.h"

namespace sportsos {

GpioButtonInput::GpioButtonInput(
    const GpioButtonBinding* bindings,
    size_t bindingCount)
    : bindings_(bindings),
      bindingCount_(bindingCount),
      states_(nullptr),
      callback_(nullptr),
      callbackContext_(nullptr) {}

void GpioButtonInput::begin() {
  delete[] states_;

  states_ =
      new ButtonState[bindingCount_];

  for (
      size_t index = 0;
      index < bindingCount_;
      ++index
  ) {
    const auto& binding =
        bindings_[index];

    pinMode(
        binding.pin,
        static_cast<uint8_t>(
            binding.pinMode));

    const int level =
        digitalRead(
            binding.pin);

    states_[index] = {
        level,
        level,
        millis(),
        true,
    };
  }
}

void GpioButtonInput::setCallback(
    EventCallback callback,
    void* context) {
  callback_ =
      callback;

  callbackContext_ =
      context;
}

void GpioButtonInput::poll(
    unsigned long nowMs) {
  if (
      states_ == nullptr ||
      bindings_ == nullptr
  ) {
    return;
  }

  for (
      size_t index = 0;
      index < bindingCount_;
      ++index
  ) {
    const auto& binding =
        bindings_[index];

    auto& state =
        states_[index];

    const int rawLevel =
        digitalRead(
            binding.pin);

    if (
        !state.initialized
    ) {
      state.rawLevel =
          rawLevel;

      state.stableLevel =
          rawLevel;

      state.lastRawChangeMs =
          nowMs;

      state.initialized =
          true;

      continue;
    }

    if (
        rawLevel !=
        state.rawLevel
    ) {
      state.rawLevel =
          rawLevel;

      state.lastRawChangeMs =
          nowMs;

      continue;
    }

    if (
        rawLevel ==
        state.stableLevel
    ) {
      continue;
    }

    if (
        nowMs -
            state.lastRawChangeMs <
        binding.debounceMs
    ) {
      continue;
    }

    state.stableLevel =
        rawLevel;

    emit(
        index,
        isPressed(
            binding,
            rawLevel),
        nowMs);
  }
}

size_t
GpioButtonInput::bindingCount() const {
  return bindingCount_;
}

bool GpioButtonInput::isPressed(
    const GpioButtonBinding& binding,
    int level) const {
  return
      level ==
      static_cast<int>(
          binding.activeLevel);
}

void GpioButtonInput::emit(
    size_t index,
    bool pressed,
    unsigned long nowMs) {
  if (
      callback_ == nullptr
  ) {
    return;
  }

  const auto& binding =
      bindings_[index];

  callback_(
      GpioButtonEvent{
          binding.pin,
          binding.type,
          pressed,
          nowMs,
      },
      callbackContext_);
}

}  // namespace sportsos
