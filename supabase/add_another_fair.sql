-- Add another college fair with the same groups and items as the sample.
-- Edit the name and date below, then run in Supabase SQL Editor.
-- Run once per fair; change name/date and run again to add more.

-- Fair to add (edit these):
--   Name: Fall 2026 Fair
--   Date: 2026-10-01

-- 1. Insert the new college fair
INSERT INTO public.college_fairs (name, fair_date)
VALUES ('Fall 2026 Fair', '2026-10-01');

-- 2. Same two groups for this fair
INSERT INTO public.checklist_groups (college_fair_id, title, sort_order)
SELECT id, 'Before the fair', 0
FROM public.college_fairs
WHERE name = 'Fall 2026 Fair'
ORDER BY created_at DESC
LIMIT 1;

INSERT INTO public.checklist_groups (college_fair_id, title, sort_order)
SELECT id, 'Day of the fair', 1
FROM public.college_fairs
WHERE name = 'Fall 2026 Fair'
ORDER BY created_at DESC
LIMIT 1;

-- 3. Same items under "Before the fair"
INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Register for the fair', 'checkbox', 0
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Before the fair' AND f.name = 'Fall 2026 Fair'
LIMIT 1;

INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Prepare resume copies', 'checkbox', 1
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Before the fair' AND f.name = 'Fall 2026 Fair'
LIMIT 1;

INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Target schools to visit', 'text', 2
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Before the fair' AND f.name = 'Fall 2026 Fair'
LIMIT 1;

-- 4. Same items under "Day of the fair"
INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Pick up program map', 'checkbox', 0
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Day of the fair' AND f.name = 'Fall 2026 Fair'
LIMIT 1;

INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Notes / follow-ups', 'text', 1
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Day of the fair' AND f.name = 'Fall 2026 Fair'
LIMIT 1;
