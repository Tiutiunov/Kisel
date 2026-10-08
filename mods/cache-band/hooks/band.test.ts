import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'cache-band',
  component: 'AbovePrompt',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

test('nothing above the prompt until a response has been seen', async ($, on) => {
  on('ui.render', async ($, e) => { const { Box } = $.ui.resolve(e); return h(Box, {}) }) // (the engine's own band: an empty one)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    expect(await ui.find({ key: 'cache' })).toBeUndefined()
    await ui.unmount()
  }
})
