-- Optimistic concurrency (compare-and-swap) for tenant records.
--
-- saas_save_record gains a trailing optional base version argument. The old
-- six-argument function must be dropped first: leaving it in place would create
-- an overload, and six-argument calls would silently resolve to the legacy
-- body without versioning.
drop function if exists public.saas_save_record(uuid,uuid,text,text,jsonb,boolean);

alter table public.saas_records add column if not exists version integer not null default 1;

create or replace function public.saas_save_record(actor uuid,t uuid,k text,rid text,b jsonb,is_new boolean,base integer default null) returns jsonb language plpgsql security definer set search_path='' as $$declare m public.memberships;sub public.saas_subscriptions;n integer;paid numeric;old public.saas_records;clean jsonb;hall jsonb;capacity numeric;begin
 perform 1 from public.organizations where id=t for update;if not found then raise exception 'Organization not found.';end if;
 select * into m from public.memberships where user_id=actor and tenant_id=t and status='active';if not found then raise exception 'Access denied.';end if;
 if not public.saas_has_access(t) then raise exception 'Subscription inactive. Renew before making changes.';end if;
 if k is null or k not in ('halls','bookings','clients','staff','payments','plans','addons') then raise exception 'Invalid resource.';end if;
 if m.role='client' and (k<>'bookings' or not is_new or b->>'clientId' is distinct from m.record_id or b->>'status' is distinct from 'Pending') then raise exception 'Client action not allowed.';end if;
 if m.role='staff' and k in ('halls','staff','plans','addons') then raise exception 'Only owners can manage this resource.';end if;
 select * into old from public.saas_records where id=rid and tenant_id=t and kind=k;
 if not is_new and not found then raise exception 'Record not found.';end if; if not is_new and base is not null and old.version is distinct from base then raise exception 'This record was changed by someone else. Reload and try again.';end if;
 select * into sub from public.saas_subscriptions where tenant_id=t;
 if k='halls' and is_new then select count(*) into n from public.saas_records where tenant_id=t and kind='halls';if n>=(sub.plan_snapshot->>'max_halls')::int then raise exception 'Your subscription hall limit has been reached.';end if;end if;
 if k='staff' and b->>'status'='Active' then select count(*) into n from public.saas_records where tenant_id=t and kind='staff' and body->>'status'='Active' and id<>rid;if n>=(sub.plan_snapshot->>'max_staff')::int then raise exception 'Your subscription team limit has been reached.';end if;end if;
 if jsonb_typeof(b) is distinct from 'object' then raise exception 'Record body must be an object.';end if;
 if k='halls' then
  if jsonb_typeof(b->'capacity') is distinct from 'number' or (b->>'capacity')::numeric<1 or (b->>'capacity')::numeric>10000 or trunc((b->>'capacity')::numeric)<>(b->>'capacity')::numeric then raise exception 'Hall capacity must be a whole number between 1 and 10000.';end if;
 end if;
 if k='bookings' then
  if b->>'status' is null or b->>'status' not in ('Pending','Confirmed','Completed','Cancelled') then raise exception 'Choose a valid booking status.';end if;
  perform public.booking_window(b);
  if jsonb_typeof(b->'total') is distinct from 'number' or (b->>'total')::numeric<0 then raise exception 'Booking total must be a non-negative number.';end if;
  select body into hall from public.saas_records where tenant_id=t and kind='halls' and id=b->>'hallId';
  capacity:=(hall->>'capacity')::numeric;
  if capacity is null then raise exception 'Choose a valid hall and client.';end if;
  if jsonb_typeof(b->'guests') is distinct from 'number' or (b->>'guests')::numeric<1 or trunc((b->>'guests')::numeric)<>(b->>'guests')::numeric or (b->>'guests')::numeric>capacity then raise exception 'Guest count exceeds current hall capacity or is invalid.';end if;
  if greatest(coalesce((b->>'guaranteedPlates')::numeric,0),coalesce((b->>'actualGuests')::numeric,0),coalesce((b->'quote'->>'billedPlates')::numeric,0))>capacity then raise exception 'Attendance exceeds current hall capacity.';end if;
  if hall->>'status'='Maintenance' and (is_new or old.body->>'hallId' is distinct from b->>'hallId') then raise exception 'This hall is under maintenance.';end if;
  if not exists(select 1 from public.saas_records where tenant_id=t and kind='halls' and id=b->>'hallId') or not exists(select 1 from public.saas_records where tenant_id=t and kind='clients' and id=b->>'clientId') then raise exception 'Choose a valid hall and client.';end if;
  if b->>'status'<>'Cancelled' and exists(select 1 from public.saas_records x where x.tenant_id=t and x.kind='bookings' and x.id<>rid and x.body->>'hallId'=b->>'hallId' and x.body->>'status'<>'Cancelled' and public.booking_window(x.body)&&public.booking_window(b)) then raise exception 'Hall unavailable for the selected duration.';end if;
  select coalesce(sum((body->>'amount')::numeric),0) into paid from public.saas_records where tenant_id=t and kind='payments' and body->>'bookingId'=rid;if (b->>'total')::numeric<paid then raise exception 'Booking total is below payments received.';end if;
 end if;
 if k='payments' then
  if jsonb_typeof(b->'amount') is distinct from 'number' or (b->>'amount')::numeric<=0 then raise exception 'Payment amount must be positive.';end if;
  select * into old from public.saas_records where tenant_id=t and kind='bookings' and id=b->>'bookingId';if not found then raise exception 'Booking not found.';end if;
  select coalesce(sum((body->>'amount')::numeric),0) into paid from public.saas_records where tenant_id=t and kind='payments' and body->>'bookingId'=old.id and id<>rid;if paid+(b->>'amount')::numeric>(old.body->>'total')::numeric then raise exception 'Payment exceeds remaining balance.';end if;
 end if;
 clean:=b-'operationsNotes';if is_new then insert into public.saas_records(id,tenant_id,kind,body) values(rid,t,k,clean) returning version into n;else update public.saas_records set body=clean,version=version+1,updated_at=now() where id=rid and tenant_id=t returning version into n;if n is null then raise exception 'Record not found.';end if;end if;
 if k='bookings' then insert into public.record_private(record_id,tenant_id,operations_notes) values(rid,t,case when m.role='client' then '' else coalesce(b->>'operationsNotes','') end) on conflict(record_id) do update set operations_notes=excluded.operations_notes;end if;
 if k in ('staff','clients') then update public.memberships set status=case when b->>'status'='Active' then 'active' else 'inactive' end where tenant_id=t and record_id=rid;end if;
 insert into public.audit_log(actor_id,tenant_id,action,details) values(actor,t,k||case when is_new then '.created' else '.updated' end,jsonb_build_object('record_id',rid));return clean||jsonb_build_object('id',rid,'version',n);end;$$;

