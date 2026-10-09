import type { Register } from 'claude-code'

import { clean, folder, pending, reply } from './inbox'

export const register: Register = on => {
  let stop: (() => void) | undefined
  let inbox: string | undefined // this session's folder, once known
  let said = 0

  // What Claude says in the main conversation goes back to Kisel, one file per reply,
  // so its chat shows both sides. Only while Kisel has made the folder (it is running).
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const text = e.agentId === undefined ? reply(result.answer) : null

    if (text !== null && inbox !== undefined) {
      try {
        if (await $.fs.exists(inbox)) {
          await $.fs.write(`${inbox}/${await $.clock.now()}-${said++}.reply`, text)
        }
      } catch {
        // Kisel's folder went away mid-write: nothing to tell
      }
    }

    return result
  })

  on('session.start', async ($, e, next) => {
    const result = await next(e)
    stop?.()

    const home = await $.env.get('USERPROFILE')
    if (!home) {
      return result // (not Windows, or no Kisel folder to share)
    }

    const dir = folder(home, await $.session.id())
    inbox = dir
    const done = new Set<string>() // handed over by this run (a receipt may fail to write)
    let isBusy = false
    let tick = 0
    let lastReport = ''

    const look = async (): Promise<void> => {
      if (isBusy) {
        return
      }

      isBusy = true

      try {
        // Kisel makes the folder when it first sees the session; until then there is nothing to do.
        if (!(await $.fs.exists(dir))) {
          return
        }

        if (tick++ % 2 === 0) {
          await $.fs.write(`${dir}/alive`, String(await $.clock.now()))
        }

        // every ten looks: what the session knows of the account's limits, for the rings in Kisel's chat
        if (tick % 10 === 1) {
          const usage = await $.session.usage()
          const report = JSON.stringify({
            model: await $.session.model(),
            limits: usage.rateLimits.map(l => ({ kind: l.kind, used: l.percentUsed, resetsAt: l.resetsAt ?? '' })),
            context:
              usage.context.percent === undefined
                ? undefined
                : { used: usage.context.percent, tokens: usage.context.tokens ?? 0, window: usage.context.window },
          })

          if (report !== lastReport) {
            await $.fs.write(`${dir}/limits`, report)
            lastReport = report
          }
        }

        const names = (await $.fs.list(dir)).map(entry => entry.name)

        for (const name of pending(names, done)) {
          const text = clean(await $.fs.read(`${dir}/${name}.prompt`))
          done.add(name)
          await $.fs.write(`${dir}/${name}.taken`, '')

          if (text !== null) {
            // (the person's own words, typed in Kisel: read bare, in a turn of its own once the session is idle)
            void $.prompt.submit({ text, asUser: true })
          }
        }
      } catch {
        // a file half-way through being replaced, or the folder just removed: the next look sees it whole
      } finally {
        isBusy = false
      }
    }

    const timer = $.clock.every(1000, () => void look())
    stop = () => timer.cancel()

    return result
  })
}
