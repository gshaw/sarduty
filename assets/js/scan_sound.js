// Short tones for a scan's result on the door's page and the verify site, made with
// Web Audio so there are no sound files. The LiveView pushes a "scan-sound" event with
// one of the names in TONES. Browsers play sound only after a tap, so every tap resumes
// the audio. On an iPhone the silent switch mutes Web Audio unless the page's audio
// session is "playback" (Safari 17 and later).
// The sound is on unless turned off with a SoundToggle button, remembered on the device.
const STORAGE_KEY = "sarduty:scan-sound"

// Each tone is [frequency in Hz, start in seconds, length in seconds, wave].
const TONES = {
  arrived: [[660, 0, 0.12, "sine"], [990, 0.12, 0.18, "sine"]],
  left: [[990, 0, 0.12, "sine"], [660, 0.12, 0.18, "sine"]],
  ok: [[660, 0, 0.12, "sine"], [990, 0.12, 0.18, "sine"]],
  error: [[200, 0, 0.18, "square"], [200, 0.24, 0.18, "square"]],
}

let context = null

function soundOn() {
  return localStorage.getItem(STORAGE_KEY) !== "off"
}

function unlock() {
  if (navigator.audioSession) navigator.audioSession.type = "playback"
  context ??= new AudioContext()
  if (context.state === "suspended") context.resume()
}

function play(name) {
  const tones = TONES[name]
  if (!tones || !soundOn() || !context) return
  const start = context.currentTime + 0.02
  for (const [frequency, offset, length, wave] of tones) {
    const oscillator = context.createOscillator()
    const gain = context.createGain()
    oscillator.type = wave
    oscillator.frequency.value = frequency
    // A quick fade in and out, so the tone doesn't click.
    gain.gain.setValueAtTime(0, start + offset)
    gain.gain.linearRampToValueAtTime(0.3, start + offset + 0.01)
    gain.gain.linearRampToValueAtTime(0, start + offset + length)
    oscillator.connect(gain).connect(context.destination)
    oscillator.start(start + offset)
    oscillator.stop(start + offset + length)
  }
}

export function listenForScanSounds() {
  document.addEventListener("pointerdown", unlock, {capture: true})
  window.addEventListener("phx:scan-sound", event => play(event.detail.sound))
}

// A button that turns scan sounds on and off. Its label and aria-pressed come from here,
// so give it phx-update="ignore".
export const SoundToggle = {
  mounted() {
    this.show()
    this.el.addEventListener("click", () => {
      localStorage.setItem(STORAGE_KEY, soundOn() ? "off" : "on")
      this.show()
      if (soundOn()) {
        unlock()
        play("ok")
      }
    })
  },
  show() {
    this.el.textContent = soundOn() ? "Sound on" : "Sound off"
    this.el.setAttribute("aria-pressed", String(soundOn()))
  },
}
