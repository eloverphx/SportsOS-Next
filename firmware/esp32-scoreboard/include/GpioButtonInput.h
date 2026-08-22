#pragma once

#include <Arduino.h>

#include "ScoreboardControlInput.h"

namespace sportsos {

enum class ButtonActiveLevel : uint8_t {
  Low = LOW,
  High = HIGH,
};

enum class ButtonPinMode : uint8_t {
  Input = INPUT,
  InputPullup = INPUT_PULLUP,
#ifdef INPUT_PULLDOWN
  InputPulldown = INPUT_PULLDOWN,
#endif
};

struct GpioButtonBinding {
  uint8_t pin;
  ScoreboardControlInputType type;
  ButtonActiveLevel activeLevel;
  ButtonPinMode pinMode;
  uint32_t debounceMs;
};

struct GpioButtonEvent {
  uint8_t pin;
  ScoreboardControlInputType type;
  bool pressed;
  unsigned long occurredAtMs;
};

class GpioButtonInput {
 public:
  using EventCallback =
      void (*)(
          const GpioButtonEvent& event,
          void* context);

  GpioButtonInput(
      const GpioButtonBinding* bindings,
      size_t bindingCount);

  void begin();

  void setCallback(
      EventCallback callback,
      void* context);

  void poll(
      unsigned long nowMs);

  size_t bindingCount() const;

 private:
  struct ButtonState {
    int rawLevel;
    int stableLevel;
    unsigned long lastRawChangeMs;
    bool initialized;
  };

  const GpioButtonBinding* bindings_;
  size_t bindingCount_;
  ButtonState* states_;
  EventCallback callback_;
  void* callbackContext_;

  bool isPressed(
      const GpioButtonBinding& binding,
      int level) const;

  void emit(
      size_t index,
      bool pressed,
      unsigned long nowMs);
};

}  // namespace sportsos
