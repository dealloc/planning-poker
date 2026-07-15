import "../../vendor/confetti"

const Chaos = {
  mounted() {
    this.handleEvent("votes_revealed", ({ chaos, rickroll }) => {
      if (chaos && !rickroll) {
        shakeScreen()
        launchChaosBurst()
        showChaosBanner()
      }
    })
  }
}

function shakeScreen() {
  const style = document.createElement("style")
  style.textContent = `
    @keyframes chaos-shake {
      0%, 100% { transform: translate(0, 0); }
      10% { transform: translate(-6px, 3px) rotate(-0.5deg); }
      20% { transform: translate(5px, -4px) rotate(0.5deg); }
      30% { transform: translate(-4px, 4px) rotate(-0.5deg); }
      40% { transform: translate(6px, -3px) rotate(0.5deg); }
      50% { transform: translate(-5px, 2px) rotate(-0.3deg); }
      60% { transform: translate(4px, -2px) rotate(0.3deg); }
      70% { transform: translate(-3px, 3px); }
      80% { transform: translate(3px, -3px); }
      90% { transform: translate(-2px, 1px); }
    }
  `
  document.head.appendChild(style)
  document.body.style.animation = "chaos-shake 0.5s ease-in-out"

  setTimeout(() => {
    document.body.style.animation = ""
    style.remove()
  }, 500)
}

function launchChaosBurst() {
  const colors = ["#dc2626", "#ea580c", "#000000"]

  window.confetti({
    particleCount: 140,
    spread: 100,
    startVelocity: 45,
    ticks: 60,
    zIndex: 9999,
    colors,
    origin: { x: 0.5, y: 0.5 },
    scalar: 1.2
  })
}

function showChaosBanner() {
  const banner = document.createElement("div")
  banner.innerHTML = `
    <div style="
      position: fixed; inset: 0; z-index: 99999;
      display: flex; align-items: center; justify-content: center;
      pointer-events: none;
    ">
      <div style="
        background: linear-gradient(135deg, #7f1d1d 0%, #991b1b 50%, #431407 100%);
        color: white; border-radius: 24px; padding: 40px 56px;
        text-align: center; box-shadow: 0 25px 80px rgba(0,0,0,0.6);
        animation: chaos-pop 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
        border: 2px solid rgba(255,255,255,0.15);
      ">
        <div style="font-size: 72px; margin-bottom: 12px;">💥</div>
        <div style="font-size: 28px; font-weight: 800; letter-spacing: -0.5px;">MAXIMUM CHAOS</div>
        <div style="font-size: 15px; opacity: 0.7; margin-top: 8px;">Nobody agreed on anything</div>
      </div>
    </div>
  `

  const style = document.createElement("style")
  style.textContent = `
    @keyframes chaos-pop {
      from { opacity: 0; transform: scale(0.5) rotate(4deg); }
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
  }, 3000)
}

export default Chaos
