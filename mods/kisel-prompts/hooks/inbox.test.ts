import { expect, test } from 'claude-code/testing'

import { clean, folder, pending, reply } from './inbox'

const B = String.fromCharCode(92)
const HOME = ['C:', 'Users', 'me'].join(B)

test('the folder is the one Kisel writes to', async () => {
  expect(folder(HOME, 'abc-123')).toBe('C:/Users/me/.kisel/inbox/abc-123')
  expect(folder(HOME + B, 'abc-123')).toBe('C:/Users/me/.kisel/inbox/abc-123')
})

test('only prompts without a receipt are handed over, oldest first, each once', async () => {
  const names = ['alive', '1700000000002-1.prompt', '1700000000001-0.prompt', '1700000000001-0.taken', '1700000000003-2.prompt']

  expect(pending(names, new Set())).toEqual(['1700000000002-1', '1700000000003-2'])
  expect(pending(names, new Set(['1700000000002-1']))).toEqual(['1700000000003-2'])
  expect(pending(['alive'], new Set())).toEqual([])
})

test('a reply with no words is not sent, a huge one is cut', async () => {
  expect(reply('  ')).toBeNull()
  expect(reply(' готово ')).toBe('готово')
  expect(reply('x'.repeat(13000))?.length).toBe(12002)
})

test('an empty or enormous prompt is dropped, the rest is trimmed', async () => {
  expect(clean('  привет  ')).toBe('привет')
  expect(clean('   ')).toBeNull()
  expect(clean('x'.repeat(20001))).toBeNull()
})
