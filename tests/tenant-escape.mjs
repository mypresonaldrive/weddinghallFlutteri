// Tenant-escape suite: adversarial multi-tenancy checks for the service RPCs.
// Two organizations, hostile actor combinations, suspension enforcement,
// direct-call revocation, and optimistic-concurrency (version CAS) proofs.
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { readFile, readdir } from 'node:fs/promises';
const db = new PGlite();
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}');create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create function auth.jwt() returns jsonb language sql as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated,service_role;grant execute on function auth.uid(),auth.jwt() to anon,authenticated,service_role;`);
for (const file of (await readdir('supabase/migrations')).filter(f => f.endsWith('.sql')).sort())
  await db.exec(await readFile('supabase/migrations/' + file, 'utf8'));

const uid = '00000000-0000-4000-8000-0000000000a1';
const other = '00000000-0000-4000-8000-0000000000a2';
await db.query("insert into auth.users(id,email,email_confirmed_at) values($1,'alpha-owner@example.test',now()),($2,'beta-owner@example.test',now())", [uid, other]);
const plan = (await db.query("update public.saas_plans set published=true where name='Starter' returning id")).rows[0];
const tenantA = (await db.query('select public.saas_register_org($1,$2) as id', [uid, { name: 'Alpha venue', planId: plan.id, interval: 'monthly' }])).rows[0].id;
const tenantB = (await db.query('select public.saas_register_org($1,$2) as id', [other, { name: 'Beta venue', planId: plan.id, interval: 'monthly' }])).rows[0].id;

const save = (actor, t, kind, id, body, fresh = true, base = null) =>
  db.query('select public.saas_save_record($1,$2,$3,$4,$5,$6,$7)', [actor, t, kind, id, body, fresh, base]);
const del = (actor, t, kind, id) =>
  db.query('select public.saas_delete_record($1,$2,$3,$4)', [actor, t, kind, id]);

// Seed both tenants with identical event windows.
const hallA = { name: 'Alpha Hall', capacity: 200, price: 50000, status: 'Available' };
const hallB = { name: 'Beta Hall', capacity: 200, price: 50000, status: 'Available' };
const client = n => ({ name: n, status: 'Active' });
const booking = { name: 'Wedding', date: '2027-05-10', durationMode: 'morning', time: '08:00', status: 'Confirmed', guests: 100, total: 65000 };
await save(uid, tenantA, 'halls', 'hA', hallA);
await save(uid, tenantA, 'clients', 'cA', client('Client A'));
await save(uid, tenantA, 'bookings', 'bA', { ...booking, hallId: 'hA', clientId: 'cA' });
await save(other, tenantB, 'halls', 'hB', hallB);
await save(other, tenantB, 'clients', 'cB', client('Client B'));
await save(other, tenantB, 'bookings', 'bB', { ...booking, hallId: 'hB', clientId: 'cB' });

// 1. Availability is tenant-scoped: identical slot in the other tenant succeeds.
const bRows = (await db.query("select id from public.saas_records where tenant_id=$1 and kind='bookings'", [tenantB])).rows;
assert.deepEqual(bRows.map(r => r.id), ['bB']);

// 2. Cross-tenant writes are rejected in both directions, update and create.
await assert.rejects(save(other, tenantA, 'bookings', 'bA', { ...booking, hallId: 'hA', clientId: 'cA', guests: 50 }, false), /Access denied/);
await assert.rejects(save(uid, tenantB, 'bookings', 'bB', { ...booking, hallId: 'hB', clientId: 'cB', guests: 50 }, false), /Access denied/);
await assert.rejects(save(other, tenantA, 'clients', 'cX', client('Injected')), /Access denied/);
await assert.rejects(save(uid, tenantB, 'halls', 'hX', hallA), /Access denied/);

