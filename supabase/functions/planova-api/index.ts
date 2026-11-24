import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = (origin: string | null) => ({
  'Access-Control-Allow-Origin': origin || '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Vary': 'Origin',
})
const json = (body: unknown, status = 200, origin: string | null = null) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(origin), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
const fail = (message: string, status = 400, origin: string | null = null) => json({ error: message }, status, origin)
const datePattern = /^\d{4}-\d{2}-\d{2}$/
const cleanDate = (value: string) => {
  if (!datePattern.test(value) || new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) !== value) throw new Error('Choose a valid date.')
  return value
}
const minutesOf = (value: string) => {
  const match = value?.match(/^(\d{1,2}):(\d{2})(?: (AM|PM))?$/)
  if (!match) throw new Error('Choose a valid start time.')
  let hour = Number(match[1]); const minute = Number(match[2])
  if (minute > 59 || (match[3] ? hour < 1 || hour > 12 : hour > 23)) throw new Error('Choose a valid start time.')
  if (match[3]) hour = hour % 12 + (match[3] === 'PM' ? 12 : 0)
  return hour * 60 + minute
}
const timeOf = (value: number) => {
  const hour = Math.floor(value / 60) % 24
  return `${hour % 12 || 12}:${String(value % 60).padStart(2, '0')} ${hour >= 12 ? 'PM' : 'AM'}`
}
const entityId = () => Math.floor(Date.now() * 100 + Math.random() * 99)

function buildPlan(date: string, input: any, old: any = null) {
  const tasksInput = input?.tasks
  if (!Array.isArray(tasksInput) || tasksInput.length < 1 || tasksInput.length > 30) throw new Error('Add between 1 and 30 tasks.')
  const start = minutesOf(input.start_time)
  const hasBreaks = input.has_breaks === 1 || input.has_breaks === true
  const breakCount = hasBreaks ? Number(input.break_count) : 0
  const breakMinutes = hasBreaks ? Number(input.break_duration_minutes) : 0
  if (!Number.isInteger(breakCount) || breakCount < 0 || breakCount > 3 || !Number.isInteger(breakMinutes) || (breakCount > 0 && (breakMinutes < 1 || breakMinutes > 60))) throw new Error('Check your break settings.')
  const seen = new Set<string>()
  const tasks = tasksInput.map((item: any, index: number) => {
    const title = typeof item.title === 'string' ? item.title.trim() : ''
    const duration = Number(item.duration_minutes)
    if (!title || title.length > 200 || !Number.isInteger(duration) || duration < 1 || duration > 480 || seen.has(title.toLowerCase())) throw new Error('Check task names and durations.')
    seen.add(title.toLowerCase())
    const previous = old?.tasks?.find((task: any) => task.id === item.id)
    const unchanged = previous && previous.title === title && previous.duration_minutes === duration
    return { id: previous?.id || entityId() + index, plan_id: old?.id || entityId(), title, duration_minutes: duration, order_index: index, is_completed: unchanged ? previous.is_completed : 0, completed_at: unchanged ? previous.completed_at : null }
  })
  const total = tasks.reduce((sum: number, task: any) => sum + task.duration_minutes, 0)
  if (start + total + breakCount * breakMinutes > 1440) throw new Error('This plan goes past midnight. Shorten the tasks or start earlier.')
  let current = start, focus = 0, used = 0
  const interval = breakCount ? Math.min(25, Math.floor(total / (breakCount + 1))) : total
  const slots: any[] = []
  tasks.forEach((task: any) => {
    let remaining = task.duration_minutes, session = 0
    while (remaining > 0) {
      const untilBreak = used < breakCount ? interval * (used + 1) - focus : remaining
      const duration = Math.min(remaining, Math.max(1, untilBreak))
      slots.push({ id: entityId() + slots.length, plan_id: task.plan_id, task_id: task.id, slot_type: 'focus', title: task.title, subtitle: `Focus session ${++session}`, start_time: timeOf(current), end_time: timeOf(current + duration), duration_minutes: duration, order_index: slots.length, is_completed: task.is_completed })
      current += duration; remaining -= duration; focus += duration
      if (used < breakCount && focus >= interval * (used + 1)) {
        slots.push({ id: entityId() + slots.length, plan_id: task.plan_id, task_id: null, slot_type: 'break', title: 'Take a break', subtitle: 'Break', start_time: timeOf(current), end_time: timeOf(current + breakMinutes), duration_minutes: breakMinutes, order_index: slots.length, is_completed: 0 })
        current += breakMinutes; used++
      }
    }
  })
  return { id: old?.id || tasks[0].plan_id, plan_date: date, start_time: timeOf(start), has_breaks: hasBreaks ? 1 : 0, break_count: breakCount, break_duration_minutes: breakMinutes, total_focus_minutes: total, end_time: timeOf(current), created_at: old?.created_at || new Date().toISOString(), tasks, schedule_slots: slots }
}

