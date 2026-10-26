create table if not exists public.payment_sessions (
  order_id text primary key references public.orders(id) on delete cascade,
  provider text not null check (provider = 'xendit'),
  provider_session_id text not null unique,
  checkout_url text not null,
  amount_centavos bigint not null check (amount_centavos > 0),
  currency text not null check (currency = 'PHP'),
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'expired', 'cancelled', 'failed')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory_reservations (
  order_id text primary key references public.orders(id) on delete cascade,
  status text not null default 'reserved'
    check (status in ('reserved', 'committed', 'released')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inventory_reservation_items (
  order_id text not null references public.inventory_reservations(order_id) on delete cascade,
  variant_id text not null references public.product_variants(id),
  quantity integer not null check (quantity > 0),
  primary key (order_id, variant_id)
);

create table if not exists public.invoice_snapshots (
  order_id text primary key references public.orders(id) on delete cascade,
  invoice_number text not null unique,
  issued_at timestamptz not null default now(),
  status text not null check (status in ('cod', 'paid')),
  created_at timestamptz not null default now()
);

alter table public.payment_webhook_events
  add column if not exists event_id text;
create unique index if not exists payment_webhook_events_provider_event_idx
  on public.payment_webhook_events(provider, event_id)
  where event_id is not null;

alter table public.payment_sessions enable row level security;
alter table public.inventory_reservations enable row level security;
alter table public.inventory_reservation_items enable row level security;
alter table public.invoice_snapshots enable row level security;

drop policy if exists "owner reads payment sessions" on public.payment_sessions;
create policy "owner reads payment sessions" on public.payment_sessions
  for select to authenticated using (
    exists (select 1 from public.orders o where o.id = order_id and o.user_id = public.request_uid())
  );
drop policy if exists "owner reads invoices" on public.invoice_snapshots;
create policy "owner reads invoices" on public.invoice_snapshots
  for select to authenticated using (
    exists (select 1 from public.orders o where o.id = order_id and o.user_id = public.request_uid())
  );

create or replace function public.delivery_fee(p_delivery_option jsonb)
returns bigint language plpgsql immutable set search_path = '' as $$
begin
  return case p_delivery_option ->> 'id'
    when 'express' then 15000
    when 'same-day' then 25000
    when 'standard' then 8000
    else null
  end;
end $$;

create or replace function public.create_online_payment_order(
  p_idempotency_key text,
  p_shipping_address jsonb,
  p_delivery_option jsonb,
  p_payment_method text default 'gcash'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid text := public.request_uid();
  v_order_id text;
  v_existing public.orders%rowtype;
  v_subtotal bigint := 0;
  v_fee bigint;
  v_item record;
  v_expires timestamptz := now() + interval '30 minutes';
begin
  if v_uid is null or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'unauthenticated' using errcode = '42501';
  end if;
  if p_payment_method not in ('gcash', 'maya', 'card') then
    raise exception 'unsupported online payment method' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'invalid idempotency key' using errcode = '22023';
  end if;
  if jsonb_typeof(p_shipping_address) <> 'object' or jsonb_typeof(p_delivery_option) <> 'object' then
    raise exception 'invalid checkout details' using errcode = '22023';
  end if;
  v_fee := public.delivery_fee(p_delivery_option);
  if v_fee is null then raise exception 'invalid delivery option' using errcode = '22023'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid || ':' || p_idempotency_key, 0));
  select * into v_existing from public.orders where user_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    if v_existing.payment_method <> p_payment_method then
      raise exception 'checkout idempotency key is already bound to another payment method' using errcode = '23505';
    end if;
    return jsonb_build_object('order_id', v_existing.id, 'total_centavos', v_existing.total_centavos,
      'status', v_existing.status, 'payment_status', v_existing.payment_status);
  end if;

  for v_item in
    select ci.variant_id, ci.quantity, pv.product_id, pv.label, pv.price_centavos,
           pv.available, p.name
    from public.cart_items ci
    join public.product_variants pv on pv.id = ci.variant_id
    join public.products p on p.id = pv.product_id
    where ci.user_id = v_uid
    order by ci.variant_id
    for update of pv
  loop
    if v_item.available < v_item.quantity or not exists (
      select 1 from public.products p where p.id = v_item.product_id and p.is_published
    ) then raise exception 'insufficient stock or unavailable product' using errcode = '23514'; end if;
    v_subtotal := v_subtotal + v_item.price_centavos * v_item.quantity;
  end loop;
  if v_subtotal = 0 then raise exception 'cart is empty' using errcode = '22023'; end if;

  v_order_id := p_idempotency_key;
  insert into public.orders (id, user_id, idempotency_key, shipping_address, delivery_option,
    subtotal_centavos, delivery_fee_centavos, total_centavos, status, payment_method,
    payment_provider, payment_status)
  values (v_order_id, v_uid, p_idempotency_key, p_shipping_address, p_delivery_option,
    v_subtotal, v_fee, v_subtotal + v_fee, 'pending_payment', p_payment_method, 'xendit', 'pending');

  insert into public.inventory_reservations(order_id, expires_at)
    values (v_order_id, v_expires);

  for v_item in
    select ci.variant_id, ci.quantity, pv.product_id, pv.label, pv.price_centavos, p.name
    from public.cart_items ci
    join public.product_variants pv on pv.id = ci.variant_id
    join public.products p on p.id = pv.product_id
    where ci.user_id = v_uid order by ci.variant_id
  loop
    update public.product_variants
      set reserved = reserved + v_item.quantity
      where id = v_item.variant_id and available >= v_item.quantity;
    if not found then raise exception 'inventory changed; retry checkout' using errcode = '23514'; end if;
    insert into public.order_items (order_id, product_id, variant_id, product_name, variant_label,
      unit_price_centavos, quantity)
    values (v_order_id, v_item.product_id, v_item.variant_id, v_item.name, v_item.label,
      v_item.price_centavos, v_item.quantity);
    insert into public.inventory_reservation_items(order_id, variant_id, quantity)
      values (v_order_id, v_item.variant_id, v_item.quantity);
  end loop;
  delete from public.cart_items where user_id = v_uid;
  return jsonb_build_object('order_id', v_order_id, 'total_centavos', v_subtotal + v_fee,
    'currency', 'PHP', 'status', 'pending_payment', 'expires_at', v_expires);
end $$;

create or replace function public.create_cod_order(
  p_idempotency_key text, p_shipping_address jsonb, p_delivery_option jsonb
) returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid text := public.request_uid();
  v_order_id text := p_idempotency_key;
  v_existing_order_id text;
  v_subtotal bigint := 0;
  v_fee bigint;
  v_item record;
begin
  if v_uid is null or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'unauthenticated' using errcode = '42501';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'invalid idempotency key' using errcode = '22023';
  end if;
  v_fee := public.delivery_fee(p_delivery_option);
  if v_fee is null then raise exception 'invalid delivery option' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_uid || ':' || p_idempotency_key, 0));
  select id into v_existing_order_id from public.orders where user_id = v_uid and idempotency_key = p_idempotency_key;
  if found then return v_existing_order_id; end if;
  for v_item in
    select ci.variant_id, ci.quantity, pv.product_id, pv.label, pv.price_centavos,
      pv.available, p.name from public.cart_items ci
      join public.product_variants pv on pv.id = ci.variant_id
      join public.products p on p.id = pv.product_id where ci.user_id = v_uid
      order by ci.variant_id for update of pv
  loop
    if v_item.available < v_item.quantity or not exists
      (select 1 from public.products p where p.id = v_item.product_id and p.is_published)
    then raise exception 'insufficient stock or unavailable product' using errcode = '23514'; end if;
    v_subtotal := v_subtotal + v_item.price_centavos * v_item.quantity;
  end loop;
  if v_subtotal = 0 then raise exception 'cart is empty' using errcode = '22023'; end if;
  insert into public.orders (id, user_id, idempotency_key, shipping_address, delivery_option,
    subtotal_centavos, delivery_fee_centavos, total_centavos, status, payment_method, payment_status)
  values (v_order_id, v_uid, p_idempotency_key, p_shipping_address, p_delivery_option,
    v_subtotal, v_fee, v_subtotal + v_fee, 'confirmed', 'cod', 'pending_collection');
  for v_item in
    select ci.variant_id, ci.quantity, pv.product_id, pv.label, pv.price_centavos, p.name
    from public.cart_items ci join public.product_variants pv on pv.id = ci.variant_id
      join public.products p on p.id = pv.product_id where ci.user_id = v_uid order by ci.variant_id
  loop
    update public.product_variants set on_hand = on_hand - v_item.quantity
      where id = v_item.variant_id and on_hand >= v_item.quantity;
    if not found then raise exception 'inventory changed; retry checkout' using errcode = '23514'; end if;
    insert into public.order_items(order_id, product_id, variant_id, product_name, variant_label,
      unit_price_centavos, quantity) values (v_order_id, v_item.product_id, v_item.variant_id,
      v_item.name, v_item.label, v_item.price_centavos, v_item.quantity);
    insert into public.inventory_adjustments(variant_id, order_id, actor_id, delta, reason)
      values (v_item.variant_id, v_order_id, v_uid, -v_item.quantity, 'COD order');
  end loop;
  insert into public.invoice_snapshots(order_id, invoice_number, status)
    values (v_order_id, 'INV-' || upper(left(replace(v_order_id, '-', ''), 12)), 'cod');
  delete from public.cart_items where user_id = v_uid;
  return v_order_id;
