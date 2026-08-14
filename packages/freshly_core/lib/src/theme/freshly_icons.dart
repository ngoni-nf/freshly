import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The app's icon vocabulary, in Apple's language.
///
/// SF Symbols is licensed for building software for Apple's own platforms and
/// cannot ship inside an Android binary. `cupertino_icons` is the Flutter
/// team's freely licensed set drawn from the same shapes, so it is lawful on
/// every platform and sits correctly next to SF type — thin strokes, rounded
/// terminals, optically lighter than Material's.
///
/// Named for what the icon means rather than what it depicts, so a screen says
/// `FreshlyIcons.wallet` and this file decides what that looks like. Changing
/// the whole product's iconography is then one edit here instead of a hundred
/// and thirty across two apps.
///
/// A handful stay Material on purpose. Where Cupertino has no equivalent —
/// most of the beauty-specific category glyphs, which no general icon set
/// contains — a Material outline is closer to right than a bad Cupertino
/// substitute would be, and mixing is less visible than a wrong metaphor.
class FreshlyIcons {
  const FreshlyIcons._();

  // ─── Navigation and structure ────────────────────────────────────────────
  static const IconData chevronRight = CupertinoIcons.chevron_forward;
  static const IconData expandMore = CupertinoIcons.chevron_down;
  static const IconData close = CupertinoIcons.xmark;
  static const IconData check = CupertinoIcons.check_mark;

  /// Read, as against merely delivered. The two-tick convention is understood
  /// everywhere without a legend, which a bespoke indicator would need.
  static const IconData checkDouble = CupertinoIcons.checkmark_alt_circle_fill;
  static const IconData checkCircle = CupertinoIcons.check_mark_circled_solid;
  static const IconData add = CupertinoIcons.add;
  static const IconData addCircle = CupertinoIcons.add_circled;
  static const IconData search = CupertinoIcons.search;
  static const IconData searchOff = CupertinoIcons.search;
  static const IconData tune = CupertinoIcons.slider_horizontal_3;
  static const IconData backspace = CupertinoIcons.delete_left;
  static const IconData delete = CupertinoIcons.delete;
  static const IconData send = CupertinoIcons.arrow_up_circle_fill;
  static const IconData block = CupertinoIcons.nosign;
  static const IconData trendingUp = CupertinoIcons.arrow_up_right;

  // ─── People and identity ─────────────────────────────────────────────────
  static const IconData person = CupertinoIcons.person;
  static const IconData people = CupertinoIcons.person_2;
  static const IconData verified = CupertinoIcons.checkmark_seal_fill;
  static const IconData verifiedOutline = CupertinoIcons.checkmark_seal;
  static const IconData shield = CupertinoIcons.shield;
  static const IconData lock = CupertinoIcons.lock;
  static const IconData lockClock = CupertinoIcons.lock_shield;
  static const IconData pin = CupertinoIcons.number;

  // ─── Place and movement ──────────────────────────────────────────────────
  static const IconData location = CupertinoIcons.location;
  static const IconData nearMe = CupertinoIcons.location_north;
  static const IconData navigation = CupertinoIcons.location_north_fill;
  static const IconData car = CupertinoIcons.car_detailed;
  static const IconData storefront = CupertinoIcons.building_2_fill;

  // ─── Time ────────────────────────────────────────────────────────────────
  static const IconData clock = CupertinoIcons.clock;
  static const IconData schedule = CupertinoIcons.clock;
  static const IconData calendar = CupertinoIcons.calendar;
  static const IconData calendarToday = CupertinoIcons.calendar_today;
  static const IconData dateRange = CupertinoIcons.calendar;
  static const IconData eventAvailable = CupertinoIcons.calendar_badge_plus;
  static const IconData hourglass = CupertinoIcons.hourglass;
  static const IconData timelapse = CupertinoIcons.timer;

  // ─── Communication ───────────────────────────────────────────────────────
  static const IconData chat = CupertinoIcons.chat_bubble;
  static const IconData message = CupertinoIcons.chat_bubble_text;
  static const IconData phone = CupertinoIcons.phone;
  static const IconData call = CupertinoIcons.phone_fill;
  static const IconData mobile = CupertinoIcons.device_phone_portrait;
  static const IconData notifications = CupertinoIcons.bell;
  static const IconData mic = CupertinoIcons.mic;

  // ─── Money ───────────────────────────────────────────────────────────────
  static const IconData wallet = CupertinoIcons.creditcard;
  static const IconData card = CupertinoIcons.creditcard_fill;
  static const IconData bank = CupertinoIcons.building_2_fill;
  static const IconData receipt = CupertinoIcons.doc_text;

  // ─── Media ───────────────────────────────────────────────────────────────
  static const IconData camera = CupertinoIcons.camera;
  static const IconData addPhoto = CupertinoIcons.camera_fill;
  static const IconData gallery = CupertinoIcons.photo_on_rectangle;
  static const IconData eye = CupertinoIcons.eye;

  // ─── Status and meaning ──────────────────────────────────────────────────
  static const IconData info = CupertinoIcons.info_circle;
  static const IconData error = CupertinoIcons.exclamationmark_circle;
  static const IconData warning = CupertinoIcons.exclamationmark_triangle;
  static const IconData star = CupertinoIcons.star_fill;
  static const IconData sparkles = CupertinoIcons.sparkles;
  static const IconData bolt = CupertinoIcons.bolt_fill;
  static const IconData battery = CupertinoIcons.battery_charging;
  static const IconData sos = CupertinoIcons.exclamationmark_shield_fill;
  static const IconData category = CupertinoIcons.square_grid_2x2;

  // ─── Services ────────────────────────────────────────────────────────────
  // No general icon set contains a glyph for locs or for lash extensions, so
  // these stay Material rather than being forced into a wrong metaphor.
  static const IconData barber = Icons.content_cut;
  static const IconData beard = Icons.face_outlined;
  static const IconData scalp = Icons.psychology_alt_outlined;
  static const IconData hair = Icons.brush_outlined;
  static const IconData braiding = Icons.waves;
  static const IconData locs = Icons.grain;
  static const IconData extensions = Icons.layers_outlined;
  static const IconData colour = Icons.palette_outlined;
  static const IconData nails = Icons.back_hand_outlined;
  static const IconData makeup = Icons.face_retouching_natural;
  static const IconData lashes = Icons.visibility_outlined;
  static const IconData brows = Icons.remove_red_eye_outlined;
  static const IconData aesthetics = Icons.spa_outlined;
  static const IconData bodyGrooming = Icons.auto_fix_high_outlined;
  static const IconData massage = Icons.self_improvement;
  static const IconData style = Icons.style_outlined;
}
