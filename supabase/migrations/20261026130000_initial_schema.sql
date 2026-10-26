create table public.brands (
  id text primary key,
  name text not null,
  logo_url text
);

create table public.products (
  id text primary key,
  brand_id text not null references public.brands(id),
  name text not null,
  description text not null default '',
  gender text not null,
  family text not null,
  concentration text not null,
  occasions text[] not null default '{}',
  vibes text[] not null default '{}',
  top_notes text[] not null default '{}',
  heart_notes text[] not null default '{}',
  base_notes text[] not null default '{}',
  image_urls text[] not null default '{}',
  tags text[] not null default '{}',
  authenticity_note text not null default '',
  is_published boolean not null default false,
  average_rating numeric(3,2) not null default 0 check (average_rating between 0 and 5),
  review_count integer not null default 0 check (review_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.product_variants (
  id text primary key,
  product_id text not null references public.products(id) on delete cascade,
  label text not null,
  volume_ml integer not null check (volume_ml > 0),
  price_centavos bigint not null check (price_centavos >= 0),
  on_hand integer not null default 0 check (on_hand >= 0),
  reserved integer not null default 0 check (reserved >= 0 and reserved <= on_hand),
  available integer generated always as (on_hand - reserved) stored,
  unique (product_id, label)
);

create table public.customers (
  id text primary key,
  email text not null default '',
  display_name text not null default '',
  role text not null default 'customer' check (role in ('customer', 'admin', 'superadmin')),
  created_at timestamptz not null default now()
);

create table public.addresses (
  id text primary key,
  user_id text not null references public.customers(id) on delete cascade,
  recipient_name text not null,
  phone text not null,
  line1 text not null,
  line2 text not null default '',
  barangay text not null default '',
  city text not null,
  province text not null,
  postal_code text not null default '',
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.carts (
  user_id text primary key references public.customers(id) on delete cascade,
  updated_at timestamptz not null default now()
);

create table public.cart_items (
  user_id text not null references public.carts(user_id) on delete cascade,
  variant_id text not null references public.product_variants(id),
  quantity integer not null check (quantity > 0 and quantity <= 100),
  primary key (user_id, variant_id)
);

create table public.wishlists (
  user_id text not null references public.customers(id) on delete cascade,
  product_id text not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table public.orders (
  id text primary key,
  user_id text not null references public.customers(id),
  idempotency_key text not null,
  shipping_address jsonb not null,
  delivery_option jsonb not null,
  subtotal_centavos bigint not null check (subtotal_centavos >= 0),
  delivery_fee_centavos bigint not null check (delivery_fee_centavos >= 0),
  total_centavos bigint not null check (total_centavos = subtotal_centavos + delivery_fee_centavos),
  status text not null default 'pending_confirmation',
  payment_method text not null default 'cod' check (payment_method in ('cod', 'gcash', 'maya', 'card')),
  payment_provider text,
  payment_reference text,
  payment_status text,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);

create table public.order_items (
  order_id text not null references public.orders(id) on delete cascade,
  product_id text not null references public.products(id),
  variant_id text not null references public.product_variants(id),
  product_name text not null,
  variant_label text not null,
  unit_price_centavos bigint not null check (unit_price_centavos >= 0),
  quantity integer not null check (quantity > 0),
  primary key (order_id, variant_id)
);

create table public.inventory_adjustments (
  id uuid primary key default gen_random_uuid(),
  variant_id text not null references public.product_variants(id),
  order_id text references public.orders(id),
  actor_id text not null,
  delta integer not null check (delta <> 0),
  reason text not null,
  created_at timestamptz not null default now()
);

create table public.reviews (
  id text primary key,
  order_id text not null references public.orders(id),
  user_id text not null references public.customers(id),
  product_id text not null references public.products(id),
  variant_id text not null references public.product_variants(id),
  rating integer not null check (rating between 1 and 5),
  title text not null default '',
  comment text not null default '' check (char_length(comment) <= 1000),
  created_at timestamptz not null default now(),
  unique (order_id, product_id)
);

create table public.payment_webhook_events (
  id text primary key,
  provider text not null,
  order_id text not null references public.orders(id),
  event_type text not null,
  received_at timestamptz not null default now()
);

create index products_published_idx on public.products (is_published, name);
create index variants_product_idx on public.product_variants (product_id);
create index addresses_owner_idx on public.addresses (user_id);
create index orders_owner_idx on public.orders (user_id, created_at desc);
create index reviews_product_idx on public.reviews (product_id, created_at desc);

create function public.is_admin() returns boolean
language sql stable as $$
  select coalesce((auth.jwt() ->> 'admin')::boolean, false)
      or coalesce((auth.jwt() ->> 'superadmin')::boolean, false)
$$;

create view public.catalog_variants with (security_barrier = true) as
  select v.id, v.product_id, v.label, v.volume_ml, v.price_centavos, v.available
  from public.product_variants v join public.products p on p.id = v.product_id
  where p.is_published;
create view public.admin_variants with (security_barrier = true) as
  select id, product_id, label, volume_ml, price_centavos, on_hand, reserved, available
  from public.product_variants where public.is_admin();

create function public.request_uid() returns text
language sql stable as $$ select auth.jwt() ->> 'sub' $$;

create function public.ensure_customer_profile() returns void
language plpgsql security definer set search_path = '' as $$
declare v_uid text := public.request_uid();
begin
  if v_uid is null or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'unauthenticated' using errcode = '42501';
  end if;
  insert into public.customers (id, email, display_name, role)
  values (v_uid, coalesce(auth.jwt() ->> 'email', ''),
    coalesce(auth.jwt() ->> 'name', ''), 'customer')
  on conflict (id) do nothing;
end $$;

alter table public.brands enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.addresses enable row level security;
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.wishlists enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.inventory_adjustments enable row level security;
alter table public.reviews enable row level security;
alter table public.payment_webhook_events enable row level security;

create policy "published brands are readable" on public.brands for select to anon, authenticated
  using (exists (select 1 from public.products p where p.brand_id = brands.id and p.is_published));
create policy "published products are readable" on public.products for select to anon, authenticated using (is_published);
create policy "available variants are readable" on public.product_variants for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.is_published));
create policy "published reviews are readable" on public.reviews for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.is_published));
create policy "customer reads own profile" on public.customers for select to authenticated using (id = public.request_uid() or public.is_admin());
create policy "admins read all catalog" on public.products for select to authenticated using (public.is_admin());
create policy "admins read all variants" on public.product_variants for select to authenticated using (public.is_admin());
create policy "customer edits own non-role profile" on public.customers for update to authenticated
  using (id = public.request_uid()) with check (id = public.request_uid() and role = 'customer');
