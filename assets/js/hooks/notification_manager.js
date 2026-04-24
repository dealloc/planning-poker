const STORAGE_KEY = "pp_notifications_enabled"
const SOUND_URL = "/audio/msn-sound_1.mp3"
const BUZZ_SOUND_URL = "/audio/msn-wizz-sound.mp3"

const NotificationManager = {
  mounted() {
    this._enabled = localStorage.getItem(STORAGE_KEY) === "true"
    this._syncButton()

    document.getElementById("notification-toggle-btn")?.addEventListener("click", () => {
      this._enabled = !this._enabled
      localStorage.setItem(STORAGE_KEY, this._enabled)

      if (this._enabled && "Notification" in window && Notification.permission === "default") {
        Notification.requestPermission()
      }

      this._syncButton()
    })

    this.handleEvent("voting_started", () => {
      this._playSound()
      this._sendNotification("Voting started", "Cast your vote now!")
    })

    this.handleEvent("votes_revealed", ({ consensus }) => {
      this._playSound()
      this._sendNotification(
        consensus ? "🎉 Consensus reached!" : "Votes revealed",
        consensus ? "Everyone agreed on a value." : "Check the results."
      )
    })

    this.handleEvent("buzz_received", () => {
      this._playBuzzSound()
      this._showBuzzAlert()
      this._sendNotification("🔔 Buzz!", "Someone is waiting for your vote!")
    })
  },

  updated() {
    this._syncButton()
  },

  _syncButton() {
    const btn = document.getElementById("notification-toggle-btn")
    if (!btn) return

    if (this._enabled) {
      btn.setAttribute("aria-pressed", "true")
      btn.title = "Notifications enabled — click to disable"
      btn.classList.add("bg-primary/10", "border-primary/30")
      btn.classList.remove("bg-base-200", "border-base-300")
      btn.querySelector("svg")?.classList.replace("text-base-content/50", "text-primary")
      const label = btn.querySelector("span")
      if (label) label.classList.replace("text-base-content/60", "text-primary")
    } else {
      btn.setAttribute("aria-pressed", "false")
      btn.title = "Enable notifications (sound + browser alerts)"
      btn.classList.remove("bg-primary/10", "border-primary/30")
      btn.classList.add("bg-base-200", "border-base-300")
      btn.querySelector("svg")?.classList.replace("text-primary", "text-base-content/50")
      const label = btn.querySelector("span")
      if (label) label.classList.replace("text-primary", "text-base-content/60")
    }
  },

  _playSound() {
    if (!this._enabled) return
    try {
      new Audio(SOUND_URL).play()
    } catch (_) {}
  },

  _playBuzzSound() {
    try {
      new Audio(BUZZ_SOUND_URL).play()
    } catch (_) {}
  },

  _showBuzzAlert() {
    const existing = document.getElementById("msn-buzz-alert")
    if (existing) existing.remove()

    const el = document.createElement("div")
    el.id = "msn-buzz-alert"
    el.innerHTML = `
      <div style="display:flex;align-items:center;gap:10px;">
        <span style="font-size:1.5rem;">💬</span>
        <div>
          <div style="font-weight:700;font-size:0.95rem;">You've been buzzed!</div>
          <div style="font-size:0.8rem;opacity:0.85;">Someone's waiting for your vote.</div>
        </div>
      </div>
    `
    el.style.cssText = [
      "position:fixed",
      "bottom:24px",
      "right:24px",
      "z-index:99999",
      "background:linear-gradient(135deg,#1d6fd8,#0f4fa8)",
      "color:#fff",
      "border:2px solid #5ba3f5",
      "border-radius:12px",
      "padding:14px 18px",
      "box-shadow:0 8px 32px rgba(0,0,0,0.35),0 0 0 1px rgba(255,255,255,0.08)",
      "cursor:pointer",
      "max-width:280px",
      "animation:msn-buzz-in 0.25s ease-out"
    ].join(";")

    if (!document.getElementById("msn-buzz-keyframes")) {
      const style = document.createElement("style")
      style.id = "msn-buzz-keyframes"
      style.textContent = `
        @keyframes msn-buzz-in {
          0% { transform: translateY(20px) scale(0.95); opacity: 0; }
          100% { transform: translateY(0) scale(1); opacity: 1; }
        }
        @keyframes msn-buzz-shake {
          0%,100% { transform: translateX(0); }
          15% { transform: translateX(-6px) rotate(-1deg); }
          30% { transform: translateX(6px) rotate(1deg); }
          45% { transform: translateX(-5px); }
          60% { transform: translateX(5px); }
          75% { transform: translateX(-3px); }
          90% { transform: translateX(3px); }
        }
      `
      document.head.appendChild(style)
    }

    document.body.appendChild(el)

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        el.style.animation = "msn-buzz-shake 0.5s ease-in-out"
      })
    })

    el.addEventListener("click", () => el.remove())
    setTimeout(() => el.remove(), 6000)
  },

  _sendNotification(title, body) {
    if (!this._enabled) return
    if (document.visibilityState === "visible") return
    if (!("Notification" in window) || Notification.permission !== "granted") return
    try {
      new Notification(title, { body, icon: "/favicon.svg" })
    } catch (_) {}
  }
}

export default NotificationManager
