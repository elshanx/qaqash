const spring = (response: number, dampingRatio: number) => {
  const stiffness = (2 * Math.PI / response) ** 2
  const damping = 4 * Math.PI * dampingRatio / response
  const step = 1 / 60
  const points = [0]
  let position = 0
  let velocity = 0
  while (points.length < 180) {
    velocity += (stiffness * (1 - position) - damping * velocity) * step
    position += velocity * step
    points.push(position)
    if (Math.abs(1 - position) < 0.001 && Math.abs(velocity) < 0.01) break
  }
  points.push(1)
  return { easing: `linear(${points.map((point) => point.toFixed(3)).join(', ')})`, ms: Math.round(points.length * step * 1000) }
}

export const morph = spring(0.45, 0.68)
export const pop = spring(0.32, 0.6)

const root = document.documentElement.style
root.setProperty('--spring', morph.easing)
root.setProperty('--spring-ms', `${morph.ms}ms`)
root.setProperty('--pop', pop.easing)
root.setProperty('--pop-ms', `${pop.ms}ms`)

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))