Deno.serve(async (req) => {
  const origin = req.headers.get('origin')
  const allowedOrigins = (Deno.env.get('ALLOWED_ORIGINS') || '')
    .split(',')
    .map(value => value.trim())
    .filter(Boolean)
  if (origin && allowedOrigins.length && !allowedOrigins.includes(origin)) {
    return fail('Origin is not allowed.', 403)
  }
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors(origin) })
  try {
    const authorization = req.headers.get('Authorization') || ''
    const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } } })
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) return fail('Please sign in.', 401, origin)
    const url = new URL(req.url)
    const marker = '/planova-api/'
    const path = url.pathname.includes(marker) ? url.pathname.split(marker)[1] : ''
    const rawBody = ['POST', 'PUT'].includes(req.method) ? await req.text() : ''
    let body = null
    if (rawBody.trim()) {
      try { body = JSON.parse(rawBody) }
      catch { return fail('Invalid JSON body.', 400, origin) }
    }

    if (req.method === 'GET' && path === 'profile') {
      const { data, error } = await supabase.from('profiles').select('name,avatar_data').single()
      if (error) throw error
      const plans = await supabase.from('plans').select('data')
      let streak = 0
      const completed = new Set<string>()
      for (const row of plans.data || []) for (const task of row.data.tasks || []) if (task.is_completed && task.completed_at) completed.add(String(task.completed_at).slice(0, 10))
      const today = cleanDate(url.searchParams.get('today') || new Date().toISOString().slice(0, 10))
      let cursor = new Date(today + 'T00:00:00Z')
      while (completed.has(cursor.toISOString().slice(0, 10))) { streak++; cursor.setUTCDate(cursor.getUTCDate() - 1) }
      return json({ profile: { id: 1, name: data.name, workspace: 'Personal', tagline: '', avatar_url: data.avatar_data || '', streak_count: streak, last_active_date: today } }, 200, origin)
    }
    if (req.method === 'PUT' && path === 'profile') {
      const name = String(body?.name || '').trim()
      if (name.length < 2 || name.length > 60) return fail('Enter a valid name.', 400, origin)
      const { error } = await supabase.from('profiles').update({ name, updated_at: new Date().toISOString() }).eq('user_id', user.id)
      if (error) throw error
      return json({ ok: true }, 200, origin)
    }
    if (req.method === 'PUT' && path === 'profile/avatar') {
      const encoded = body?.image_base64
      let avatar = ''
      if (encoded != null) {
        if (typeof encoded !== 'string' || encoded.length > 2_800_000) return fail('Choose an image smaller than 2 MB.', 413, origin)
        const bytes = Uint8Array.from(atob(encoded), c => c.charCodeAt(0))
        let mime = ''
        if (bytes[0] === 0x89 && bytes[1] === 0x50) mime = 'png'
        else if (bytes[0] === 0xff && bytes[1] === 0xd8) mime = 'jpeg'
        else if (String.fromCharCode(...bytes.slice(0, 4)) === 'RIFF') mime = 'webp'
        if (!mime) return fail('Choose a PNG, JPEG or WebP image.', 400, origin)
        avatar = `data:image/${mime};base64,${encoded}`
      }
      const { error } = await supabase.from('profiles').update({ avatar_data: avatar, updated_at: new Date().toISOString() }).eq('user_id', user.id)
      if (error) throw error
      return json({ ok: true }, 200, origin)
    }
    if (req.method === 'GET' && path === 'settings') {
      const { data, error } = await supabase.from('settings').select('key,value')
      if (error) throw error
      return json({ settings: Object.fromEntries((data || []).map(row => [row.key, row.value])) }, 200, origin)
    }
    if (req.method === 'PUT' && path === 'settings') {
      const allowed: Record<string, string[]> = {
        time_format: ['12-hour', '24-hour'],
        color_theme: ['cream', 'sage', 'lavender', 'rose', 'sky'],
        suggestion_like_short_list: ['true', 'false'],
        suggestion_like_enough_time: ['true', 'false'],
        suggestion_like_break: ['true', 'false'],
      }
      if (!Object.hasOwn(allowed, body?.key) || !allowed[body.key].includes(body?.value)) return fail('Invalid setting.', 400, origin)
      const { error } = await supabase.from('settings').upsert({ user_id: user.id, key: body.key, value: body.value })
      if (error) throw error
      return json({ ok: true }, 200, origin)
    }
    if (req.method === 'GET' && path.startsWith('plans/')) {
      const date = cleanDate(path.slice(6))
      const { data, error } = await supabase.from('plans').select('revision,data').eq('plan_date', date).maybeSingle()
      if (error) throw error
      return json(data ? { plan: data.data, revision: data.revision } : { plan: null, revision: 0 }, 200, origin)
    }
    if (req.method === 'PUT' && path.startsWith('plans/')) {
      const date = cleanDate(path.slice(6)); const expected = Number(body?.expected_revision)
      const { data: current, error: readError } = await supabase.from('plans').select('revision,data').eq('plan_date', date).maybeSingle()
      if (readError) throw readError
      if (expected !== (current?.revision || 0)) return fail('This plan changed on another device. Reopen it before saving.', 409, origin)
      const plan = buildPlan(date, body?.plan, current?.data)
      const revision = expected + 1
      const write = current
        ? await supabase.from('plans').update({ revision, data: plan, updated_at: new Date().toISOString() }).eq('plan_date', date).eq('revision', expected).select('revision').maybeSingle()
        : await supabase.from('plans').insert({ user_id: user.id, plan_date: date, revision, data: plan }).select('revision').maybeSingle()
      const { data: saved, error } = write
      if (error) throw error
      if (!saved) return fail('This plan changed on another device. Reopen it before saving.', 409, origin)
      return json({ plan, revision }, 200, origin)
    }
    if (req.method === 'POST' && /^(tasks|slots)\/\d+$/.test(path)) {
      const [kind, idText] = path.split('/'); const id = Number(idText); const expected = Number(body?.expected_revision)
      const { data: rows, error: readError } = await supabase.from('plans').select('plan_date,revision,data')
      if (readError) throw readError
      const row = (rows || []).find(item => (kind === 'tasks' ? item.data.tasks : item.data.schedule_slots).some((entry: any) => entry.id === id))
      if (!row) return fail('Task not found.', 404, origin)
      if (row.revision !== expected) return fail('This plan changed on another device.', 409, origin)
      const plan = structuredClone(row.data); const completed = body?.completed === true
      if (kind === 'tasks') {
        const task = plan.tasks.find((entry: any) => entry.id === id); task.is_completed = completed ? 1 : 0; task.completed_at = completed ? task.completed_at || new Date().toISOString() : null
        plan.schedule_slots.filter((entry: any) => entry.task_id === id && entry.slot_type === 'focus').forEach((entry: any) => entry.is_completed = completed ? 1 : 0)
      } else {
        const slot = plan.schedule_slots.find((entry: any) => entry.id === id); slot.is_completed = completed ? 1 : 0
        if (slot.task_id != null) { const task = plan.tasks.find((entry: any) => entry.id === slot.task_id); task.is_completed = plan.schedule_slots.filter((entry: any) => entry.task_id === slot.task_id && entry.slot_type === 'focus').every((entry: any) => entry.is_completed) ? 1 : 0; task.completed_at = task.is_completed ? task.completed_at || new Date().toISOString() : null }
      }
      const revision = expected + 1
      const { data: saved, error } = await supabase.from('plans').update({ data: plan, revision, updated_at: new Date().toISOString() }).eq('plan_date', row.plan_date).eq('revision', expected).select('revision').maybeSingle()
      if (error) throw error
      if (!saved) return fail('This plan changed on another device.', 409, origin)
      return json({ plan, revision }, 200, origin)
    }
    if (req.method === 'GET' && path === 'activity') {
      const today = cleanDate(url.searchParams.get('today') || new Date().toISOString().slice(0, 10)); const { data, error } = await supabase.from('plans').select('data')
      if (error) throw error
      const counts = new Map<string, number>()
      for (const row of data || []) for (const task of row.data.tasks || []) if (task.is_completed && task.completed_at) { const date = String(task.completed_at).slice(0, 10); counts.set(date, (counts.get(date) || 0) + 1) }
      const weekly = Array.from({ length: 7 }, (_, index) => { const date = new Date(today + 'T00:00:00Z'); date.setUTCDate(date.getUTCDate() - 6 + index); const key = date.toISOString().slice(0, 10); return { date: key, tasks_completed: counts.get(key) || 0 } })
      return json({ weekly }, 200, origin)
    }
    if (req.method === 'GET' && path === 'feedback') {
      const { data: rows, error: fbError } = await supabase
        .from('feedback')
        .select('id, user_id, author_name, author_avatar, content, category, recommendation, visibility, created_at, updated_at, is_seed')
        .eq('is_seed', false)
        .order('created_at', { ascending: false })
      if (fbError) throw fbError

      const items = rows || []

      const { data: likes, error: likesError } = await supabase
        .from('feedback_likes')
        .select('feedback_id, user_id')
      if (likesError) throw likesError

      const counts = new Map<string, number>()
      const likedSet = new Set<string>()
      for (const row of (likes || [])) {
        counts.set(row.feedback_id, (counts.get(row.feedback_id) || 0) + 1)
        if (row.user_id === user.id) likedSet.add(row.feedback_id)
      }

      const feedback = items.map((item: any) => ({
        ...item,
        likes_count: counts.get(item.id) || 0,
        is_liked_by_me: likedSet.has(item.id),
        is_mine: item.user_id === user.id
      }))
      return json({ feedback }, 200, origin)
    }
    if (req.method === 'POST' && path === 'feedback') {
      const content = String(body?.content || '').trim()
      const visibility = body?.visibility === 'public' ? 'public' : 'private'
      const category = body?.category ?? 'General Feedback'
      const recommendation = body?.recommendation ?? 'yes'
      if (!content || content.length > 1000) return fail('Feedback must be between 1 and 1000 characters.', 400, origin)
      if (!['General Feedback', 'Feature Suggestion', 'Bug Report'].includes(category)) return fail('Choose a feedback category.', 400, origin)
      if (!['yes', 'maybe', 'no'].includes(recommendation)) return fail('Choose a recommendation response.', 400, origin)
      const { data: profile, error: profileError } = await supabase.from('profiles').select('name,avatar_data').eq('user_id', user.id).maybeSingle()
      if (profileError) throw profileError
      const author_name = profile?.name || 'Planova User'
      const author_avatar = profile?.avatar_data || ''

      const { data: item, error: insError } = await supabase
        .from('feedback')
        .insert({ user_id: user.id, author_name, author_avatar, content, category, recommendation, visibility })
        .select()
        .single()
      if (insError) throw insError
      return json({
        feedback: {
          ...item,
          likes_count: 0,
          is_liked_by_me: false,
          is_mine: true
        }
      }, 201, origin)
    }
    if (req.method === 'PUT' && path.startsWith('feedback/') && !path.endsWith('/like')) {
      const id = path.slice('feedback/'.length)
      const content = String(body?.content || '').trim()
      const visibility = body?.visibility === 'public' ? 'public' : 'private'
      const category = body?.category ?? 'General Feedback'
      const recommendation = body?.recommendation ?? 'yes'
      if (!content || content.length > 1000) return fail('Feedback must be between 1 and 1000 characters.', 400, origin)
      if (!['General Feedback', 'Feature Suggestion', 'Bug Report'].includes(category)) return fail('Choose a feedback category.', 400, origin)
      if (!['yes', 'maybe', 'no'].includes(recommendation)) return fail('Choose a recommendation response.', 400, origin)

      const { data: item, error: updError } = await supabase
        .from('feedback')
        .update({ content, category, recommendation, visibility, updated_at: new Date().toISOString() })
        .eq('id', id)
        .eq('user_id', user.id)
        .select()
        .maybeSingle()
      if (updError) throw updError
      if (!item) return fail('Feedback not found or unauthorized.', 404, origin)

      const { count } = await supabase.from('feedback_likes').select('*', { count: 'exact', head: true }).eq('feedback_id', id)
      const { data: myLike } = await supabase.from('feedback_likes').select('feedback_id').eq('feedback_id', id).eq('user_id', user.id).maybeSingle()

      return json({
        feedback: {
          ...item,
          likes_count: count || 0,
          is_liked_by_me: Boolean(myLike),
          is_mine: true
        }
      }, 200, origin)
    }
    if (req.method === 'DELETE' && path.startsWith('feedback/') && !path.endsWith('/like')) {
      const id = path.slice('feedback/'.length)
      const { error: delError } = await supabase
        .from('feedback')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id)
      if (delError) throw delError
      return json({ ok: true }, 200, origin)
    }
    if (req.method === 'POST' && path.startsWith('feedback/') && path.endsWith('/like')) {
      const id = path.slice('feedback/'.length, path.length - '/like'.length)
      const { data: existing, error: readError } = await supabase
        .from('feedback_likes')
        .select('feedback_id')
        .eq('feedback_id', id)
        .eq('user_id', user.id)
        .maybeSingle()
      if (readError) throw readError

      if (existing) {
        const { error } = await supabase.from('feedback_likes').delete().eq('feedback_id', id).eq('user_id', user.id)
        if (error) throw error
      } else {
        const { error } = await supabase.from('feedback_likes').insert({ feedback_id: id, user_id: user.id })
        if (error) throw error
      }

      const { count, error: countError } = await supabase.from('feedback_likes').select('*', { count: 'exact', head: true }).eq('feedback_id', id)
      if (countError) throw countError
      return json({
        is_liked_by_me: !existing,
        likes_count: count || 0
      }, 200, origin)
    }
    if (req.method === 'POST' && path === 'generate') {
      const apiKey = Deno.env.get('GEMINI_API_KEY'); if (!apiKey) return fail('Planning is not configured.', 503, origin)
      const tasks = body?.tasks
      if (!Array.isArray(tasks) || tasks.length < 1 || tasks.length > 30) return fail('Invalid planning request.', 400, origin)
      const prompt = { date: body.date, start_time: body.start_time, break_count: body.break_count, break_minutes: body.break_minutes, tasks: tasks.map((task: any, input_index: number) => ({ input_index, title: String(task.title).slice(0, 200), duration_minutes: Number(task.duration_minutes) || 0 })) }
      const model = Deno.env.get('GEMINI_MODEL') || 'gemini-2.5-flash'
      const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey }, body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: `Estimate realistic task durations in minutes. Return JSON only as {"tasks":[{"input_index":0,"duration_minutes":30}]}. Preserve input order and include every task.\n${JSON.stringify(prompt)}` }] }], generationConfig: { responseMimeType: 'application/json' } }) })
      if (!response.ok) return fail('Planning service is temporarily unavailable.', response.status === 429 ? 429 : 502, origin)
      const result = await response.json(); return json({ candidates: result.candidates }, 200, origin)
    }
    return fail('Not found.', 404, origin)
  } catch (error) {
    console.error(error)
    return fail(error instanceof Error ? error.message : 'Please try again.', 500, origin)
  }
})