create policy "owner manages addresses" on public.addresses for all to authenticated
  using (user_id = public.request_uid() or public.is_admin()) with check (user_id = public.request_uid() or public.is_admin());
create policy "owner manages cart" on public.carts for all to authenticated
  using (user_id = public.request_uid()) with check (user_id = public.request_uid());
create policy "owner manages cart items" on public.cart_items for all to authenticated
  using (user_id = public.request_uid()) with check (user_id = public.request_uid());
create policy "owner manages wishlist" on public.wishlists for all to authenticated
  using (user_id = public.request_uid()) with check (user_id = public.request_uid());
create policy "owner reads orders" on public.orders for select to authenticated using (user_id = public.request_uid() or public.is_admin());
create policy "owner reads order items" on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.user_id = public.request_uid() or public.is_admin())));
create policy "admin reads inventory audit" on public.inventory_adjustments for select to authenticated using (public.is_admin());
create policy "owner reads reviews" on public.reviews for select to authenticated using (user_id = public.request_uid() or public.is_admin());

create function public.create_cod_order(p_idempotency_key text, p_shipping_address jsonb, p_delivery_option jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid text := public.request_uid();
  v_order_id text := gen_random_uuid()::text;
  v_existing_order_id text;
  v_subtotal bigint;
  v_fee bigint;
  v_item record;
begin
  if v_uid is null or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'unauthenticated' using errcode = '42501';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 128 then
    raise exception 'invalid idempotency key' using errcode = '22023';
  end if;
  if jsonb_typeof(p_shipping_address) <> 'object' or jsonb_typeof(p_delivery_option) <> 'object' then
    raise exception 'invalid checkout details' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid || ':' || p_idempotency_key, 0));
  select id into v_existing_order_id from public.orders where user_id = v_uid and idempotency_key = p_idempotency_key;
  if found then return v_existing_order_id; end if;

  perform 1 from public.cart_items where user_id = v_uid for update;

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
    v_subtotal := coalesce(v_subtotal, 0) + v_item.price_centavos * v_item.quantity;
  end loop;
  if v_subtotal is null or v_subtotal = 0 then raise exception 'cart is empty' using errcode = '22023'; end if;

  if p_delivery_option ->> 'id' = 'express' then v_fee := 15000;
  elsif p_delivery_option ->> 'id' = 'same-day' then
    if lower(trim(coalesce(p_shipping_address ->> 'province', ''))) not in
      ('ncr', 'national capital region', 'metro manila') then
      raise exception 'same-day delivery is only available in NCR' using errcode = '22023';
    end if;
    if lower(trim(coalesce(p_shipping_address ->> 'city', ''))) not in
      ('caloocan', 'las pinas', 'makati', 'malabon', 'mandaluyong', 'manila', 'marikina',
       'muntinlupa', 'navotas', 'paranaque', 'pasay', 'pasig', 'pateros', 'quezon city',
       'san juan', 'taguig', 'valenzuela') then
      raise exception 'same-day delivery is only available in NCR' using errcode = '22023';
    end if;
    v_fee := 25000;
  elsif p_delivery_option ->> 'id' = 'standard' then v_fee := 8000;
  else raise exception 'invalid delivery option' using errcode = '22023';
  end if;
  insert into public.orders (id, user_id, idempotency_key, shipping_address, delivery_option,
    subtotal_centavos, delivery_fee_centavos, total_centavos)
  values (v_order_id, v_uid, p_idempotency_key, p_shipping_address, p_delivery_option,
    v_subtotal, v_fee, v_subtotal + v_fee);

  for v_item in
    select ci.variant_id, ci.quantity, pv.product_id, pv.label, pv.price_centavos, p.name
    from public.cart_items ci join public.product_variants pv on pv.id = ci.variant_id
    join public.products p on p.id = pv.product_id where ci.user_id = v_uid order by ci.variant_id
  loop
    update public.product_variants set on_hand = on_hand - v_item.quantity where id = v_item.variant_id;
    insert into public.order_items (order_id, product_id, variant_id, product_name, variant_label, unit_price_centavos, quantity)
    values (v_order_id, v_item.product_id, v_item.variant_id, v_item.name, v_item.label, v_item.price_centavos, v_item.quantity);
    insert into public.inventory_adjustments (variant_id, order_id, actor_id, delta, reason)
    values (v_item.variant_id, v_order_id, v_uid, -v_item.quantity, 'COD order');
  end loop;
  delete from public.cart_items where user_id = v_uid;
  return v_order_id;
