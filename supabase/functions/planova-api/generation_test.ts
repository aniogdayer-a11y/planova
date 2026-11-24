import { basicEstimates, generateWithRetry, validEstimates } from './generation.ts'

Deno.test('invalid, missing, over-budget, and changed fixed estimates are rejected', () => {
  const input = [{ duration_minutes: 0 }, { duration_minutes: 15 }]
  const response = (rows: any[]) => ({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify({ tasks: rows }) }] } }] })
  const valid = [{ input_index: 0, duration_minutes: 5 }, { input_index: 1, duration_minutes: 15 }]
  if (!validEstimates(response(valid), input, 20)) throw new Error('Valid estimates rejected')
  if (validEstimates(response(valid), input, 19)) throw new Error('Exceeded time budget')
  if (validEstimates(response(valid.slice(0, 1)), input, 20)) throw new Error('Missing task accepted')
  if (validEstimates(response([valid[0], valid[0]]), input, 20)) throw new Error('Duplicate task accepted')
  if (validEstimates(response([valid[0], { input_index: 1, duration_minutes: 10 }]), input, 20)) throw new Error('Changed fixed duration accepted')
})

Deno.test('transient generation failure retries once and can recover', async () => {
  let calls = 0
  const result = await generateWithRetry(async () => new Response('{}', { status: ++calls === 1 ? 503 : 200 }), async () => {})
  if (calls !== 2 || result.status !== 200) throw new Error('Retry failed')
  await result.body?.cancel()
})

Deno.test('authentication failures are not retried or disguised', async () => {
  let calls = 0
  const result = await generateWithRetry(async () => { calls++; return new Response('{}', { status: 403 }) }, async () => {})
  if (calls !== 1 || result.status !== 403) throw new Error('Unauthorized request retried')
  await result.body?.cancel()
})

Deno.test('basic estimates fit a large plan and preserve supplied durations', () => {
  const input = Array.from({ length: 200 }, (_, i) => ({ title: 'Review '+i, duration_minutes: i === 0 ? 30 : 0 }))
  const output = basicEstimates(input, 1100)
  if (output.length !== 200 || output[0].duration_minutes !== 30) throw new Error('Lost task or changed fixed duration')
  if (output.reduce((sum, task) => sum + task.duration_minutes, 0) > 1100) throw new Error('Exceeded budget')
  if (output.slice(1).some(task => task.duration_minutes < 5)) throw new Error('Invalid auto duration')
})

Deno.test('basic estimates reject an impossible day without dropping tasks', () => {
  let rejected = false
  try { basicEstimates([{ title: 'Review', duration_minutes: 60 }], 10) }
  catch { rejected = true }
  if (!rejected) throw new Error('Impossible day accepted')
})
