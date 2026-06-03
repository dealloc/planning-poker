// 🎵 You know the rules, and so do I
const RICKROLL_NOTES = [
  // Never Gonna Give You Up opening synth riff (A major)
  // [frequency_hz, duration_ms]
  [659, 150], [587, 150], [659, 150], [587, 150],
  [659, 300], [494, 150], [587, 300], [523, 150],
  [587, 300]
]

const RickRoll = {
  mounted() {
    this.handleEvent("votes_revealed", ({ rickroll }) => {
      if (rickroll) {
        playRickRollMelody()
        showRickRollBanner()
      }
    })
  }
}

function playRickRollMelody() {
  const AudioCtx = window.AudioContext || window.webkitAudioContext
  if (!AudioCtx) return

  const ctx = new AudioCtx()
  let time = ctx.currentTime + 0.05

  RICKROLL_NOTES.forEach(([freq, durationMs]) => {
    const osc = ctx.createOscillator()
    const gain = ctx.createGain()
    osc.connect(gain)
    gain.connect(ctx.destination)

    osc.type = "square"
    osc.frequency.setValueAtTime(freq, time)

    const dur = durationMs / 1000
    gain.gain.setValueAtTime(0.08, time)
    gain.gain.exponentialRampToValueAtTime(0.001, time + dur * 0.9)

    osc.start(time)
    osc.stop(time + dur)
    time += dur
  })
}

function showRickRollBanner() {
  const banner = document.createElement("div")
  banner.innerHTML = `
    <div style="
      position: fixed; inset: 0; z-index: 99999;
      display: flex; align-items: center; justify-content: center;
      pointer-events: none;
    ">
      <div style="
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
        color: white; border-radius: 24px; padding: 40px 56px;
        text-align: center; box-shadow: 0 25px 80px rgba(0,0,0,0.6);
        animation: rickroll-pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
        border: 2px solid rgba(255,255,255,0.1);
      ">
        <div style="font-size: 72px; margin-bottom: 12px;">🎵</div>
        <div style="font-size: 28px; font-weight: 800; letter-spacing: -0.5px;">Never Gonna Give You Up</div>
        <div style="font-size: 15px; opacity: 0.6; margin-top: 8px;">Someone played the secret card</div>
      </div>
    </div>
  `

  const style = document.createElement("style")
  style.textContent = `
    @keyframes rickroll-pop {
      from { opacity: 0; transform: scale(0.5) rotate(-4deg); }
      to   { opacity: 1; transform: scale(1) rotate(0deg); }
    }
  `
  document.head.appendChild(style)
  document.body.appendChild(banner)

  setTimeout(() => {
    banner.style.transition = "opacity 0.5s"
    banner.style.opacity = "0"
    setTimeout(() => {
      banner.remove()
      style.remove()
    }, 500)
  }, 3500)
}

export default RickRoll
