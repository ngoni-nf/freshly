import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

/// A single source of truth for a job's state.
///
/// Declared once and imported by every screen that touches it. Two providers
/// fetching the same booking is a silent bug: the PIN pad invalidates one, the
/// job screen watches the other, and the button never changes.
final jobProvider = FutureProvider.autoDispose.family<Booking, String>(
  (ref, id) => ref.watch(apiProvider).booking(id),
);
