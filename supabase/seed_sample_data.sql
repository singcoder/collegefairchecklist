-- Optional: run once in SQL Editor to add a sample college fair and checklist.
-- Makes the app show one fair with two groups and a few items.

-- 1. One college fair
INSERT INTO public.college_fairs (name, fair_date)
VALUES ('Spring 2026 Fair', '2026-04-15');

-- 2. Two groups for that fair (use the fair we just added)
INSERT INTO public.checklist_groups (college_fair_id, title, sort_order)
SELECT id, 'Before the fair', 0
FROM public.college_fairs
ORDER BY created_at DESC
LIMIT 1;

INSERT INTO public.checklist_groups (college_fair_id, title, sort_order)
SELECT id, 'Day of the fair', 1
FROM public.college_fairs
ORDER BY created_at DESC
LIMIT 1;

-- 3. Items under "Before the fair"
INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Register for the fair', 'checkbox', 0
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Before the fair' AND f.name = 'Spring 2026 Fair'
LIMIT 1;

INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Prepare resume copies', 'checkbox', 1
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Before the fair' AND f.name = 'Spring 2026 Fair'
LIMIT 1;

INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Target schools to visit', 'text', 2
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Before the fair' AND f.name = 'Spring 2026 Fair'
LIMIT 1;

-- 4. Items under "Day of the fair"
INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Pick up program map', 'checkbox', 0
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Day of the fair' AND f.name = 'Spring 2026 Fair'
LIMIT 1;

INSERT INTO public.checklist_items (group_id, label, item_type, sort_order)
SELECT g.id, 'Notes / follow-ups', 'text', 1
FROM public.checklist_groups g
JOIN public.college_fairs f ON f.id = g.college_fair_id
WHERE g.title = 'Day of the fair' AND f.name = 'Spring 2026 Fair'
LIMIT 1;
