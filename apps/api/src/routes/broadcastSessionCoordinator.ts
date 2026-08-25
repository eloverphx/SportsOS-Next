import type {
  FastifyInstance,
} from "fastify";
import {
  listBroadcastCoordinatorAudit,
} from "../services/broadcastCoordinatorAudit.js";
import {
  listGoLiveAuditEvents,
} from "../services/goLiveAudit.js";
import {
  addBroadcastOperatorNote,
  listBroadcastOperatorNotes,
} from "../services/broadcastOperatorNotes.js";
import {
  evaluateBroadcastRuntimeHeartbeat,
} from "../services/broadcastRuntimeHeartbeat.js";
import {
  evaluateBroadcastResilienceSupervisor,
} from "../services/broadcastResilienceSupervisor.js";
import {
  executeControlledBroadcastRecovery,
} from "../services/broadcastControlledRecovery.js";
import {
  getBroadcastRecoverySnapshot,
  listBroadcastRecoverySnapshots,
  saveBroadcastRecoverySnapshot,
} from "../services/broadcastRecoverySnapshotStore.js";
import {
  classifyStreamDestinationFailure,
} from "../services/streamDestinationFailurePolicy.js";
import {
  evaluateResilienceRetryBudget,
} from "../services/broadcastResilienceRetryBudget.js";
import {
  evaluateBroadcastReleaseReadiness,
} from "../services/broadcastReleaseReadiness.js";
import {
  createDeploymentManifest,
} from "../services/deploymentManifest.js";
import {
  evaluateDataMigrationReadiness,
} from "../services/dataMigrationReadiness.js";
import mysql from "mysql2/promise";
import {
  validateSecretEnvironment,
} from "../services/secretEnvironmentValidation.js";
import {
  evaluateRollbackRestoreReadiness,
} from "../services/rollbackRestoreReadiness.js";
import {
  evaluateCredentialRotationReadiness,
} from "../services/credentialRotationReadiness.js";
import {
  evaluateSecretSourceHardening,
} from "../services/secretSourceHardening.js";
import {
  evaluateSessionInvalidationReadiness,
} from "../services/sessionInvalidationReadiness.js";
import {
  evaluateSecurityTelemetry,
} from "../services/securityTelemetry.js";

import {
  configureBroadcastCoordinatorRetry,
  evaluateBroadcastCoordinatorHealth,
  executeBroadcastCoordinatorRetry,
  getBroadcastCoordinatorRetry,
  getBroadcastCoordinatorSnapshot,
  listActiveBroadcastGameIds,
  runBroadcastCoordinatorSupervisorTick,
  scheduleBroadcastCoordinatorRetry,
  prepareBroadcastSession,
  reconcileBroadcastCoordinator,
  setBroadcastCoordinatorIntent,
  startCoordinatedBroadcast,
  stopCoordinatedBroadcast,
} from "../services/broadcastSessionCoordinator.js";

