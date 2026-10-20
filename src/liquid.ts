import { drop, shape } from './dom'

const squash = (amount: number) => [
  { transform: 'none' },
  { transform: `scale(${1 - amount}, ${1 + amount})`, offset: 0.3 },
  { transform: `scale(${1 + amount * 0.5}, ${1 - amount * 0.4})`, offset: 0.6 },
  { transform: 'none' },
]

let last = { width: 0, height: 0 }

export const wobble = (width: number, height: number) => {
  const grew = height - last.height
  const moved = Math.abs(grew) + Math.abs(width - last.width)
  last = { width, height }
  if (moved < 20) return
  shape.animate(squash(grew >= 0 ? 0.035 : -0.03), { duration: 650, easing: 'ease-in-out' })
  if (grew < 0) drip()
}

const drip = () => {
  drop.animate(
    [
      { transform: 'none' },
      { transform: 'translateY(14px) scaleX(0.7)', offset: 0.35 },
      { transform: 'translateY(-2px) scaleX(1.05)', offset: 0.7 },
      { transform: 'none' },
    ],
    { duration: 750, easing: 'cubic-bezier(0.3, 0.6, 0.35, 1)' },
  )
}
