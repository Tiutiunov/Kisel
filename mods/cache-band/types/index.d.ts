// What the last response of the main conversation said about the prompt cache.
export type CacheCount = {
  /** input tokens the cache served */
  read: number
  /** input tokens the response wrote to the cache */
  written: number
  /** input tokens that went past the cache */
  fresh: number
}

declare module 'claude-code' {
  interface PluginState {
    'cache-band': {
      last: CacheCount | null
      /** of each of the last responses' input, the part the cache served (0..100), newest last */
      history: number[]
    }
  }
}
