import 'package:supabase_flutter/supabase_flutter.dart';

const scentifySupabaseUrl = String.fromEnvironment(
  'SCENTIFY_SUPABASE_URL',
  defaultValue: 'https://jnukqrpkyqwoatesuelp.supabase.co',
);
const scentifySupabasePublishableKey = String.fromEnvironment(
  'SCENTIFY_SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_dKitRNf0q2ARs9k_m86KQQ_h0pFe5-6',
);

Future<void> initializeScentifySupabase() async {
  await Supabase.initialize(
    url: scentifySupabaseUrl,
    publishableKey: scentifySupabasePublishableKey,
  );
}
