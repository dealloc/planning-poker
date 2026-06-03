import "../../vendor/confetti"

const Confetti = {
  mounted() {
    this.handleEvent("votes_revealed", ({ consensus, rickroll }) => {
      if (consensus && !rickroll) {
        launchFireworks()
      }
    })
  }
}

function launchFireworks() {
  const duration = 4 * 1000
  const animationEnd = Date.now() + duration
  const defaults = { startVelocity: 30, spread: 360, ticks: 80, zIndex: 9999 }

  function randomInRange(min, max) {
    return Math.random() * (max - min) + min
  }

  const interval = setInterval(() => {
    const timeLeft = animationEnd - Date.now()

    if (timeLeft <= 0) {
      clearInterval(interval)
      return
    }

    const particleCount = 60 * (timeLeft / duration)

    window.confetti({
      ...defaults,
      particleCount,
      origin: { x: randomInRange(0.1, 0.3), y: Math.random() - 0.2 }
    })
    window.confetti({
      ...defaults,
      particleCount,
      origin: { x: randomInRange(0.7, 0.9), y: Math.random() - 0.2 }
    })
  }, 250)
}

export default Confetti
