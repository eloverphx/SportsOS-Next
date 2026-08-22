import mqtt from "mqtt";

const MQTT_ROOT = "sportsos/scoreboards";
const PROTOCOL_VERSION = 1;

function topics(deviceId) {
  const base = `${MQTT_ROOT}/${deviceId}`;

  return {
    command: `${base}/command`,
    acknowledgement: `${base}/ack`,
    state: `${base}/state`,
    telemetry: `${base}/telemetry`,
    presence: `${base}/presence`,
  };
}

export function createInitialSimulatorState(deviceId) {
  return {
    protocolVersion: PROTOCOL_VERSION,
    deviceId,
    gameId: null,
    connectionState: "ONLINE",
    homeScore: 0,
    awayScore: 0,
    period: null,
    clock: {
      remainingMs: 0,
      running: false,
    },
    hornActive: false,
    updatedAt: new Date().toISOString(),
  };
}

export function applySimulatorCommand(state, envelope) {
  if (!envelope || typeof envelope !== "object") {
    throw new Error("Invalid command envelope.");
  }

  if (envelope.deviceId !== state.deviceId) {
    throw new Error("Command deviceId does not match simulator.");
  }

  const command = envelope.command;

  if (
    !command ||
    command.protocolVersion !== PROTOCOL_VERSION
  ) {
    throw new Error("Unsupported command protocol version.");
  }

  if (!command.commandId) {
    throw new Error("commandId is required.");
  }

  const next = structuredClone(state);

  switch (command.type) {
    case "SET_GAME":
      next.gameId = command.gameId ?? null;
      break;

    case "SET_SCORE":
      if (
        !Number.isInteger(command.homeScore) ||
        command.homeScore < 0 ||
        !Number.isInteger(command.awayScore) ||
        command.awayScore < 0
      ) {
        throw new Error("Invalid score command.");
      }

      next.homeScore = command.homeScore;
      next.awayScore = command.awayScore;
      break;

    case "SET_CLOCK":
      if (
        !Number.isFinite(command.remainingMs) ||
        command.remainingMs < 0
      ) {
        throw new Error("Invalid clock command.");
      }

      next.clock = {
        remainingMs: command.remainingMs,
        running: Boolean(command.running),
      };
      break;

    case "SET_PERIOD":
      if (
        command.period !== null &&
        (
          !Number.isInteger(command.period) ||
          command.period < 1
        )
      ) {
        throw new Error("Invalid period command.");
      }

      next.period = command.period;
      break;

    case "HORN":
      next.hornActive = Boolean(command.active);
      break;

    case "SYNC_STATE":
      next.gameId = command.snapshot.gameId ?? null;
      next.homeScore = command.snapshot.homeScore;
      next.awayScore = command.snapshot.awayScore;
      next.period = command.snapshot.period;
      next.clock = {
        remainingMs: command.snapshot.clock.remainingMs,
        running: Boolean(
          command.snapshot.clock.running,
        ),
      };
      next.hornActive = Boolean(
        command.snapshot.hornActive,
      );
      break;

    default:
      throw new Error(
        `Unsupported simulator command: ${command.type}`,
      );
  }

  next.updatedAt = new Date().toISOString();

  return next;
}

function publishJson(
  client,
  topic,
  payload,
  options,
) {
  client.publish(
    topic,
    JSON.stringify(payload),
    options,
  );
}

export function startScoreboardMqttAdapter(options = {}) {
  const deviceId =
    options.deviceId ??
    process.env.SCOREBOARD_DEVICE_ID ??
    "scoreboard-simulator-1";

  const mqttUrl =
    options.mqttUrl ??
    process.env.MQTT_URL ??
    "mqtt://sportsos_mqtt:1883";

  const mqttTopics = topics(deviceId);

  let state = createInitialSimulatorState(deviceId);

  const client = mqtt.connect(mqttUrl, {
    clientId: `${deviceId}-${Math.random()
      .toString(16)
      .slice(2, 10)}`,
    reconnectPeriod: 2000,
    will: {
      topic: mqttTopics.presence,
      payload: JSON.stringify({
        deviceId,
        online: false,
        reportedAt: new Date().toISOString(),
      }),
      qos: 1,
      retain: true,
    },
  });

  const publishState = () => {
    publishJson(
      client,
      mqttTopics.state,
      state,
      {
        qos: 1,
        retain: true,
      },
    );
  };

  const publishPresence = (online) => {
    publishJson(
      client,
      mqttTopics.presence,
      {
        deviceId,
        online,
        reportedAt: new Date().toISOString(),
      },
      {
        qos: 1,
        retain: true,
      },
    );
  };

  const publishTelemetry = () => {
    publishJson(
      client,
      mqttTopics.telemetry,
      {
        deviceId,
        firmwareVersion: "simulator-10.3",
        ipAddress: null,
        wifiRssi: null,
        uptimeSeconds: Math.floor(
          process.uptime(),
        ),
        freeHeapBytes:
          process.memoryUsage().heapUsed,
        reportedAt: new Date().toISOString(),
      },
      {
        qos: 0,
        retain: false,
      },
    );
  };

  client.on("connect", () => {
    state.connectionState = "ONLINE";
    state.updatedAt = new Date().toISOString();

    client.subscribe(
      mqttTopics.command,
      {
        qos: 1,
      },
    );

    publishPresence(true);
    publishState();
    publishTelemetry();
  });

  client.on("reconnect", () => {
    state.connectionState = "CONNECTING";
    state.updatedAt = new Date().toISOString();
  });

  client.on("offline", () => {
    state.connectionState = "OFFLINE";
    state.updatedAt = new Date().toISOString();
  });

  client.on(
    "message",
    (topic, payloadBuffer) => {
      if (topic !== mqttTopics.command) {
        return;
      }

      let envelope;

      try {
        envelope = JSON.parse(
          payloadBuffer.toString("utf8"),
        );

        publishJson(
          client,
          mqttTopics.acknowledgement,
          {
            deviceId,
            commandId:
              envelope?.command?.commandId ??
              "unknown",
            status: "ACCEPTED",
            message: null,
            acknowledgedAt:
              new Date().toISOString(),
          },
          {
            qos: 1,
            retain: false,
          },
        );

        state = applySimulatorCommand(
          state,
          envelope,
        );

        publishState();

        publishJson(
          client,
          mqttTopics.acknowledgement,
          {
            deviceId,
            commandId:
              envelope.command.commandId,
            status: "APPLIED",
            message: null,
            acknowledgedAt:
              new Date().toISOString(),
          },
          {
            qos: 1,
            retain: false,
          },
        );
      } catch (error) {
        publishJson(
          client,
          mqttTopics.acknowledgement,
          {
            deviceId,
            commandId:
              envelope?.command?.commandId ??
              "unknown",
            status: "REJECTED",
            message:
              error instanceof Error
                ? error.message
                : "Unknown simulator command error.",
            acknowledgedAt:
              new Date().toISOString(),
          },
          {
            qos: 1,
            retain: false,
          },
        );
      }
    },
  );

  const telemetryTimer = setInterval(
    publishTelemetry,
    30000,
  );

  return {
    client,
    deviceId,
    topics: mqttTopics,
    getState: () => structuredClone(state),
    stop: async () => {
      clearInterval(telemetryTimer);
      publishPresence(false);

      await new Promise((resolve) => {
        client.end(
          false,
          {},
          resolve,
        );
      });
    },
  };
}
