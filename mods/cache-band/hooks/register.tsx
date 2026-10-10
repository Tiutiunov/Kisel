import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { CacheCount } from '../types'
import { bar, detail, drawing, head, line, remember, share, spark } from './format'

const last = atom({ plugin: 'cache-band', key: 'last' } as const, null)
// (the share served from the cache, response after response: the graph)
const history = atom({ plugin: 'cache-band', key: 'history' } as const, [])

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
      await update($, history, kept => remember(kept, seen))
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
      await update($, history, kept => remember(kept, seen))
    }

    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const seen = await read($, last)

    if (e.props.hasSurvey || seen === null) {
      return next(e)
    }

    const kept = await read($, history)
    // (how well the cache served the last response decides the colour of its figure)
    const tone = share(seen) >= 80 ? 'success' : share(seen) >= 50 ? 'warning' : 'error'

    // A terminal draws characters: a graph in blocks, then the bar, then the words.
    if (e.surface === 'terminal') {
      const { Box, Text } = $.ui.resolve(e)
      const parts = bar(seen, 12)

      return (
        <Box key="cache" gap={1}>
          <Text color="success">{spark(kept)}</Text>
          <Text>
            <Text color="success">{parts.read}</Text>
            <Text color="warning">{parts.written}</Text>
            <Text color="error">{parts.fresh}</Text>
          </Text>
          <Text bold>{head(seen)}</Text>
          <Text color={tone}>{`${share(seen)}%`}</Text>
          <Text dimColor>{detail(seen)}</Text>
        </Box>
      )
    }

    // The other surfaces draw a picture, with the words beside it.
    const { Box, Text, Svg } = $.ui.resolve(e)

    return (
      <Box key="cache" flexDirection="row" alignItems="center" gap={2}>
        <Svg source={drawing(kept, seen)} alt={line(seen)} width={300} height={34} />
        <Box flexDirection="column">
          <Box flexDirection="row" gap={1}>
            <Text bold>{head(seen)}</Text>
            <Text color={tone} bold>{`${share(seen)}%`}</Text>
          </Box>
          <Text dimColor>{detail(seen)}</Text>
        </Box>
      </Box>
    )
  })
}
