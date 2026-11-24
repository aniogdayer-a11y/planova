-- Extend account preferences without changing ownership policies or existing data.
alter table public.settings drop constraint settings_key_check;
alter table public.settings add constraint settings_key_check check (
  key in ('time_format', 'color_theme', 'suggestion_like_short_list',
          'suggestion_like_enough_time', 'suggestion_like_break')
);
alter table public.settings add constraint settings_value_check check (
  (key = 'time_format' and value in ('12-hour', '24-hour')) or
  (key = 'color_theme' and value in ('cream', 'sage', 'lavender', 'rose', 'sky')) or
  (key in ('suggestion_like_short_list', 'suggestion_like_enough_time',
           'suggestion_like_break') and value in ('true', 'false'))
);