// 3. Cross-tenant deletes are rejected in both directions.
await assert.rejects(del(other, tenantA, 'bookings', 'bA'), /Action not allowed/);
await assert.rejects(del(uid, tenantB, 'clients', 'cB'), /Action not allowed/);

// 4. A foreign record id cannot be hijacked by re-inserting it in another tenant.
await assert.rejects(save(other, tenantB, 'clients', 'cA', client('Hijack attempt')), /duplicate key/);
const hijacked = (await db.query("select tenant_id from public.saas_records where id='cA'")).rows[0];
assert.equal(hijacked.tenant_id, tenantA);

// 5. Payments can never reference a booking owned by another tenant.
await assert.rejects(save(other, tenantB, 'payments', 'payX', { bookingId: 'bA', amount: 1 }), /Booking not found/);
await assert.rejects(save(uid, tenantA, 'payments', 'payY', { bookingId: 'bB', amount: 1 }), /Booking not found/);

// 6. Suspension is enforced inside the RPCs (via saas_has_access), not only
//    by the HTTP middleware.
await db.query("update public.organizations set status='suspended' where id=$1", [tenantA]);
await assert.rejects(save(uid, tenantA, 'clients', 'cA2', client('Late entry')), /Subscription inactive/);
await assert.rejects(del(uid, tenantA, 'clients', 'cA'), /Subscription inactive/);
await db.query("update public.organizations set status='active' where id=$1", [tenantA]);
await save(uid, tenantA, 'clients', 'cA2', client('Late entry')); // restored org works again

// 7. Authenticated callers cannot reach the RPCs directly (service-role only).
await db.query('set role authenticated');
await assert.rejects(
  db.query('select public.saas_save_record($1,$2,$3,$4,$5,$6,$7)', [uid, tenantA, 'clients', 'cDirect', client('Direct'), true, null]),
  /permission denied/
);
await assert.rejects(db.query('select public.saas_delete_record($1,$2,$3,$4)', [uid, tenantA, 'clients', 'cA2']), /permission denied/);
await db.query('reset role');

// 8. Optimistic concurrency: version CAS rejects stale writers, allows fresh ones.
const unwrap = row => row.saas_save_record ?? row;
const created = unwrap((await save(uid, tenantA, 'clients', 'cV', client('V1'))).rows[0]);
assert.equal(created.version, 1);
const bumped = unwrap((await save(uid, tenantA, 'clients', 'cV', client('V2'), false, 1)).rows[0]);
assert.equal(bumped.version, 2);
await assert.rejects(save(uid, tenantA, 'clients', 'cV', client('V3'), false, 1), /changed by someone else/);
await assert.rejects(save(uid, tenantA, 'clients', 'cV', client('V3'), false, 99), /changed by someone else/);
const legacy = unwrap((await save(uid, tenantA, 'clients', 'cV', client('V4'), false, null)).rows[0]);
assert.equal(legacy.version, 3); // null base keeps legacy last-write-wins behavior
await assert.rejects(save(uid, tenantA, 'clients', 'cV', client('V5'), false, 2), /changed by someone else/);

// 9. Visibility helpers never leak across tenants (record_visible / member_role).
await db.query("select set_config('request.jwt.claim.sub',$1,false)", [uid]);
const ownRow = (await db.query("select body from public.saas_records where id='bA'")).rows[0];
const foreignRow = (await db.query("select body from public.saas_records where id='bB'")).rows[0];
const visOwn = (await db.query("select public.record_visible($1,'bookings','bA',$2::jsonb) as v", [tenantA, ownRow.body])).rows[0].v;
const visForeign = (await db.query("select public.record_visible($1,'bookings','bB',$2::jsonb) as v", [tenantB, foreignRow.body])).rows[0].v;
assert.equal(visOwn, true);
assert.equal(visForeign, false);
assert.equal((await db.query('select public.member_role($1) as r', [tenantB])).rows[0].r, null);

console.log('tenant-escape: all isolation, suspension, and CAS checks passed');
