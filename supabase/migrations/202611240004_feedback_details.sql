alter table public.feedback
  add column if not exists author_avatar text not null default '',
  add column if not exists category text not null default 'General Feedback',
  add column if not exists recommendation text not null default 'yes',
  add column if not exists is_seed boolean not null default false;

alter table public.feedback
  drop constraint if exists feedback_category_check,
  add constraint feedback_category_check
    check (category in ('General Feedback', 'Feature Suggestion', 'Bug Report')),
  drop constraint if exists feedback_recommendation_check,
  add constraint feedback_recommendation_check
    check (recommendation in ('yes', 'maybe', 'no'));

update public.feedback
set is_seed = true, visibility = 'private'
where author_name = 'Planova'
  and content in (
    'Start with the tasks you can realistically finish today.',
    'Leave a little room between tasks so you do not have to rush.',
    'Add a short break between focus sessions.'
  );

drop policy if exists "feedback_likes_read" on public.feedback_likes;
create policy "feedback_likes_read" on public.feedback_likes for select to authenticated
  using (exists (
    select 1 from public.feedback
    where feedback.id = feedback_likes.feedback_id
      and (feedback.visibility = 'public' or feedback.user_id = (select auth.uid()))
  ));

drop policy if exists "feedback_likes_insert" on public.feedback_likes;
create policy "feedback_likes_insert" on public.feedback_likes for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.feedback
      where feedback.id = feedback_likes.feedback_id
        and feedback.visibility = 'public'
        and not feedback.is_seed
    )
  );

drop policy if exists "feedback_likes_delete" on public.feedback_likes;
create policy "feedback_likes_delete" on public.feedback_likes for delete to authenticated
  using (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.feedback
      where feedback.id = feedback_likes.feedback_id
        and (feedback.visibility = 'public' or feedback.user_id = (select auth.uid()))
    )
  );
