import { expect, test } from 'claude-code/testing'

import { KEPT, bar, detail, drawing, head, line, remember, share, short, spark } from './format'

test('counts are shortened the way a person reads them', async () => {
  expect(short(950)).toBe('950')
  expect(short(182431)).toBe('182.4k')
  expect(short(1234567)).toBe('1.23M')
})

test('the band says what the cache holds and what share was served from it', async () => {
  const c = { read: 180000, written: 2500, fresh: 17500 }

  expect(share(c)).toBe(90)
  expect(head(c)).toBe('Кеш 182.5k')
  expect(detail(c)).toBe('из кеша 90% · дописано 2.5k · мимо 17.5k')
  expect(line(c)).toBe('Кеш 182.5k · из кеша 90% · дописано 2.5k · мимо 17.5k')
  expect(line({ read: 0, written: 0, fresh: 0 })).toBe('Кеш 0 · из кеша 0% · дописано 0 · мимо 0')
})

test('the graph keeps the last responses and no more', async () => {
  let kept: number[] = []

  for (let i = 0; i < KEPT + 5; i++) {
    kept = remember(kept, { read: i, written: 0, fresh: 100 - i })
  }

  expect(kept.length).toBe(KEPT)
  expect(kept[kept.length - 1]).toBe(KEPT + 4)
})

test('a terminal gets the graph in blocks and the bar in characters', async () => {
  expect(spark([0, 50, 100])).toBe('▁▅█')

  const parts = bar({ read: 50, written: 25, fresh: 25 }, 12)

  expect(parts.read.length + parts.written.length + parts.fresh.length).toBe(12)
  expect(parts.read).toBe('██████')
  expect(bar({ read: 0, written: 0, fresh: 0 }, 4).fresh).toBe('░░░░')
})

test('the drawing is one svg, whatever it is given', async () => {
  for (const history of [[], [90], [10, 95, 97, 40, 99]]) {
    const svg = drawing(history, { read: 180000, written: 2500, fresh: 17500 })

    expect(svg.startsWith('<svg ')).toBe(true)
    expect(svg.endsWith('</svg>')).toBe(true)
    expect(svg.includes('NaN')).toBe(false)
  }

  expect(drawing([], { read: 0, written: 0, fresh: 0 }).includes('NaN')).toBe(false)
})