end $$;

create or replace function public.settle_xendit_payment(
  p_event_id text, p_session_id text, p_amount_centavos bigint, p_currency text,
  p_status text, p_payment_id text default null
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_order public.orders%rowtype;
  v_session public.payment_sessions%rowtype;
  v_item record;
begin
  if p_event_id is null or p_session_id is null or p_status <> 'COMPLETED' then return false; end if;
  if exists (select 1 from public.payment_webhook_events where provider = 'xendit' and event_id = p_event_id) then return true; end if;
  select o.* into v_order from public.orders o join public.payment_sessions ps on ps.order_id = o.id
    where ps.provider_session_id = p_session_id for update;
  if not found then raise exception 'payment session not found' using errcode = 'P0002'; end if;
  select * into v_session from public.payment_sessions where order_id = v_order.id for update;
  if v_order.total_centavos <> p_amount_centavos or v_session.amount_centavos <> p_amount_centavos
    or p_currency <> 'PHP' or v_order.payment_provider <> 'xendit' then
    raise exception 'payment amount or provider mismatch' using errcode = '22023';
  end if;
  if v_order.payment_status = 'paid' then return true; end if;
  if v_order.status <> 'pending_payment' or not exists (
    select 1 from public.inventory_reservations
    where order_id = v_order.id and status = 'reserved'
  ) then
    raise exception 'payment order is no longer awaiting settlement' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.inventory_reservation_items ri
    join public.product_variants pv on pv.id = ri.variant_id
    where ri.order_id = v_order.id
      and (pv.reserved < ri.quantity or pv.on_hand < ri.quantity)
  ) then
    raise exception 'reserved inventory is no longer available' using errcode = '23514';
  end if;
  insert into public.payment_webhook_events(id, provider, event_id, order_id, event_type)
    values (p_event_id, 'xendit', p_event_id, v_order.id, 'payment_session.completed');
  update public.orders set status = 'confirmed', payment_status = 'paid', payment_reference = p_session_id
    where id = v_order.id;
  update public.payment_sessions set status = 'completed', updated_at = now() where order_id = v_order.id;
  update public.product_variants pv set reserved = pv.reserved - ri.quantity,
    on_hand = pv.on_hand - ri.quantity
    from public.inventory_reservation_items ri where ri.order_id = v_order.id and ri.variant_id = pv.id;
  update public.inventory_reservations set status = 'committed', updated_at = now() where order_id = v_order.id;
  insert into public.invoice_snapshots(order_id, invoice_number, status)
    values (v_order.id, 'INV-' || upper(left(replace(v_order.id, '-', ''), 12)), 'paid')
    on conflict (order_id) do update set status = 'paid';
  return true;
