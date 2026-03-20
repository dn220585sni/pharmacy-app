import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fallback for non-web platforms — opens in external browser.
void showInstructionDialog(BuildContext context, String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