create or replace function public.saas_delete_record(actor uuid,t uuid,k text,rid text) returns void language plpgsql security definer set search_path='' as $$declare role text;begin
 perform 1 from public.organizations where id=t for update;select m.role into role from public.memberships m where m.user_id=actor and m.tenant_id=t and m.status='active';
 if role is null or role='client' or (role='staff' and k in ('halls','staff','plans','addons')) then raise exception 'Action not allowed.';end if;if not public.saas_has_access(t) then raise exception 'Subscription inactive.';end if;
 if not exists(select 1 from public.saas_records where tenant_id=t and kind=k and id=rid) then raise exception 'Record not found.';end if;
 if k in ('halls','clients') and exists(select 1 from public.saas_records where tenant_id=t and kind='bookings' and body->>case when k='halls' then 'hallId' else 'clientId' end=rid) then raise exception 'This record still has bookings.';end if;
 if k='bookings' then delete from public.saas_records where tenant_id=t and kind='payments' and body->>'bookingId'=rid;end if;
 delete from public.memberships where tenant_id=t and record_id=rid;
 delete from public.saas_records where tenant_id=t and kind=k and id=rid;
 insert into public.audit_log(actor_id,tenant_id,action,details) values(actor,t,k||'.deleted',jsonb_build_object('record_id',rid));end;$$;

-- RPCs are service-role only: tenant access is enforced by the HTTP layer and
-- by in-function membership/entitlement checks. Authenticated callers must
-- never reach these functions directly.
revoke all on function public.saas_save_record(uuid,uuid,text,text,jsonb,boolean,integer),public.saas_delete_record(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.saas_save_record(uuid,uuid,text,text,jsonb,boolean,integer),public.saas_delete_record(uuid,uuid,text,text) to service_role;