end $$;

create function public.admin_adjust_stock(p_variant_id text, p_delta integer, p_reason text)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_available integer;
begin
  if not public.is_admin() or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'admin access required' using errcode = '42501';
  end if;
  if p_delta = 0 or length(trim(coalesce(p_reason, ''))) not between 3 and 240 then
    raise exception 'invalid inventory adjustment' using errcode = '22023';
  end if;
  update public.product_variants set on_hand = on_hand + p_delta
  where id = p_variant_id and on_hand + p_delta >= reserved
  returning available into v_available;
  if not found then raise exception 'variant missing or stock would be negative' using errcode = '23514'; end if;
  insert into public.inventory_adjustments (variant_id, actor_id, delta, reason)
  values (p_variant_id, public.request_uid(), p_delta, trim(p_reason));
  return v_available;
end $$;

create function public.submit_review(
  p_id text, p_order_id text, p_product_id text, p_variant_id text,
  p_rating integer, p_title text, p_comment text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_uid text := public.request_uid();
begin
  if v_uid is null or coalesce(auth.jwt() ->> 'role', '') <> 'authenticated' then
    raise exception 'unauthenticated' using errcode = '42501';
  end if;
  if p_rating not between 1 and 5 or length(coalesce(p_comment, '')) > 1000 then
    raise exception 'invalid review' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.orders o join public.order_items oi on oi.order_id = o.id
    where o.id = p_order_id and o.user_id = v_uid and o.status = 'delivered'
      and oi.product_id = p_product_id and oi.variant_id = p_variant_id
  ) then raise exception 'delivered purchase required' using errcode = '42501'; end if;

  insert into public.reviews (id, order_id, user_id, product_id, variant_id, rating, title, comment)
  values (p_id, p_order_id, v_uid, p_product_id, p_variant_id, p_rating,
    left(coalesce(p_title, ''), 120), coalesce(p_comment, ''));
  update public.products p set
    average_rating = (select avg(r.rating)::numeric(3,2) from public.reviews r where r.product_id = p.id),
    review_count = (select count(*) from public.reviews r where r.product_id = p.id),
    updated_at = now()
  where p.id = p_product_id;
end $$;

revoke all on function public.ensure_customer_profile() from public, anon;
grant execute on function public.ensure_customer_profile() to authenticated;
revoke all on function public.create_cod_order(text, jsonb, jsonb) from public, anon;
grant execute on function public.create_cod_order(text, jsonb, jsonb) to authenticated;
revoke all on function public.admin_adjust_stock(text, integer, text) from public, anon;
grant execute on function public.admin_adjust_stock(text, integer, text) to authenticated;
revoke all on function public.submit_review(text, text, text, text, integer, text, text) from public, anon;
grant execute on function public.submit_review(text, text, text, text, integer, text, text) to authenticated;

grant select on public.brands, public.products, public.product_variants, public.reviews to anon, authenticated;
revoke select on public.product_variants from anon, authenticated;
grant select on public.catalog_variants to anon, authenticated;
grant select on public.admin_variants to authenticated;
grant select, update on public.customers to authenticated;
grant select, insert, update, delete on public.addresses, public.carts, public.cart_items, public.wishlists to authenticated;
grant select on public.orders, public.order_items, public.inventory_adjustments to authenticated;
