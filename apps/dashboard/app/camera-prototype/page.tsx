"use client";

import { useEffect, useState } from "react";
import styles from "./page.module.css";

type Lens = "0.5" | "1" | "2";
type AudioMode = "AUTO" | "MANUAL" | "RAW";

export default function CameraPrototypePage() {
  const [menuOpen, setMenuOpen] = useState(false);
  const [lens, setLens] = useState<Lens>("1");
  const [zoom, setZoom] = useState(1);
  const [showZoomSlider, setShowZoomSlider] = useState(true);
  const [showScoreOverlay, setShowScoreOverlay] = useState(true);

  const [muted, setMuted] = useState(false);
  const [gain, setGain] = useState(62);
  const [audioMode, setAudioMode] = useState<AudioMode>("AUTO");
  const [meter, setMeter] = useState(0.55);

  const [cameraReady, setCameraReady] = useState(false);
  const [mic, setMic] = useState("iPhone Microphone");
  const [stabilization, setStabilization] = useState("Auto");

  useEffect(() => {
    const timer = window.setInterval(() => {
      if (muted) {
        setMeter(0);
        return;
      }

      const gainFactor = gain / 100;
      const variation = 0.2 + Math.random() * 0.6;
      const autoScale = audioMode === "AUTO" ? 0.85 : 1;

      setMeter(Math.min(1, variation * gainFactor * 1.35 * autoScale));
    }, 120);

    return () => window.clearInterval(timer);
  }, [muted, gain, audioMode]);

  const clipping = meter > 0.94;

  function chooseLens(value: Lens) {
    setLens(value);
    setZoom(Number(value));
  }

  return (
    <main className={styles.screen}>
      <div className={styles.fakeCamera}>
        <div className={styles.vignette} />

        <div className={styles.topLeft}>
          <div className={styles.brand}>
            <strong>SportsOS Camera</strong>
            <span>Game Camera · 1080p60</span>
          </div>

          <div className={`${styles.status} ${cameraReady ? styles.ready : ""}`}>
            <span className={styles.statusDot} />
            {cameraReady ? "CAMERA READY" : "OFFLINE"}
          </div>
        </div>

        <button
          type="button"
          className={styles.menuButton}
          onClick={() => setMenuOpen(true)}
          aria-label="Open camera controls"
        >
          ☰
        </button>

        {showScoreOverlay && (
          <section className={styles.scoreOverlay}>
            <div className={styles.teamBlock}>
              <span className={styles.teamName}>HOME</span>
              <strong className={styles.score}>2</strong>
            </div>

            <div className={styles.gameCenter}>
              <span>P2</span>
              <strong>8:42</strong>
            </div>

            <div className={styles.teamBlock}>
              <strong className={styles.score}>1</strong>
              <span className={styles.teamName}>AWAY</span>
            </div>
          </section>
        )}

        <section className={styles.audioOverlay}>
          <div className={styles.audioTop}>
            <div>
              <span className={styles.audioLabel}>AUDIO</span>
              <strong>{mic}</strong>
            </div>

            <button
              type="button"
              className={`${styles.muteButton} ${muted ? styles.mutedButton : ""}`}
              onClick={() => setMuted((value) => !value)}
            >
              {muted ? "UNMUTE" : "MUTE"}
            </button>
          </div>

          <div className={styles.meterHeader}>
            <span>
              {audioMode}
              {audioMode === "AUTO" ? " LEVEL" : ""}
            </span>

            <strong>
              {muted ? "MUTED" : clipping ? "CLIPPING" : `${Math.round(-40 + meter * 34)} dB`}
            </strong>
          </div>

          <div className={styles.meterShell}>
            <div
              className={`${styles.meterFill} ${clipping ? styles.meterClip : ""}`}
              style={{ height: `${meter * 100}%` }}
            />
            <div className={styles.targetMarker} />
          </div>

          {audioMode === "MANUAL" && (
            <>
              <div className={styles.gainRow}>
                <span>GAIN</span>
                <strong>{gain}%</strong>
              </div>

              <input
                className={styles.slider}
                type="range"
                min="0"
                max="100"
                value={gain}
                onChange={(event) => setGain(Number(event.target.value))}
              />
            </>
          )}
        </section>

        <div className={styles.centerTarget}>
          <span />
          <span />
        </div>

        {showZoomSlider && (
          <section className={styles.zoomOverlay}>
            <div className={styles.zoomHeader}>
              <span>ZOOM</span>
              <strong>{zoom.toFixed(1)}×</strong>
            </div>

            <input
              className={styles.zoomSlider}
              type="range"
              min="0.5"
              max="5"
              step="0.1"
              value={zoom}
              onChange={(event) => setZoom(Number(event.target.value))}
            />
          </section>
        )}

        <div className={styles.bottomControls}>
          <div className={styles.lensRow}>
            {(["0.5", "1", "2"] as Lens[]).map((value) => (
              <button
                key={value}
                type="button"
                className={lens === value ? styles.lensActive : styles.lensButton}
                onClick={() => chooseLens(value)}
              >
                {value}×
              </button>
            ))}
          </div>

          <button
            type="button"
            className={`${styles.readyButton} ${cameraReady ? styles.stopButton : ""}`}
            onClick={() => setCameraReady((value) => !value)}
          >
            <span className={styles.readyDot} />
            {cameraReady ? "STOP CAMERA" : "CAMERA READY"}
          </button>

          <div className={styles.streamStats}>
            <span>{cameraReady ? "SPORTSOS CONNECTED" : "WAITING"}</span>
            <strong>{cameraReady ? "8.2 Mbps" : "—"}</strong>
          </div>
        </div>
      </div>

      {menuOpen && (
        <>
          <button
            type="button"
            className={styles.backdrop}
            onClick={() => setMenuOpen(false)}
            aria-label="Close camera controls"
          />

          <aside className={styles.drawer}>
            <div className={styles.drawerHead}>
              <div>
                <span className={styles.kicker}>SPORTSOS CAMERA</span>
                <h2>Camera Controls</h2>
              </div>

              <button
                type="button"
                className={styles.closeButton}
                onClick={() => setMenuOpen(false)}
              >
                ×
              </button>
            </div>

            <section className={styles.drawerSection}>
              <h3>Video</h3>

              <label className={styles.selectField}>
                <span>Stabilization</span>
                <select
                  value={stabilization}
                  onChange={(event) => setStabilization(event.target.value)}
                >
                  <option>Auto</option>
                  <option>Standard</option>
                  <option>Cinematic</option>
                  <option>Low Latency</option>
                  <option>Off</option>
                </select>
              </label>

              <label className={styles.toggleRow}>
                <span>
                  <strong>Persistent zoom control</strong>
                  <small>Keep the zoom slider visible during the game.</small>
                </span>

                <input
                  type="checkbox"
                  checked={showZoomSlider}
                  onChange={(event) => setShowZoomSlider(event.target.checked)}
                />
              </label>

              <label className={styles.toggleRow}>
                <span>
                  <strong>Score overlay</strong>
                  <small>Show the live SportsOS scoreboard while filming.</small>
                </span>

                <input
                  type="checkbox"
                  checked={showScoreOverlay}
                  onChange={(event) => setShowScoreOverlay(event.target.checked)}
                />
              </label>
            </section>

            <section className={styles.drawerSection}>
              <h3>Audio</h3>

              <label className={styles.selectField}>
                <span>Input</span>
                <select value={mic} onChange={(event) => setMic(event.target.value)}>
                  <option>iPhone Microphone</option>
                  <option>Bluetooth Microphone</option>
                  <option>USB-C / Wired Input</option>
                </select>
              </label>

              <div className={styles.modeRow}>
                {(["AUTO", "MANUAL", "RAW"] as AudioMode[]).map((mode) => (
                  <button
                    key={mode}
                    type="button"
                    className={audioMode === mode ? styles.modeActive : styles.modeButton}
                    onClick={() => setAudioMode(mode)}
                  >
                    {mode}
                  </button>
                ))}
              </div>

              {audioMode !== "AUTO" && (
                <>
                  <div className={styles.drawerGain}>
                    <span>Input gain</span>
                    <strong>{gain}%</strong>
                  </div>

                  <input
                    className={styles.slider}
                    type="range"
                    min="0"
                    max="100"
                    value={gain}
                    disabled={audioMode === "RAW"}
                    onChange={(event) => setGain(Number(event.target.value))}
                  />
                </>
              )}

              <p className={styles.audioHint}>
                {audioMode === "AUTO"
                  ? "Automatic leveling, light compression and safety limiter."
                  : audioMode === "RAW"
                    ? "Minimal processing for an external mixer or audio interface."
                    : "Manual gain with safety limiter."}
              </p>
            </section>

            <section className={styles.drawerSection}>
              <h3>Connection</h3>

              <div className={styles.connectionGrid}>
                <div>
                  <span>SportsOS</span>
                  <strong>{cameraReady ? "Connected" : "Waiting"}</strong>
                </div>

                <div>
                  <span>Network</span>
                  <strong>{cameraReady ? "Excellent" : "—"}</strong>
                </div>

                <div>
                  <span>Bitrate</span>
                  <strong>{cameraReady ? "8.2 Mbps" : "—"}</strong>
                </div>
              </div>
            </section>

            <div className={styles.safetyNote}>
              Camera Ready does not put the game LIVE. Broadcast remains controlled by SportsOS.
            </div>
          </aside>
        </>
      )}
    </main>
  );
}
