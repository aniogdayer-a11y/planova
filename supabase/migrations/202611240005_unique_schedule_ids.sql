-- Repair only repeated schedule IDs. Preserve task links, times, text, order,
-- and completion flags. The changed revision prevents stale clients saving
-- with the old duplicate IDs until they reload the repaired plan.
update public.plans p
set data = jsonb_set(p.data, '{schedule_slots}', (
  select jsonb_agg(
    case when occurrence > 1
      then jsonb_set(slot, '{id}', to_jsonb(max_id + position))
      else slot end
    order by position
  )
  from (
    select slot, position,
      row_number() over (partition by slot->>'id' order by position) as occurrence,
      max((slot->>'id')::bigint) over () as max_id
    from jsonb_array_elements(p.data->'schedule_slots')
      with ordinality as items(slot, position)
  ) entries
)), revision = revision + 1, updated_at = now()
where jsonb_array_length(p.data->'schedule_slots') <> (
  select count(distinct slot->>'id')
  from jsonb_array_elements(p.data->'schedule_slots') slot
);