export async function registerBroadcastSessionCoordinatorRoutes(
  app: FastifyInstance,
): Promise<void> {
  app.post(
    "/broadcast-coordinator/:gameId/supervisor/tick",
    async (request, reply) => {
      const gameId = (request.params as { gameId?: string }).gameId?.trim();
      if (!gameId) {
        return reply.code(400).send({ success: false, error: "Game ID is required." });
      }
      const result = await runBroadcastCoordinatorSupervisorTick(gameId);
      if (result.action === "REFUSED") {
        return reply.code(409).send({ success: false, error: result.message, data: result });
      }
      return { success: true, data: result };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/retry",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          retry:
            getBroadcastCoordinatorRetry(
              gameId,
            ),
        },
      };
    },
  );

  app.put(
    "/broadcast-coordinator/:gameId/retry",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          maxAttempts?: number;
          backoffSeconds?: number;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          retry:
            configureBroadcastCoordinatorRetry({
              gameId,
              maxAttempts:
                body.maxAttempts,
              backoffSeconds:
                body.backoffSeconds,
            }),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/retry/schedule",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          error?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          retry:
            scheduleBroadcastCoordinatorRetry(
              gameId,
              body.error?.trim() ||
                "Coordinator retry requested.",
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/retry/execute",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        return {
          success: true,
          data:
            await executeBroadcastCoordinatorRetry(
              gameId,
            ),
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Coordinator retry failed.",
          data: {
            retry:
              getBroadcastCoordinatorRetry(
                gameId,
              ),
          },
        });
      }
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/reconcile",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const result =
        await reconcileBroadcastCoordinator(
          gameId,
        );

      if (
        result.action ===
        "REFUSE_AMBIGUOUS"
      ) {
        return reply.code(409).send({
          success: false,
          error:
            result.message,
          data:
            result,
        });
      }

      return {
        success: true,
        data:
          result,
      };
    },
  );

  app.get(
    "/broadcast-coordinator/attention-queue",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      const items =
        gameIds
          .map(
            (gameId) => {
              const snapshot =
                getBroadcastCoordinatorSnapshot(
                  gameId,
                );

              const health =
                evaluateBroadcastCoordinatorHealth(
                  gameId,
                );

              const retry =
                getBroadcastCoordinatorRetry(
                  gameId,
                );

              let severity:
                | "CRITICAL"
                | "HIGH"
                | "MEDIUM"
                | "LOW" =
                "LOW";

              let reason =
                "Active broadcast requires no immediate attention.";

              if (
                snapshot.goLive.status ===
                  "EMERGENCY_STOPPED"
              ) {
                severity =
                  "CRITICAL";

                reason =
                  "Emergency stop is active.";
              } else if (
                !health.healthy
              ) {
                severity =
                  "HIGH";

                reason =
                  health.issues
                    .map(
                      (issue) =>
                        issue.message,
                    )
                    .join(" | ");
              } else if (
                snapshot.goLive.status ===
                  "DEGRADED"
              ) {
                severity =
                  "HIGH";

                reason =
                  snapshot.goLive.degradationReason ??
                  "Broadcast is degraded.";
              } else if (
                retry.state ===
                  "EXHAUSTED"
              ) {
                severity =
                  "HIGH";

                reason =
                  retry.lastError ??
                  "Coordinator retries are exhausted.";
              } else if (
                retry.state ===
                  "SCHEDULED"
              ) {
                severity =
                  "MEDIUM";

                reason =
                  retry.nextRetryAt
                    ? `Coordinator retry scheduled for ${retry.nextRetryAt}.`
                    : "Coordinator retry is scheduled.";
              } else if (
                snapshot.goLive.status ===
                  "STARTING" ||
                snapshot.goLive.status ===
                  "STOPPING"
              ) {
                severity =
                  "MEDIUM";

                reason =
                  `Go-live transition is ${snapshot.goLive.status}.`;
              }

              const score =
                severity === "CRITICAL"
                  ? 400
                  : severity === "HIGH"
                    ? 300
                    : severity === "MEDIUM"
                      ? 200
                      : 100;

              return {
                gameId,
                severity,
                score,
                reason,
                health,
                retry,
                snapshot,
              };
            },
          )
          .sort(
            (a, b) =>
              b.score -
              a.score,
          );

      return {
        success: true,
        data: {
          count:
            items.length,
          items,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/security-telemetry",
    async () => {
      const rollback =
        evaluateRollbackRestoreReadiness({
          root:
            process.cwd(),
          dataDir:
            process.env.SPORTSOS_DATA_DIR ??
            null,
          backupDir:
            process.env.SPORTSOS_BACKUP_DIR ??
            "/app/data/backups",
        });

      let mysqlReachable =
        false;

      try {
        const mysql =
          await import(
            "mysql2/promise",
          );

        const connection =
          await mysql.default.createConnection({
            host:
              process.env.MYSQL_HOST ??
              "mysql",
            port:
              Number(
                process.env.MYSQL_PORT ??
                3306,
              ),
            database:
              process.env.MYSQL_DATABASE,
            user:
              process.env.MYSQL_USER,
            password:
              process.env.MYSQL_PASSWORD,
          });

        try {
          await connection.query(
            "SELECT 1",
          );

          mysqlReachable =
            true;
        } finally {
          await connection.end();
        }
      } catch {
        mysqlReachable =
          false;
      }

      const migration =
        evaluateDataMigrationReadiness({
          dataDir:
            process.env.SPORTSOS_DATA_DIR ??
            null,
          mysqlReachable,
          files: [
            "broadcast-operator-notes.json",
            "broadcast-recovery-snapshots.json",
            "broadcast-session-profiles.json",
            "stream-destination-profiles.json",
            "encoder-sessions.json",
            "encoder-runtime-audit.json",
            "go-live-sessions.json",
            "go-live-audit.json",
            "broadcast-session-coordinator.json",
            "broadcast-coordinator-audit.json",
          ],
        });

      return {
        success: true,
        data:
          evaluateSecurityTelemetry({
            root:
              process.cwd(),
            env:
              process.env,
            rollbackReady:
              rollback.ready,
            dataMigrationReady:
              migration.ready,
          }),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/session-invalidation-readiness",
    async () => {
      return {
        success: true,
        data:
          evaluateSessionInvalidationReadiness(
            process.env,
          ),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/secret-source-hardening",
    async () => {
      return {
        success: true,
        data:
          evaluateSecretSourceHardening({
            root:
              process.cwd(),
          }),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/credential-rotation-readiness",
    async () => {
      const rollback =
        evaluateRollbackRestoreReadiness({
          root:
            process.cwd(),
          dataDir:
            process.env.SPORTSOS_DATA_DIR ??
            null,
          backupDir:
            process.env.SPORTSOS_BACKUP_DIR ??
            "/app/data/backups",
        });

      let mysqlReachable =
        false;

      try {
        const mysql =
          await import(
            "mysql2/promise",
          );

        const connection =
          await mysql.default.createConnection({
            host:
              process.env.MYSQL_HOST ??
              "mysql",
            port:
              Number(
                process.env.MYSQL_PORT ??
                3306,
              ),
            database:
              process.env.MYSQL_DATABASE,
            user:
              process.env.MYSQL_USER,
            password:
              process.env.MYSQL_PASSWORD,
          });

        try {
          await connection.query(
            "SELECT 1",
          );

          mysqlReachable =
            true;
        } finally {
          await connection.end();
        }
      } catch {
        mysqlReachable =
          false;
      }

      const migration =
        evaluateDataMigrationReadiness({
          dataDir:
            process.env.SPORTSOS_DATA_DIR ??
            null,
          mysqlReachable,
          files: [
            "broadcast-operator-notes.json",
            "broadcast-recovery-snapshots.json",
            "broadcast-session-profiles.json",
            "stream-destination-profiles.json",
            "encoder-sessions.json",
            "encoder-runtime-audit.json",
            "go-live-sessions.json",
            "go-live-audit.json",
            "broadcast-session-coordinator.json",
            "broadcast-coordinator-audit.json",
          ],
        });

      return {
        success: true,
        data:
          evaluateCredentialRotationReadiness({
            env:
              process.env,
            rollbackReady:
              rollback.ready,
            dataMigrationReady:
              migration.ready,
          }),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/rollback-restore-readiness",
    async () => {
      return {
        success: true,
        data:
          evaluateRollbackRestoreReadiness({
            root:
              process.cwd(),
            dataDir:
              process.env.SPORTSOS_DATA_DIR ??
              null,
            backupDir:
              process.env.SPORTSOS_BACKUP_DIR ??
              "/app/data/backups",
          }),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/secret-environment-validation",
    async () => {
      return {
        success: true,
        data:
          validateSecretEnvironment(
            process.env,
          ),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/data-migration-readiness",
    async () => {
      let mysqlReachable =
        false;

      try {
        const connection =
          await mysql.createConnection({
            host:
              process.env.MYSQL_HOST ??
              "mysql",
            port:
              Number(
                process.env.MYSQL_PORT ??
                3306,
              ),
            database:
              process.env.MYSQL_DATABASE,
            user:
              process.env.MYSQL_USER,
            password:
              process.env.MYSQL_PASSWORD,
          });

        try {
          await connection.query(
            "SELECT 1",
          );

          mysqlReachable =
            true;
        } finally {
          await connection.end();
        }
      } catch {
        mysqlReachable =
          false;
      }

      return {
        success: true,
        data:
          evaluateDataMigrationReadiness({
            dataDir:
              process.env.SPORTSOS_DATA_DIR ??
              null,
            mysqlReachable,
            files: [
              "broadcast-operator-notes.json",
              "broadcast-recovery-snapshots.json",
              "broadcast-session-profiles.json",
              "stream-destination-profiles.json",
              "encoder-sessions.json",
              "encoder-runtime-audit.json",
              "go-live-sessions.json",
              "go-live-audit.json",
              "broadcast-session-coordinator.json",
              "broadcast-coordinator-audit.json",
            ],
          }),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/deployment-manifest",
    async () => {
      return {
        success: true,
        data:
          createDeploymentManifest(),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/release-readiness",
    async () => {
      return {
        success: true,
        data:
          evaluateBroadcastReleaseReadiness({
            env:
              process.env,
          }),
      };
    },
  );

  app.get(
    "/broadcast-coordinator/operations-summary",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      const items =
        gameIds.map(
          (gameId) => ({
            gameId,
            snapshot:
              getBroadcastCoordinatorSnapshot(
                gameId,
              ),
            health:
              evaluateBroadcastCoordinatorHealth(
                gameId,
              ),
            retry:
              getBroadcastCoordinatorRetry(
                gameId,
              ),
          }),
        );

      return {
        success: true,
        data: {
          count:
            items.length,
          items,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/active",
    async () => {
      const gameIds =
        listActiveBroadcastGameIds();

      return {
        success: true,
        data: {
          gameIds,
          count:
            gameIds.length,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/handoff-summary",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const health =
        evaluateBroadcastCoordinatorHealth(
          gameId,
        );

      const retry =
        getBroadcastCoordinatorRetry(
          gameId,
        );

      const notes =
        listBroadcastOperatorNotes(
          gameId,
          5,
        );

      const coordinatorEvents =
        listBroadcastCoordinatorAudit(
          gameId,
          10,
        ).map(
          (event) => ({
            source:
              "COORDINATOR",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
          }),
        );

      const goLiveEvents =
        listGoLiveAuditEvents(
          gameId,
          10,
        ).map(
          (event) => ({
            source:
              "GO_LIVE",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
          }),
        );

      const recentEvents =
        [
          ...coordinatorEvents,
          ...goLiveEvents,
        ]
          .sort(
            (a, b) =>
              Date.parse(
                b.timestamp,
              ) -
              Date.parse(
                a.timestamp,
              ),
          )
          .slice(
            0,
            10,
          );

      return {
        success: true,
        data: {
          gameId,
          generatedAt:
            new Date().toISOString(),
          snapshot,
          health,
          retry,
          notes,
          recentEvents,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/operator-notes",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          notes:
            listBroadcastOperatorNotes(
              gameId,
              100,
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/operator-notes",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          operator?: string;
          note?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        const note =
          addBroadcastOperatorNote({
            gameId,
            operator:
              body.operator ??
              "",
            note:
              body.note ??
              "",
          });

        return {
          success: true,
          data: {
            note,
          },
        };
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to save operator note.",
        });
      }
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/operator-timeline",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const query =
        request.query as {
          limit?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const parsedLimit =
        Number.parseInt(
          query.limit ??
          "100",
          10,
        );

      const limit =
        Number.isFinite(
          parsedLimit,
        )
          ? Math.max(
              1,
              Math.min(
                parsedLimit,
                200,
              ),
            )
          : 100;

      const coordinatorEvents =
        listBroadcastCoordinatorAudit(
          gameId,
          limit,
        ).map(
          (event) => ({
            id:
              event.id,
            source:
              "COORDINATOR",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
            operator:
              null,
            correlationId:
              event.correlationId,
          }),
        );

      const goLiveEvents =
        listGoLiveAuditEvents(
          gameId,
          limit,
        ).map(
          (event) => ({
            id:
              event.id,
            source:
              "GO_LIVE",
            type:
              event.type,
            timestamp:
              event.timestamp,
            detail:
              event.detail,
            operator:
              event.operator,
            correlationId:
              null,
          }),
        );

      const events =
        [
          ...coordinatorEvents,
          ...goLiveEvents,
        ]
          .sort(
            (a, b) =>
              Date.parse(
                b.timestamp,
              ) -
              Date.parse(
                a.timestamp,
              ),
          )
          .slice(
            0,
            limit,
          );

      return {
        success: true,
        data: {
          gameId,
          count:
            events.length,
          events,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/audit",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const query =
        request.query as {
          limit?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const parsed =
        Number.parseInt(
          query.limit ??
          "100",
          10,
        );

      return {
        success: true,
        data: {
          events:
            listBroadcastCoordinatorAudit(
              gameId,
              Number.isFinite(parsed)
                ? parsed
                : 100,
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/recovery/execute",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          operator?: string;
          approveDestructive?: boolean;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const lastActivityAt =
        snapshot.runtime.telemetry.lastProgressAt ??
        null;

      const stateAgeMs =
        lastActivityAt
          ? Math.max(
              0,
              Date.now() -
                Date.parse(
                  lastActivityAt,
                ),
            )
          : 0;

      try {
        const result =
          await executeControlledBroadcastRecovery({
            gameId,
            operator:
              body.operator ??
              "",
            approveDestructive:
              body.approveDestructive ===
              true,
            coordinatorIntent:
              snapshot.coordinator.intent,
            runtimeStatus:
              snapshot.runtime.session.status,
            lastActivityAt,
            stateAgeMs,
          });

        return {
          success: true,
          data:
            result,
        };
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Controlled recovery failed.",
        });
      }
    },
  );

  app.get(
    "/broadcast-coordinator/recovery-snapshots",
    async () => {
      return {
        success: true,
        data: {
          snapshots:
            listBroadcastRecoverySnapshots(),
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/recovery-snapshot",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          snapshot:
            getBroadcastRecoverySnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/recovery-snapshot/capture",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const lastActivityAt =
        snapshot.runtime.telemetry.lastProgressAt ??
        null;

      const stateAgeMs =
        lastActivityAt
          ? Math.max(
              0,
              Date.now() -
                Date.parse(
                  lastActivityAt,
                ),
            )
          : 0;

      const decision =
        evaluateBroadcastResilienceSupervisor({
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            snapshot.runtime.session.status,
          lastActivityAt,
          stateAgeMs,
        });

      const captured =
        saveBroadcastRecoverySnapshot({
          gameId,
          capturedAt:
            new Date().toISOString(),
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            snapshot.runtime.session.status,
          lastActivityAt,
          recoveryAction:
            decision.recovery.action,
          heartbeatState:
            decision.heartbeat.state,
        });

      return {
        success: true,
        data: {
          snapshot:
            captured,
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/resilience-retry-budget",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          attempts?: number;
          maxAttempts?: number;
          baseDelayMs?: number;
          maxDelayMs?: number;
          failure?: {
            failureClass?: string;
            action?: string;
            retryable?: boolean;
            reason?: string;
          };
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      if (!body.failure) {
        return reply.code(400).send({
          success: false,
          error:
            "Failure classification is required.",
        });
      }

      const decision =
        evaluateResilienceRetryBudget({
          attempts:
            body.attempts ??
            0,
          maxAttempts:
            body.maxAttempts,
          baseDelayMs:
            body.baseDelayMs,
          maxDelayMs:
            body.maxDelayMs,
          failure: {
            failureClass:
              (body.failure.failureClass ??
                "UNKNOWN") as any,
            action:
              (body.failure.action ??
                "OPERATOR_REVIEW") as any,
            retryable:
              body.failure.retryable ===
              true,
            reason:
              body.failure.reason ??
              "Unspecified failure.",
          },
        });

      return {
        success: true,
        data: {
          gameId,
          decision,
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/destination-failure/classify",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          ok?: boolean;
          statusCode?: number | null;
          errorCode?: string | null;
          message?: string | null;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const decision =
        classifyStreamDestinationFailure({
          ok:
            body.ok ===
            true,
          statusCode:
            body.statusCode ??
            null,
          errorCode:
            body.errorCode ??
            null,
          message:
            body.message ??
            null,
        });

      return {
        success: true,
        data: {
          gameId,
          decision,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/resilience-status",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const lastActivityAt =
        snapshot.runtime.telemetry.lastProgressAt ??
        null;

      const stateAgeMs =
        lastActivityAt
          ? Math.max(
              0,
              Date.now() -
                Date.parse(
                  lastActivityAt,
                ),
            )
          : 0;

      const decision =
        evaluateBroadcastResilienceSupervisor({
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            snapshot.runtime.session.status,
          lastActivityAt,
          stateAgeMs,
        });

      return {
        success: true,
        data: {
          gameId,
          heartbeat:
            decision.heartbeat,
          recovery:
            decision.recovery,
          persistedSnapshot:
            getBroadcastRecoverySnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/resilience-supervisor",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const telemetry =
        snapshot.runtime.telemetry;

      const session =
        snapshot.runtime.session;

      const lastActivityAt =
        telemetry.lastProgressAt ??
        null;

      const stateAgeMs =
        lastActivityAt
          ? Math.max(
              0,
              Date.now() -
                Date.parse(
                  lastActivityAt,
                ),
            )
          : 0;

      const decision =
        evaluateBroadcastResilienceSupervisor({
          coordinatorIntent:
            snapshot.coordinator.intent,
          runtimeStatus:
            session.status,
          lastActivityAt,
          stateAgeMs,
        });

      return {
        success: true,
        data: {
          gameId,
          decision,
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/runtime-heartbeat",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        getBroadcastCoordinatorSnapshot(
          gameId,
        );

      const session =
        snapshot.runtime.session;

      const telemetry =
        snapshot.runtime.telemetry;

      const lastActivityAt =
        telemetry.lastProgressAt ??
        null;

      return {
        success: true,
        data: {
          gameId,
          heartbeat:
            evaluateBroadcastRuntimeHeartbeat({
              runtimeStatus:
                session.status,
              lastActivityAt,
            }),
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId/health",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data: {
          health:
            evaluateBroadcastCoordinatorHealth(
              gameId,
            ),
          snapshot:
            getBroadcastCoordinatorSnapshot(
              gameId,
            ),
        },
      };
    },
  );

  app.get(
    "/broadcast-coordinator/:gameId",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data:
          getBroadcastCoordinatorSnapshot(
            gameId,
          ),
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/prepare",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        prepareBroadcastSession(
          gameId,
        );

      if (
        !snapshot.preflight.ready
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Broadcast preparation is blocked by final go-live preflight.",
          data:
            snapshot,
        });
      }

      return {
        success: true,
        data:
          snapshot,
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/start",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        return {
          success: true,
          data:
            await startCoordinatedBroadcast(
              gameId,
            ),
        };
      } catch (error) {
        return reply.code(409).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to start coordinated broadcast.",
          data:
            getBroadcastCoordinatorSnapshot(
              gameId,
            ),
        });
      }
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/stop",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      return {
        success: true,
        data:
          await stopCoordinatedBroadcast(
            gameId,
          ),
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/reset",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      setBroadcastCoordinatorIntent({
        gameId,
        intent:
          "IDLE",
      });

      return {
        success: true,
        data:
          getBroadcastCoordinatorSnapshot(
            gameId,
          ),
      };
    },
  );
}
