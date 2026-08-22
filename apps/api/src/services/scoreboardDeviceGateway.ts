import mqtt, {
  type IClientOptions,
  type MqttClient,
} from "mqtt";
import {
  buildScoreboardMqttCommandEnvelope,
  scoreboardMqttTopics,
  type ScoreboardDeviceCommand,
  type ScoreboardDeviceSnapshot,
  type ScoreboardMqttAcknowledgement,
  type ScoreboardMqttPresence,
  type ScoreboardMqttTelemetry,
} from "@sportsos/core";

export type ScoreboardDeviceRuntime = {
  deviceId: string;
  state: ScoreboardDeviceSnapshot | null;
  presence: ScoreboardMqttPresence | null;
  telemetry: ScoreboardMqttTelemetry | null;
  lastAcknowledgement: ScoreboardMqttAcknowledgement | null;
};

export type ScoreboardPresenceListener = (
  deviceId: string,
  online: boolean,
) => void | Promise<void>;

export class ScoreboardDeviceGateway {
  private readonly presenceListeners =
    new Set<ScoreboardPresenceListener>();

  private readonly client: MqttClient;
  private readonly devices =
    new Map<string, ScoreboardDeviceRuntime>();

  public constructor(options: {
    mqttUrl?: string;
    mqttOptions?: IClientOptions;
  } = {}) {
    const mqttUrl =
      options.mqttUrl ??
      process.env.MQTT_URL ??
      "mqtt://sportsos_mqtt:1883";

    this.client = mqtt.connect(mqttUrl, options.mqttOptions);

    this.client.on("connect", () => {
      this.client.subscribe([
        "sportsos/scoreboards/+/state",
        "sportsos/scoreboards/+/presence",
        "sportsos/scoreboards/+/telemetry",
        "sportsos/scoreboards/+/ack",
      ]);
    });

    this.client.on("message", (topic, payloadBuffer) => {
      this.handleMessage(topic, payloadBuffer.toString("utf8"));
    });
  }

  public onPresence(
    listener: ScoreboardPresenceListener,
  ): () => void {
    this.presenceListeners.add(
      listener,
    );

    return () => {
      this.presenceListeners.delete(
        listener,
      );
    };
  }

  public listDevices(): ScoreboardDeviceRuntime[] {
    return Array.from(
      this.devices.values(),
      (device) => structuredClone(device),
    );
  }

  public getDevice(deviceId: string): ScoreboardDeviceRuntime | null {
    const device = this.devices.get(deviceId);
    return device ? structuredClone(device) : null;
  }

  public async sendCommand(
    deviceId: string,
    command: ScoreboardDeviceCommand,
  ): Promise<void> {
    const mqttTopics = scoreboardMqttTopics(deviceId);
    const envelope =
      buildScoreboardMqttCommandEnvelope(deviceId, command);

    await new Promise<void>((resolve, reject) => {
      this.client.publish(
        mqttTopics.command,
        JSON.stringify(envelope),
        { qos: 1, retain: false },
        (error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        },
      );
    });
  }

  private ensureDevice(deviceId: string): ScoreboardDeviceRuntime {
    const current = this.devices.get(deviceId);
    if (current) {
      return current;
    }

    const created: ScoreboardDeviceRuntime = {
      deviceId,
      state: null,
      presence: null,
      telemetry: null,
      lastAcknowledgement: null,
    };

    this.devices.set(deviceId, created);
    return created;
  }

  private handleMessage(topic: string, payloadText: string): void {
    const match = topic.match(
      /^sportsos\/scoreboards\/([^/]+)\/(state|presence|telemetry|ack)$/,
    );

    if (!match) {
      return;
    }

    const deviceId = match[1];
    const kind = match[2];

    if (!deviceId || !kind) {
      return;
    }

    let payload: unknown;

    try {
      payload = JSON.parse(payloadText);
    } catch {
      return;
    }

    const device = this.ensureDevice(deviceId);

    switch (kind) {
      case "state":
        device.state = payload as ScoreboardDeviceSnapshot;
        break;
      case "presence": {
        const presence =
          payload as ScoreboardMqttPresence;

        device.presence =
          presence;

        for (
          const listener
          of this.presenceListeners
        ) {
          void listener(
            deviceId,
            presence.online,
          );
        }

        break;
      }
      case "telemetry":
        device.telemetry = payload as ScoreboardMqttTelemetry;
        break;
      case "ack":
        device.lastAcknowledgement =
          payload as ScoreboardMqttAcknowledgement;
        break;
    }
  }
}


export async function publishCommissioningSelfTestCommand(
  deviceId: string,
  command: {
    type: "COMMISSIONING_SELF_TEST";
    commandId: string;
    deviceId: string;
    requestedAt: string;
  },
): Promise<void> {
  const transport =
    (
      globalThis as unknown as {
        __sportsosScoreboardCommandPublisher?: (
          deviceId: string,
          payload: string,
        ) => Promise<void> | void;
      }
    ).__sportsosScoreboardCommandPublisher;

  if (!transport) {
    throw new Error(
      "Scoreboard command publisher is unavailable.",
    );
  }

  await transport(
    deviceId,
    JSON.stringify(
      command,
    ),
  );
}
