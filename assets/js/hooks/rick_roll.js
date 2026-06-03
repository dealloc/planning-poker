const RickRoll = {
  mounted() {
    this._audio = new Audio("/audio/rickroll.mp3")
    this._audio.preload = "auto"
    this._audio.load()

    this.handleEvent("votes_revealed", ({ rickroll }) => {
      if (rickroll) {
        this._audio.currentTime = 0
        this._audio.play().catch(() => {})
        showRickRollBanner()
      }
    })
  },

  destroyed() {
    if (this._audio) {
      this._audio.pause()
      this._audio = null
    }
  }
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
