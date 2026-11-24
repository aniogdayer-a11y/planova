export async function generateWithRetry(
  request: () => Promise<Response>,
  wait: () => Promise<void> = () => new Promise(resolve => setTimeout(resolve, 750)),
) {
  for (let attempt = 0; ; attempt++) {
    let response: Response
    try { response = await request() }
    catch { response = new Response('{}', { status: 503 }) }
    if (attempt === 1 || ![429, 500, 502, 503, 504].includes(response.status)) return response
    await response.body?.cancel()
    await wait()
  }
}

export function basicEstimates(tasks: { title: string; duration_minutes: number }[], budget: number) {
  const auto = tasks.filter(task => task.duration_minutes === 0).length
  const fixed = tasks.reduce((sum, task) => sum + task.duration_minutes, 0)
  if (!Number.isInteger(budget) || budget < fixed + auto * 5) throw new Error('These tasks do not fit the available time.')
  const preferred = tasks.map(task => {
    if (task.duration_minutes) return 0
    if (/\b(check|email|reply|message|water)\b/i.test(task.title)) return 5
    if (/\b(unwind|unwinding|relax|meditate)\b/i.test(task.title)) return 15
    if (/\b(project|assignment|workout)\b/i.test(task.title)) return 50
    return 25
  })
  const extra = Math.max(0, budget - fixed - auto * 5)
  const desiredExtra = preferred.reduce<number>((sum, value) => sum + Math.max(0, value - 5), 0)
  const scale = desiredExtra ? Math.min(1, extra / desiredExtra) : 0
  return tasks.map((task, input_index) => ({
    input_index,
    duration_minutes: task.duration_minutes || 5 + Math.floor((preferred[input_index] - 5) * scale),
  }))
}

export function validEstimates(result: any, tasks: { duration_minutes: number }[], budget: number) {
  try {
    const candidate = result.candidates?.[0]
    if (candidate?.finishReason !== 'STOP') return false
    const text = candidate.content.parts.filter((part: any) => !part.thought && typeof part.text === 'string').map((part: any) => part.text).join('')
    const output = JSON.parse(text).tasks
    if (!Array.isArray(output) || output.length !== tasks.length) return false
    const seen = new Set<number>()
    let total = 0
    for (const row of output) {
      const index = row.input_index, duration = row.duration_minutes
      if (!Number.isInteger(index) || index < 0 || index >= tasks.length || seen.has(index) || !Number.isInteger(duration) || duration < 1 || duration > 480) return false
      const original = tasks[index].duration_minutes
      if (original ? original !== duration : duration < 5) return false
      seen.add(index)
      total += duration
    }
    return total <= budget
  } catch { return false }
}
