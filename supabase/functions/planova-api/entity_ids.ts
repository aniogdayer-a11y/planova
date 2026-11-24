const randomId = () => {
  const bytes = crypto.getRandomValues(new Uint32Array(2))
  return (bytes[0] & 0xffff) * 0x100000000 + bytes[1] || 1
}

// Reserve existing IDs so new entries never reuse an ID in the same plan.
export function createIdAllocator(
  reserved: number[] = [],
  candidate: () => number = randomId,
) {
  const used = new Set(reserved)
  return () => {
    let id = candidate()
    while (used.has(id)) id++
    if (!Number.isSafeInteger(id) || id < 1) throw new Error('Invalid entry ID.')
    used.add(id)
    return id
  }
}
