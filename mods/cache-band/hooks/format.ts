// 182431 -> "182.4k", 950 -> "950", 1234567 -> "1.23M"
export const short = (n: number): string =>
  n >= 1_000_000 ? `${(n / 1_000_000).toFixed(2)}M` : n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`

// What the band says. In the cache after a response: what it read from the
// cache plus what it added to it.
export const line = (c: { read: number; written: number; fresh: number }): string => {
  const held = c.read + c.written
  const all = held + c.fresh
  const share = all > 0 ? Math.round((c.read / all) * 100) : 0

  return `В кеше ${short(held)} токенов · из кеша ${short(c.read)} (${share}%) · дописано ${short(c.written)} · мимо кеша ${short(c.fresh)}`
}
