const STORAGE_KEY = "pp_notifications_enabled"
const SOUND_URL = "/audio/msn-sound_1.mp3"

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
