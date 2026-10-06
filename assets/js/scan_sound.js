// Short tones for a scan's result on the door's page and the verify site, made with
// Web Audio so there are no sound files. The LiveView pushes a "scan-sound" event with
// one of the names in TONES. Browsers play sound only after a tap, so every tap resumes
// the audio. On an iPhone the silent switch mutes Web Audio unless the page's audio
// session is "playback" (Safari 17 and later).
// The sound is on unless turned off with a SoundSwitch, remembered on the device.
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

// iOS lets a page start audio only from a finished tap, and the first one counts only
// if it plays something, so this plays a silent sound. An "interrupted" context, from
// the camera prompt or a call, often never runs again, so a tap replaces it.
function unlock() {
  if (navigator.audioSession) navigator.audioSession.type = "playback"
  if (context?.state === "interrupted") drop()
  context ??= new AudioContext()
  if (context.state !== "running") context.resume().catch(() => {})
  const silence = context.createBufferSource()
  silence.buffer = context.createBuffer(1, 1, 22050)
  silence.connect(context.destination)
  silence.start()
}

function drop() {
  context?.close().catch(() => {})
  context = null
}

// Safari's camera prompt on a first scan pauses the audio, so wake it before playing
// rather than losing the tone. On an iPhone resume() can stay pending for good, so give
// up after half a second.
async function play(name) {
  if (!TONES[name] || !soundOn() || !context) return
  if (context.state !== "running") {
    const timeout = new Promise(resolve => setTimeout(resolve, 500))
    await Promise.race([context.resume().catch(() => {}), timeout])
  }
  if (context?.state === "running") playTones(TONES[name])
}

function playTones(tones) {
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
  for (const type of ["pointerdown", "touchend", "click"])
    document.addEventListener(type, unlock, {capture: true})
  window.addEventListener("phx:scan-sound", event => play(event.detail.sound))
  // A page that goes to the background, such as switching apps, loses its audio and
  // doesn't always get it back, so start fresh on the next tap.
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) drop()
  })
}

// A switch that turns scan sounds on and off. Its checked state comes from here, so give
// it phx-update="ignore".
export const SoundSwitch = {
  mounted() {
    this.el.checked = soundOn()
    this.el.addEventListener("change", () => {
      localStorage.setItem(STORAGE_KEY, this.el.checked ? "on" : "off")
      if (this.el.checked) {
        unlock()
        play("ok")
      }
    })
  },
}
