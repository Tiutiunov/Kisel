import { expect, test } from 'claude-code/testing'

import { line, short } from './format'

test('counts are shortened the way a person reads them', async () => {
  expect(short(950)).toBe('950')
  expect(short(182431)).toBe('182.4k')
  expect(short(1234567)).toBe('1.23M')
})

test('the band says what the cache holds and what share was served from it', async () => {
  expect(line({ read: 180000, written: 2500, fresh: 17500 })).toBe(
    'В кеше 182.5k токенов · из кеша 180.0k (90%) · дописано 2.5k · мимо кеша 17.5k',
  )
  expect(line({ read: 0, written: 0, fresh: 0 })).toBe('В кеше 0 токенов · из кеша 0 (0%) · дописано 0 · мимо кеша 0')
})
