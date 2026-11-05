-- THINK BEFORE AI — شغّل هذا الملف كاملًا في Supabase > SQL Editor

create table participants_ai(
  id uuid primary key default gen_random_uuid(),
  num serial unique,
  code text unique not null,
  name text not null,
  username text unique not null,
  major text, university text, country text, linkedin text,
  path text not null check (path in ('HUMAN THINKING','AI THINKING','HUMAN + AI')),
  live boolean default false,
  consent boolean default false,
  attended boolean default false,
  created_at timestamptz default now()
);
create table outputs(
  id uuid primary key default gen_random_uuid(),
  pid uuid unique references participants_ai(id) on delete cascade,
  title text, problem text, solution text, thinking text, ai_role text, result text, post_url text, image_url text,
  status text default 'pending' check (status in ('pending','approved','rejected')),
  reason text,
  created_at timestamptz default now()
);
create table votes(
  oid uuid references outputs(id) on delete cascade,
  voter text,
  primary key(oid, voter)
);

alter table participants_ai enable row level security;
alter table outputs enable row level security;
alter table votes enable row level security;

-- الإدارة فقط (مستخدم مسجّل دخول عبر Supabase Auth) تصل مباشرة للجداول
create policy admin_p on participants_ai for all to authenticated using (true) with check (true);
create policy admin_o on outputs for all to authenticated using (true) with check (true);
create policy admin_v on votes for all to authenticated using (true) with check (true);

-- المعرض العام: المخرجات المعتمدة لأصحاب الموافقة فقط
create view gallery as
  select o.id, o.title, o.problem, o.solution, o.result, o.post_url, o.image_url,
         p.name, p.path, p.university, p.country, p.num, p.linkedin,
         (select count(*) from votes v where v.oid = o.id) as votes
  from outputs o join participants_ai p on p.id = o.pid
  where o.status = 'approved' and p.consent;
grant select on gallery to anon, authenticated;

-- التسجيل (يحجز المقعد المباشر تلقائيًا حتى 100)
create function register(p_name text, p_username text, p_major text, p_univ text, p_country text,
                         p_linkedin text, p_path text, p_live boolean, p_consent boolean)
returns json language plpgsql security definer set search_path = public as $$
declare v_code text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
        v_live boolean := p_live and (select count(*) from participants_ai where live) < 100;
        v_num int;
begin
  if exists(select 1 from participants_ai where username = p_username) then raise exception 'username_taken'; end if;
  insert into participants_ai(code,name,username,major,university,country,linkedin,path,live,consent)
  values (v_code,p_name,p_username,p_major,p_univ,p_country,nullif(p_linkedin,''),p_path,v_live,p_consent)
  returning num into v_num;
  return json_build_object('num', v_num, 'code', v_code, 'live', v_live, 'live_requested', p_live);
end $$;

create function stats() returns json language sql security definer set search_path = public as $$
  select json_build_object(
    'registered', (select count(*) from participants_ai),
    'seats_left', 100 - (select count(*) from participants_ai where live),
    'outputs', (select count(*) from outputs where status = 'approved'));
$$;

-- رمز الدخول عشوائي (10 خانات) وفريد لكل مشارك. قفل 15 دقيقة بعد 5 محاولات خاطئة لنفس الرقم.
create table auth_fail(num int, at timestamptz default now());
alter table auth_fail enable row level security;

create function check_login(p_num int, p_code text) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if (select count(*) from auth_fail where num = p_num and at > now() - interval '15 minutes') >= 5 then
    raise exception 'locked';
  end if;
  select id into v_id from participants_ai
   where num = p_num and code = upper(replace(replace(coalesce(p_code,''), '-', ''), ' ', ''));
  if v_id is null then insert into auth_fail(num) values (p_num); end if;
  return v_id;
end $$;
revoke execute on function check_login from public, anon, authenticated;

create function my_status(p_num int, p_code text) returns json language plpgsql security definer set search_path = public as $$
declare v_id uuid := check_login(p_num, p_code);
begin
  if v_id is null then return null; end if;
  return (select json_build_object('name', p.name, 'path', p.path, 'attended', p.attended,
         'status', o.status, 'reason', o.reason, 'title', o.title)
         from participants_ai p left join outputs o on o.pid = p.id where p.id = v_id);
end $$;

create function submit_output(p_num int, p_code text, p_title text, p_problem text, p_solution text,
                              p_thinking text, p_ai text, p_result text, p_url text, p_image text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_pid uuid;
begin
  v_pid := check_login(p_num, p_code);
  if v_pid is null then return false; end if;
  if p_url !~* '^https?://' then return false; end if;
  if p_image is not null and p_image !~ '^https://[^/]+/storage/v1/object/public/outputs/' then return false; end if;
  insert into outputs(pid,title,problem,solution,thinking,ai_role,result,post_url,image_url,status)
  values (v_pid,p_title,p_problem,p_solution,p_thinking,p_ai,p_result,p_url,p_image,'pending')
  on conflict (pid) do update set title=excluded.title, problem=excluded.problem, solution=excluded.solution,
    thinking=excluded.thinking, ai_role=excluded.ai_role, result=excluded.result, post_url=excluded.post_url,
    image_url=coalesce(excluded.image_url, outputs.image_url), status='pending', reason=null;
  return true;
end $$;

create function vote(p_oid uuid, p_voter text) returns void language sql security definer set search_path = public as $$
  insert into votes(oid, voter) values (p_oid, p_voter) on conflict do nothing;
$$;

grant execute on function register, stats, my_status, submit_output, vote to anon, authenticated;

-- تخزين صور المخرجات (حد 2 ميغابايت، صور فقط)
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('outputs','outputs',true,2097152,array['image/jpeg','image/png','image/webp']) on conflict (id) do nothing;
create policy outputs_upload on storage.objects for insert to anon, authenticated with check (bucket_id = 'outputs');
create policy outputs_admin_delete on storage.objects for delete to authenticated using (bucket_id = 'outputs');

-- بعد إنشاء مستخدم الإدارة من Authentication > Users، لا تفعّل التسجيل العام (Disable signups).
