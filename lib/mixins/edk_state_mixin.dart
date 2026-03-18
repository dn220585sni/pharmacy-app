import 'package:flutter/material.dart';
import '../models/edk_offer.dart';

/// Shared ЄДК (pharmaceutical substitution) state management.
///
/// Used by [PosScreenState] and [OrdersPanelState] to avoid duplicating
/// EDK offer activation / dismissal / clearing logic.
mixin EdkStateMixin<T extends StatefulWidget> on State<T> {
  EdkOffer? activeEdkOffer;
  final Set<String> dismissedEdkIds = {};

  bool get isEdkActive => activeEdkOffer != null;

  /// Dismiss the currently active EDK offer (adds donor to dismissed set).
  void dismissActiveEdk() {
    if (activeEdkOffer == null) return;
    setState(() {
      dismissedEdkIds.add(activeEdkOffer!.donorDrugId);
      activeEdkOffer = null;
    });
  }

  /// Clear all EDK state (offer + dismissed set).
  void clearEdkState() {
    activeEdkOffer = null;
    dismissedEdkIds.clear();
  }

  /// Try to activate an EDK offer for [key] from [offers] map.
  /// Returns true if an offer was activated.
  bool tryActivateEdk(String key, Map<String, EdkOffer> offers) {
    if (dismissedEdkIds.contains(key)) return false;
    final offer = offers[key];
    if (offer == null) return false;
    setState(() => activeEdkOffer = offer);
    return true;
  }
}
