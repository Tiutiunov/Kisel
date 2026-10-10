// 182431 -> "182.4k", 950 -> "950", 1234567 -> "1.23M"
export const short = (n: number): string =>
  n >= 1_000_000 ? `${(n / 1_000_000).toFixed(2)}M` : n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`

export type Count = { read: number; written: number; fresh: number }

// Of the input of a response, the part the cache served: 0..100.
export const share = (c: Count): number => {
  const all = c.read + c.written + c.fresh

  return all > 0 ? Math.round((c.read / all) * 100) : 0
}

// What the band says in words. In the cache after a response: what it read from
// the cache plus what it added to it.
export const head = (c: Count): string => `Кеш ${short(c.read + c.written)}`

export const detail = (c: Count): string =>
  `из кеша ${share(c)}% · дописано ${short(c.written)} · мимо ${short(c.fresh)}`

// ...and all of it in one line, for a reader that cannot see the drawing.
export const line = (c: Count): string => `${head(c)} · ${detail(c)}`

// The shares of the last responses kept for the graph, newest last.
export const KEPT = 32

export const remember = (history: readonly number[], c: Count): number[] => [...history, share(c)].slice(-KEPT)

// A graph in eight heights of block, for a terminal: one character a response.
const BLOCKS = '▁▂▃▄▅▆▇█'

export const spark = (history: readonly number[]): string =>
  history.map(v => BLOCKS[Math.max(0, Math.min(7, Math.round((v / 100) * 7)))]).join('')

// A bar of `width` characters: how the last response's input divides.
export const bar = (c: Count, width: number): { read: string; written: string; fresh: string } => {
  const all = c.read + c.written + c.fresh

  if (all <= 0) {
    return { read: '', written: '', fresh: '░'.repeat(width) }
  }

  const read = Math.round((c.read / all) * width)
  const written = Math.min(width - read, Math.round((c.written / all) * width))

  return { read: '█'.repeat(read), written: '▓'.repeat(written), fresh: '░'.repeat(width - read - written) }
}

const GREEN = '#3fb950'
const AMBER = '#d29922'
const RED = '#f85149'

// The same as a drawing, for the surfaces that draw one: on the left the share
// served from the cache over the last responses (a response that missed the
// cache gets a red dot), on the right how the last response's input divides:
// served (green), added (amber), past the cache (red).
// Its colours are fixed: the drawing is an image and cannot follow the theme, so
// they are ones that read on a dark page and on a light one.
export const drawing = (history: readonly number[], c: Count): string => {
  const W = 300
  const H = 34
  const x0 = 8
  const x1 = 188
  const top = 6
  const bottom = 28
  const points = history.length > 1 ? history : [history[0] ?? share(c), history[0] ?? share(c)]
  const step = (x1 - x0) / (points.length - 1)
  const at = (v: number, i: number): [number, number] => [x0 + i * step, bottom - (Math.max(0, Math.min(100, v)) / 100) * (bottom - top)]
  const path = points.map((v, i) => at(v, i).map(n => n.toFixed(1)).join(',')).join(' ')
  const dots = points
    .map((v, i) => ({ v, p: at(v, i), last: i === points.length - 1 }))
    .filter(d => d.last || d.v < 50)
    .map(d => `<circle cx="${d.p[0].toFixed(1)}" cy="${d.p[1].toFixed(1)}" r="${d.last ? 2.6 : 2}" fill="${d.v < 50 ? RED : GREEN}"/>`)
    .join('')

  const all = c.read + c.written + c.fresh
  const bx = 200
  const bw = 92
  const rw = all > 0 ? (c.read / all) * bw : 0
  const ww = all > 0 ? (c.written / all) * bw : 0

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">` +
    `<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${GREEN}" stop-opacity="0.45"/>` +
    `<stop offset="1" stop-color="${GREEN}" stop-opacity="0.04"/></linearGradient>` +
    `<clipPath id="c"><rect x="${bx}" y="12" width="${bw}" height="10" rx="5"/></clipPath></defs>` +
    `<rect x="0.5" y="0.5" width="${W - 1}" height="${H - 1}" rx="8" fill="#808080" fill-opacity="0.12" stroke="#808080" stroke-opacity="0.25"/>` +
    `<line x1="${x0}" y1="${top}" x2="${x1}" y2="${top}" stroke="#808080" stroke-opacity="0.3" stroke-dasharray="2 3"/>` +
    `<polygon points="${x0},${bottom} ${path} ${x1},${bottom}" fill="url(#g)"/>` +
    `<polyline points="${path}" fill="none" stroke="${GREEN}" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"/>` +
    dots +
    `<g clip-path="url(#c)"><rect x="${bx}" y="12" width="${bw}" height="10" fill="${RED}" fill-opacity="${all > 0 ? 0.85 : 0.2}"/>` +
    `<rect x="${bx}" y="12" width="${(rw + ww).toFixed(1)}" height="10" fill="${AMBER}"/>` +
    `<rect x="${bx}" y="12" width="${rw.toFixed(1)}" height="10" fill="${GREEN}"/></g>` +
    `</svg>`
  )
}
