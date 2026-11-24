import { createIdAllocator } from './entity_ids.ts'

Deno.test('colliding candidates produce distinct IDs without reusing existing entries', () => {
  const next = createIdAllocator([100, 101, 103], () => 100)
  const ids = Array.from({ length: 500 }, next)
  if (new Set(ids).size !== ids.length) throw new Error('Duplicate IDs')
  if (ids.some(id => [100, 101, 103].includes(id))) throw new Error('Reused saved ID')
})

Deno.test('new IDs are positive safe integers', () => {
  const next = createIdAllocator()
  const ids = Array.from({ length: 10000 }, next)
  if (new Set(ids).size !== ids.length) throw new Error('Duplicate IDs')
  if (ids.some(id => !Number.isSafeInteger(id) || id < 1)) throw new Error('Unsafe ID')
})