end $$;

create or replace function public.release_xendit_payment(p_event_id text, p_session_id text, p_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_order_id text; v_item record;
begin
  if p_status not in ('EXPIRED', 'CANCELED', 'CANCELLED') then return false; end if;
  if exists (select 1 from public.payment_webhook_events where provider = 'xendit' and event_id = p_event_id) then return true; end if;
  select order_id into v_order_id from public.payment_sessions where provider_session_id = p_session_id for update;
  if v_order_id is null then return false; end if;
  insert into public.payment_webhook_events(id, provider, event_id, order_id, event_type)
    values (p_event_id, 'xendit', p_event_id, v_order_id, 'payment_session.expired');
  if not exists (
    select 1 from public.inventory_reservations
    where order_id = v_order_id and status = 'reserved'
  ) then
    update public.payment_sessions set status = case when p_status = 'CANCELED' then 'cancelled' else lower(p_status) end, updated_at = now()
      where order_id = v_order_id;
    return true;
  end if;
  update public.orders set status = 'cancelled', payment_status = 'expired' where id = v_order_id and status = 'pending_payment';
  update public.product_variants pv set reserved = pv.reserved - ri.quantity
    from public.inventory_reservation_items ri where ri.order_id = v_order_id and ri.variant_id = pv.id;
  update public.inventory_reservations set status = 'released', updated_at = now()
    where order_id = v_order_id and status = 'reserved';
  update public.payment_sessions set status = case when p_status = 'CANCELED' then 'cancelled' else lower(p_status) end, updated_at = now() where order_id = v_order_id;
  return true;
end $$;

create or replace function public.get_checkout_invoice(p_order_id text)
returns jsonb language sql security definer set search_path = '' as $$
  select jsonb_build_object(
    'orderId', o.id, 'invoiceNumber', i.invoice_number, 'issuedAt', i.issued_at,
    'status', i.status, 'items', coalesce((select jsonb_agg(jsonb_build_object(
      'productName', items.product_name, 'variantLabel', items.variant_label,
      'quantity', items.quantity, 'unitPriceCentavos', items.unit_price_centavos,
      'lineTotalCentavos', items.unit_price_centavos * items.quantity
    ) order by items.product_name) from public.order_items items where items.order_id = o.id), '[]'::jsonb),
    'subtotalCentavos', o.subtotal_centavos, 'deliveryFeeCentavos', o.delivery_fee_centavos,
    'totalCentavos', o.total_centavos, 'paymentMethod', o.payment_method,
    'paymentStatus', o.payment_status
  ) from public.orders o join public.invoice_snapshots i on i.order_id = o.id
    where o.id = p_order_id and (o.user_id = public.request_uid() or public.is_admin());
$$;

create or replace function public.record_xendit_session(
  p_order_id text, p_session_id text, p_checkout_url text,
  p_expires_at timestamptz, p_amount_centavos bigint
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.orders where id = p_order_id and user_id = public.request_uid()
      and status = 'pending_payment' and payment_provider = 'xendit'
      and total_centavos = p_amount_centavos
  ) then raise exception 'payment order is not valid' using errcode = '42501'; end if;
  insert into public.payment_sessions(order_id, provider, provider_session_id, checkout_url,
    amount_centavos, currency, expires_at)
  values (p_order_id, 'xendit', p_session_id, p_checkout_url, p_amount_centavos, 'PHP', p_expires_at)
  on conflict (order_id) do update set provider_session_id = excluded.provider_session_id,
    checkout_url = excluded.checkout_url, expires_at = excluded.expires_at, updated_at = now();
  return true;
end $$;

create or replace function public.release_checkout_reservation(p_order_id text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_released integer;
begin
  if not exists (select 1 from public.orders where id = p_order_id and user_id = public.request_uid()
    and status = 'pending_payment') then return false; end if;
  update public.inventory_reservations set status = 'released', updated_at = now()
    where order_id = p_order_id and status = 'reserved';
  get diagnostics v_released = row_count;
  if v_released = 0 then return true; end if;
  update public.product_variants pv set reserved = pv.reserved - ri.quantity
    from public.inventory_reservation_items ri
    where ri.order_id = p_order_id and ri.variant_id = pv.id;
  update public.orders set status = 'cancelled', payment_status = 'failed' where id = p_order_id;
  return true;
end $$;

revoke all on function public.create_online_payment_order(text, jsonb, jsonb, text) from public, anon;
grant execute on function public.create_online_payment_order(text, jsonb, jsonb, text) to authenticated;
revoke all on function public.create_cod_order(text, jsonb, jsonb) from public, anon;
grant execute on function public.create_cod_order(text, jsonb, jsonb) to authenticated;
revoke all on function public.settle_xendit_payment(text, text, bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.release_xendit_payment(text, text, text) from public, anon, authenticated;
revoke all on function public.record_xendit_session(text, text, text, timestamptz, bigint) from public, anon;
grant execute on function public.record_xendit_session(text, text, text, timestamptz, bigint) to authenticated;
revoke all on function public.release_checkout_reservation(text) from public, anon, authenticated;
revoke all on function public.get_checkout_invoice(text) from public, anon;
grant execute on function public.get_checkout_invoice(text) to authenticated;
