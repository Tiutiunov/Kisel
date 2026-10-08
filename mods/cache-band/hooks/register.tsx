import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { CacheCount } from '../types'
import { line } from './format'

const last = atom({ plugin: 'cache-band', key: 'last' } as const, null)

export const register: Register = on => {
  // A session picked up mid-way: what its last response reported, if the engine still has it.
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    const usage = (await $.session.usage({ breakdown: 'summary' })).context.breakdown?.apiUsage

    if (usage && (await read($, last)) === null) {
      const seen: CacheCount = {
        read: usage.cache_read_input_tokens,
        written: usage.cache_creation_input_tokens,
        fresh: usage.input_tokens,
      }
      await update($, last, () => seen)
    }

    return result
  })

  // Every model response of the main conversation (a subagent has a cache of its own).
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)

    if (e.agentId === undefined && result.usage) {
      const seen: CacheCount = {
        read: result.usage.cache_read_input_tokens,
        written: result.usage.cache_creation_input_tokens,
        fresh: result.usage.input_tokens,
      }
      await update($, last, () => seen)
    }

    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const seen = await read($, last)

    if (e.props.hasSurvey || seen === null) {
      return next(e)
    }

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text key="cache" dimColor>
          {line(seen)}
        </Text>
      </Box>
    )
  })
}
