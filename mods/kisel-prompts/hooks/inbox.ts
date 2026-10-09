// The folder Kisel and this mod share for one session (Kisel's side is src/core/PromptRelay):
//   alive        this mod's heartbeat
//   <n>.prompt   a prompt Kisel wrote
//   <n>.taken    this mod's receipt for it

//
// It is in the home folder, not under AppData: the Claude desktop app is a packaged app,
// and Windows keeps what it (and this mod inside it) writes under AppData in a private
// copy that Kisel never sees. (Kisel names the same folder in src/core/Paths.h.)

const BACKSLASH = String.fromCharCode(92)

export const folder = (home: string, sessionId: string): string => {
  let base = home.split(BACKSLASH).join('/')

  while (base.endsWith('/')) {
    base = base.slice(0, -1)
  }

  return `${base}/.kisel/inbox/${sessionId}`
}

// The prompts still to be handed over, oldest first: a `.prompt` without its `.taken`,
// not handed over already by this run. (Their names begin with the time Kisel wrote them.)
export const pending = (names: readonly string[], done: ReadonlySet<string>): string[] => {
  const taken = new Set(names.filter(n => n.endsWith('.taken')).map(n => n.slice(0, -'.taken'.length)))

  return names
    .filter(n => n.endsWith('.prompt'))
    .map(n => n.slice(0, -'.prompt'.length))
    .filter(n => !taken.has(n) && !done.has(n))
    .sort()
}

// What Claude said, for Kisel's chat: nothing when it said nothing (a step that only
// called tools), and cut where a bubble would stop being a bubble.
export const reply = (answer: string): string | null => {
  const body = answer.trim()

  if (body === '') {
    return null
  }

  return body.length > 12000 ? `${body.slice(0, 12000)}\n…` : body
}

// A prompt is text a person typed into a one-line field: bounded, and never empty.
export const clean = (text: string): string | null => {
  const body = text.trim()

  return body === '' || body.length > 20000 ? null : body
}
