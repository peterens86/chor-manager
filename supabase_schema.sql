-- ============================================================
-- CHOR MANAGER – Supabase Schema (vollständig)
-- Im Supabase SQL Editor ausführen: supabase.com → SQL Editor
-- ============================================================

create extension if not exists "uuid-ossp";

-- ============================================================
-- PROFILES
-- ============================================================
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text not null,
  email text,
  phone text,
  address text,
  stimme text,
  role text not null default 'member',
  created_at timestamptz default now()
);
alter table public.profiles enable row level security;
create policy "Profiles lesbar für Eingeloggte" on profiles for select using (auth.role() = 'authenticated');
create policy "Eigenes Profil bearbeiten" on profiles for update using (auth.uid() = id);
create policy "Admin kann alle Profile bearbeiten" on profiles for update using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "Admin kann Profile einfügen" on profiles for insert with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'member')
  );
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- SONGS
-- ============================================================
create table public.songs (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  liedanfang text,
  refrain text,
  besetzung text,
  thema text,
  anlass text,
  textdichter text,
  komponist text,
  arrangeur text,
  uebersetzer text,
  rechte text,
  originaltitel text,
  quelle text,
  lizenz text,
  links text[] default '{}',
  notizen text,
  created_by uuid references profiles(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.songs enable row level security;
create policy "Songs lesbar" on songs for select using (auth.role() = 'authenticated');
create policy "Admin fügt Songs ein" on songs for insert with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "Admin bearbeitet Songs" on songs for update using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "Admin löscht Songs" on songs for delete using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================================
-- EVENTS
-- ============================================================
create table public.events (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  datum date,
  uhrzeit time,
  ort text,
  -- Allgemeine Rollen (Fallback wenn kein Lied-spezifischer Eintrag)
  dirigent text,
  klavier text,
  instrumente text,
  notizen text,
  created_by uuid references profiles(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.events enable row level security;
create policy "Events lesbar" on events for select using (auth.role() = 'authenticated');
create policy "Admin Events insert" on events for insert with check (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "Admin Events update" on events for update using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));
create policy "Admin Events delete" on events for delete using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================================
-- EVENT PROGRAM (Reihenfolge + Rollen PRO LIED)
-- ============================================================
create table public.event_program (
  id uuid default uuid_generate_v4() primary key,
  event_id uuid references events(id) on delete cascade,
  song_id uuid references songs(id) on delete cascade,
  position integer not null,
  -- Rollen pro Lied (überschreiben die Veranstaltungs-Standardwerte)
  dirigent text default '',
  klavier text default '',
  instrumente text default '',
  unique(event_id, position)
);
alter table public.event_program enable row level security;
create policy "Program lesbar" on event_program for select using (auth.role() = 'authenticated');
create policy "Admin verwaltet Program" on event_program for all using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================================
-- EVENT TASKS (Aufgaben/Zuständigkeiten)
-- ============================================================
create table public.event_tasks (
  id uuid default uuid_generate_v4() primary key,
  event_id uuid references events(id) on delete cascade,
  person text not null,
  aufgabe text not null
);
alter table public.event_tasks enable row level security;
create policy "Tasks lesbar" on event_tasks for select using (auth.role() = 'authenticated');
create policy "Admin verwaltet Tasks" on event_tasks for all using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================================
-- ATTENDANCE
-- ============================================================
create table public.attendance (
  id uuid default uuid_generate_v4() primary key,
  event_id uuid references events(id) on delete cascade,
  member_id uuid references profiles(id) on delete cascade,
  status text check (status in ('yes','no','maybe','')) default '',
  unique(event_id, member_id)
);
alter table public.attendance enable row level security;
create policy "Anwesenheit lesbar" on attendance for select using (auth.role() = 'authenticated');
create policy "Eigene Anwesenheit eintragen" on attendance for insert with check (auth.uid() = member_id);
create policy "Eigene Anwesenheit aktualisieren" on attendance for update using (auth.uid() = member_id);
create policy "Admin verwaltet alle Anwesenheiten" on attendance for all using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================================
-- ANNOUNCEMENTS (Mitteilungen)
-- ============================================================
create table public.announcements (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  body text not null,
  priority text default 'normal',
  created_by uuid references profiles(id),
  created_at timestamptz default now(),
  expires_at timestamptz
);
alter table public.announcements enable row level security;
create policy "Mitteilungen lesbar" on announcements for select using (auth.role() = 'authenticated');
create policy "Admin verwaltet Mitteilungen" on announcements for all using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

create table public.announcement_reads (
  announcement_id uuid references announcements(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  read_at timestamptz default now(),
  primary key (announcement_id, user_id)
);
alter table public.announcement_reads enable row level security;
create policy "Lesebestätigungen eigene" on announcement_reads for all using (auth.uid() = user_id);

-- ============================================================
-- CALENDAR EVENTS (Terminkalender)
-- ============================================================
create table public.calendar_events (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  datum date not null,
  uhrzeit time,
  bis_datum date,
  bis_uhrzeit time,
  ort text,
  beschreibung text,
  typ text default 'probe',  -- 'probe', 'konzert', 'sonstiges'
  event_id uuid references events(id) on delete set null,
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);
alter table public.calendar_events enable row level security;
create policy "Kalender lesbar" on calendar_events for select using (auth.role() = 'authenticated');
create policy "Admin verwaltet Kalender" on calendar_events for all using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================================
-- REALTIME aktivieren
-- ============================================================
alter publication supabase_realtime add table announcements;
alter publication supabase_realtime add table calendar_events;
alter publication supabase_realtime add table events;

-- ============================================================
-- VIEW: Lied-Aufführungsstatistik
-- (für Auswertungen / Analytics verwendet)
-- ============================================================
create or replace view public.song_performance_stats as
select
  s.id as song_id,
  s.title,
  s.besetzung,
  s.komponist,
  count(ep.id) as total_performances,
  max(e.datum) as last_performed,
  min(e.datum) as first_performed,
  array_agg(e.datum order by e.datum desc) filter (where e.datum is not null) as performance_dates,
  array_agg(e.title order by e.datum desc) filter (where e.datum is not null) as event_titles
from songs s
left join event_program ep on ep.song_id = s.id
left join events e on e.id = ep.event_id
group by s.id, s.title, s.besetzung, s.komponist;

-- ============================================================
-- ERSTER ADMIN: Nach dem ersten Login manuell ausführen
-- (eigene User-ID einsetzen)
-- ============================================================
-- update public.profiles set role = 'admin' where email = 'deine@email.de';
